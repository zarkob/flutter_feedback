/**
 * Feedback Relay — Cloudflare Worker.
 *
 * Receives in-app feedback from the `feedback_relay` Flutter package and files
 * it as a GitHub issue (screenshot attached via imgbb) in the product's repo.
 *
 * Security model: the app sends ONLY an RSA-OAEP-encrypted product id. The
 * Worker decrypts it with its private key and looks up that product's
 * {github_repo, github_token, imgbb_key} bundle from its own secret store.
 * No secret ever ships in the app.
 *
 * See docs/OPERATOR_RUNBOOK.md for provisioning.
 */

// ─── Configuration ────────────────────────────────────────────────────────────

/** Max decoded screenshot size (4 MB). Protects against abuse. */
const MAX_SCREENSHOT_BYTES = 4 * 1024 * 1024;

/** Max feedback text length. */
const MAX_TEXT_LENGTH = 10_000;

/** Rate limit: max feedback submissions per window per IP. */
const RATE_LIMIT_MAX = 5;

/** Rate limit window in seconds (60s). */
const RATE_LIMIT_WINDOW_SECONDS = 60;

// ─── Types ────────────────────────────────────────────────────────────────────

interface FeedbackRequest {
  product_id_enc: string;
  screenshot_b64: string;
  text: string;
  app_version?: string;
  device_info?: Record<string, unknown>;
}

interface ProductBundle {
  github_repo: string;
  github_token: string;
  imgbb_key: string;
}

interface Env {
  FEEDBACK_PRIVATE_KEY_PKCS8: string;
  FEEDBACK_RATELIMIT: KVNamespace;
  // Per-product bundles: PRODUCT_<UPPER_ID>
  [key: `PRODUCT_${string}`]: string | undefined;
}

// ─── Entry ────────────────────────────────────────────────────────────────────

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    // Only POST /feedback is supported.
    const url = new URL(request.url);
    if (request.method !== 'POST' || url.pathname !== '/feedback') {
      return json({ ok: false, error: 'Not found' }, 404);
    }

    try {
      return await handleFeedback(request, env);
    } catch (err) {
      // Never leak internals (which could include secret material) to clients.
      return json({ ok: false, error: 'Internal error' }, 500);
    }
  },
};

// ─── Handler ──────────────────────────────────────────────────────────────────

async function handleFeedback(request: Request, env: Env): Promise<Response> {
  // 1. Parse + validate input.
  let body: FeedbackRequest;
  try {
    body = (await request.json()) as FeedbackRequest;
  } catch {
    return json({ ok: false, error: 'Invalid JSON body' }, 400);
  }

  const validationError = validateInput(body);
  if (validationError) {
    return json({ ok: false, error: validationError }, 400);
  }

  // 2. Rate-limit by IP.
  const ip = request.headers.get('CF-Connecting-IP') ?? 'unknown';
  const rateLimit = await checkRateLimit(env, ip);
  if (!rateLimit.allowed) {
    return json(
      { ok: false, error: 'Rate limit exceeded. Try again later.' },
      429,
    );
  }

  // 3. Decrypt the product id.
  let productId: string;
  try {
    productId = await decryptProductId(env.FEEDBACK_PRIVATE_KEY_PKCS8, body.product_id_enc);
  } catch {
    // Decryption failure = wrong key, tampered ciphertext, or non-OAEP padding.
    return json({ ok: false, error: 'Invalid product id' }, 400);
  }

  // 4. Look up the product's secret bundle.
  const bundle = lookupBundle(env, productId);
  if (!bundle) {
    return json({ ok: false, error: 'Unknown product' }, 400);
  }

  // 5. Upload the screenshot to imgbb.
  let imageUrl: string;
  try {
    imageUrl = await uploadToImgbb(bundle.imgbb_key, body.screenshot_b64);
  } catch {
    return json({ ok: false, error: 'Screenshot upload failed' }, 502);
  }

  // 6. Create the GitHub issue.
  let issueUrl: string;
  try {
    issueUrl = await createGitHubIssue(bundle, {
      text: body.text,
      imageUrl,
      appVersion: body.app_version,
      deviceInfo: body.device_info,
    });
  } catch {
    return json({ ok: false, error: 'Issue creation failed' }, 502);
  }

  // 7. Success.
  return json({ ok: true, issue_url: issueUrl }, 200);
}

// ─── Validation ───────────────────────────────────────────────────────────────

function validateInput(body: FeedbackRequest): string | null {
  if (typeof body.product_id_enc !== 'string' || body.product_id_enc.length === 0) {
    return 'Missing product_id_enc';
  }
  if (typeof body.screenshot_b64 !== 'string' || body.screenshot_b64.length === 0) {
    return 'Missing screenshot_b64';
  }
  if (typeof body.text !== 'string' || body.text.trim().length === 0) {
    return 'Missing text';
  }
  if (body.text.length > MAX_TEXT_LENGTH) {
    return 'Feedback text too long';
  }
  // Guard the decoded size before any further processing.
  const decodedLen = estimateBase64DecodedSize(body.screenshot_b64);
  if (decodedLen > MAX_SCREENSHOT_BYTES) {
    return 'Screenshot too large';
  }
  return null;
}

/** Upper-bound estimate of the decoded byte length of a base64 string. */
function estimateBase64DecodedSize(b64: string): number {
  const len = b64.length;
  const padding = b64.endsWith('==') ? 2 : b64.endsWith('=') ? 1 : 0;
  return Math.floor(len * 3 / 4) - padding;
}

// ─── Rate limiting ────────────────────────────────────────────────────────────

async function checkRateLimit(env: Env, ip: string): Promise<{ allowed: boolean }> {
  if (ip === 'unknown') {
    // No IP header — allow (Cloudflare always sets CF-Connecting-IP in prod).
    return { allowed: true };
  }
  const key = `rl:${ip}`;
  const now = Math.floor(Date.now() / 1000);
  const raw = await env.FEEDBACK_RATELIMIT.get(key);
  const count = raw ? parseInt(raw, 10) : 0;

  if (count >= RATE_LIMIT_MAX) {
    return { allowed: false };
  }

  // Increment. On the first hit of a window, set TTL so counters expire.
  await env.FEEDBACK_RATELIMIT.put(key, String(count + 1), {
    expirationTtl: RATE_LIMIT_WINDOW_SECONDS,
  });
  return { allowed: true };
}

// ─── Decryption (Web Crypto RSA-OAEP / SHA-256) ───────────────────────────────

let cachedKey: CryptoKey | null = null;

async function decryptProductId(pkcs8B64: string, ciphertextB64: string): Promise<string> {
  if (!cachedKey) {
    const der = base64ToBytes(pkcs8B64);
    cachedKey = await crypto.subtle.importKey(
      'pkcs8',
      der,
      { name: 'RSA-OAEP', hash: 'SHA-256' },
      false,
      ['decrypt'],
    );
  }

  const ciphertext = base64ToBytes(ciphertextB64);
  const plaintextBuf = await crypto.subtle.decrypt(
    { name: 'RSA-OAEP' },
    cachedKey,
    ciphertext,
  );
  const plaintext = new TextDecoder().decode(plaintextBuf);

  // Sanity-check the decrypted id is a reasonable identifier.
  if (!/^[a-z0-9][a-z0-9_-]*$/i.test(plaintext)) {
    throw new Error('decrypted id is not a valid identifier');
  }
  return plaintext;
}

// ─── Product bundle lookup ────────────────────────────────────────────────────

function lookupBundle(env: Env, productId: string): ProductBundle | null {
  // Normalize: uppercase, non-alphanumeric → underscore. "my-app" → "MY_APP".
  const suffix = productId.toUpperCase().replace(/[^A-Z0-9]/g, '_');
  const secretName = `PRODUCT_${suffix}` as `PRODUCT_${string}`;
  const raw = env[secretName];
  if (!raw) {
    return null;
  }
  try {
    const bundle = JSON.parse(raw) as ProductBundle;
    if (
      typeof bundle.github_repo !== 'string' ||
      typeof bundle.github_token !== 'string' ||
      typeof bundle.imgbb_key !== 'string'
    ) {
      return null;
    }
    return bundle;
  } catch {
    return null;
  }
}

// ─── imgbb upload ─────────────────────────────────────────────────────────────

async function uploadToImgbb(apiKey: string, screenshotB64: string): Promise<string> {
  const params = new URLSearchParams();
  params.set('key', apiKey);
  params.set('image', screenshotB64); // imgbb takes base64 directly

  const res = await fetch('https://api.imgbb.com/1/upload', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: params.toString(),
  });

  if (!res.ok) {
    throw new Error(`imgbb HTTP ${res.status}`);
  }

  const data = (await res.json()) as {
    data?: { display_url?: string; url?: string };
  };
  const url = data.data?.display_url ?? data.data?.url;
  if (!url) {
    throw new Error('imgbb returned no url');
  }
  return url;
}

// ─── GitHub issue creation ────────────────────────────────────────────────────

interface IssueInput {
  text: string;
  imageUrl: string;
  appVersion?: string;
  deviceInfo?: Record<string, unknown>;
}

async function createGitHubIssue(bundle: ProductBundle, input: IssueInput): Promise<string> {
  const body = buildIssueBody(input);

  const res = await fetch(`https://api.github.com/repos/${bundle.github_repo}/issues`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${bundle.github_token}`,
      Accept: 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      'Content-Type': 'application/json',
      'User-Agent': 'feedback-relay-worker',
    },
    body: JSON.stringify({
      title: truncateTitle(input.text),
      body,
      labels: ['feedback', 'from-app'],
    }),
  });

  if (!res.ok) {
    throw new Error(`github HTTP ${res.status}`);
  }

  const data = (await res.json()) as { html_url?: string };
  if (!data.html_url) {
    throw new Error('github returned no issue url');
  }
  return data.html_url;
}

function truncateTitle(text: string): string {
  const firstLine = text.split('\n')[0].trim();
  const title = firstLine.length > 0 ? firstLine : text.trim();
  const prefix = 'Feedback: ';
  const max = 80;
  if (title.length > max - prefix.length) {
    return prefix + title.slice(0, max - prefix.length - 1) + '…';
  }
  return prefix + title;
}

function buildIssueBody(input: IssueInput): string {
  const lines: string[] = [];
  lines.push('### Feedback');
  lines.push('');
  lines.push(input.text);
  lines.push('');
  lines.push('### Screenshot');
  lines.push('');
  lines.push(`![screenshot](${input.imageUrl})`);
  lines.push('');

  const meta: string[] = [];
  if (input.appVersion) {
    meta.push(`- **App version**: ${input.appVersion}`);
  }
  if (input.deviceInfo && Object.keys(input.deviceInfo).length > 0) {
    meta.push('- **Device info**:');
    for (const [key, value] of Object.entries(input.deviceInfo)) {
      meta.push(`  - ${key}: ${typeof value === 'object' ? JSON.stringify(value) : String(value)}`);
    }
  }
  if (meta.length > 0) {
    lines.push('<details><summary>Environment</summary>');
    lines.push('');
    lines.push(...meta);
    lines.push('');
    lines.push('</details>');
  }

  return lines.join('\n');
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

function base64ToBytes(b64: string): Uint8Array {
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}
