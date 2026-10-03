/**
 * The destination map and the tester access check.
 *
 * The public product id selects one destination. The relay keeps every
 * destination secret. A tester token is checked against the stored hash list
 * of that product, so the product id alone never grants access.
 */

/** One tester of one product. Only the hash of the token is stored. */
export interface Tester {
  name: string;
  token_sha256: string;
}

/** One product destination and its secrets. */
export interface ProductBundle {
  product_id: string;
  github_repo: string;
  github_token: string;
  image_api_key?: string;
  testers: Tester[];
}

/** Reads the destination of one product id. */
export interface DestinationMap {
  resolve(productId: string): ProductBundle | null;
}

const REPO = /^[A-Za-z0-9][A-Za-z0-9_.-]*\/[A-Za-z0-9][A-Za-z0-9_.-]*$/;
const HEX64 = /^[0-9a-f]{64}$/;

/** A destination map held in memory. Used by tests and the local server. */
export class MapDestinations implements DestinationMap {
  private readonly byId = new Map<string, ProductBundle>();

  constructor(bundles: ProductBundle[]) {
    for (const bundle of bundles) {
      this.add(bundle);
    }
  }

  /** Adds one checked bundle. A broken bundle is refused, not patched. */
  add(bundle: ProductBundle): void {
    checkBundle(bundle);
    this.byId.set(bundle.product_id, bundle);
  }

  resolve(productId: string): ProductBundle | null {
    return this.byId.get(productId) ?? null;
  }
}

/**
 * Reads the destination map from the server settings.
 *
 * Each product lives in one secret named `PRODUCT_<UPPER_ID>`, for example
 * `PRODUCT_OHRIDSKIPROLOG2`. The value is JSON:
 * `{"github_repo":"owner/name","github_token":"...","image_api_key":"...",
 *   "testers":[{"name":"zarko","token_sha256":"<64 hex>"}]}`
 */
export function readDestinations(settings: Record<string, string | undefined>): MapDestinations {
  const map = new MapDestinations([]);
  for (const [name, raw] of Object.entries(settings)) {
    if (!name.startsWith('PRODUCT_') || !raw) {
      continue;
    }
    let parsed: unknown;
    try {
      parsed = JSON.parse(raw);
    } catch {
      throw new Error(`Setting ${name} is not valid JSON.`);
    }
    if (typeof parsed !== 'object' || parsed === null) {
      throw new Error(`Setting ${name} must be a JSON object.`);
    }
    const value = parsed as Record<string, unknown>;
    const productId = name.slice('PRODUCT_'.length).toLowerCase().replace(/_/g, '-');
    map.add({
      product_id: productId,
      github_repo: String(value.github_repo ?? ''),
      github_token: String(value.github_token ?? ''),
      image_api_key: value.image_api_key === undefined ? undefined : String(value.image_api_key),
      testers: Array.isArray(value.testers)
        ? value.testers.map((tester) => ({
            name: String((tester as Record<string, unknown>).name ?? ''),
            token_sha256: String((tester as Record<string, unknown>).token_sha256 ?? '').toLowerCase(),
          }))
        : [],
    });
  }
  return map;
}

/** Checks one bundle at startup. A broken destination must not serve reports. */
export function checkBundle(bundle: ProductBundle): void {
  if (!bundle.product_id) {
    throw new Error('A product bundle needs a product_id.');
  }
  if (!REPO.test(bundle.github_repo)) {
    throw new Error(`Product ${bundle.product_id} needs a github_repo like owner/name.`);
  }
  if (!bundle.github_token) {
    throw new Error(`Product ${bundle.product_id} needs a github_token.`);
  }
  if (bundle.testers.length === 0) {
    throw new Error(`Product ${bundle.product_id} needs at least one tester entry.`);
  }
  for (const tester of bundle.testers) {
    if (!tester.name) {
      throw new Error(`Product ${bundle.product_id} has a tester without a name.`);
    }
    if (!HEX64.test(tester.token_sha256)) {
      throw new Error(`Tester ${tester.name} of product ${bundle.product_id} needs a token_sha256 with 64 hex characters.`);
    }
  }
}

/**
 * Returns true when the token belongs to one tester of the product.
 *
 * The check compares hashes. It never stores or echoes the token itself.
 */
export async function hasTesterAccess(bundle: ProductBundle, token: string | null): Promise<boolean> {
  if (!token) {
    return false;
  }
  const hash = await sha256Hex(token);
  let allowed = false;
  for (const tester of bundle.testers) {
    if (constantTimeEqual(tester.token_sha256, hash)) {
      allowed = true;
    }
  }
  return allowed;
}

/** The SHA-256 hash of one text value, as 64 lowercase hex characters. */
export async function sha256Hex(text: string): Promise<string> {
  const bytes = new TextEncoder().encode(text);
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) {
    return false;
  }
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}
