# Operator Runbook — Feedback Relay Worker

This runbook describes how to operate the `relay/` Cloudflare Worker: generate
the RSA keypair, provision Worker secrets, register a product, encrypt a
product id for an app, and rotate secrets/keys.

Everything here is **generic** — the relay is product-agnostic. A "product" is
anything that has a GitHub repo where feedback issues should be filed.

## Prerequisites

- The `wrangler` CLI installed and authenticated (`wrangler login`).
- `openssl` on your local machine.
- Worker deployed (see `relay/README.md`).

## 1. Generate the RSA keypair (once)

The relay uses RSA-OAEP (SHA-256). The app encrypts a plaintext product id with
the **public** key; the Worker decrypts it with the **private** key. The public
key is safe to ship inside apps (it can only encrypt). The private key never
leaves the Worker secret store.

Run this once per relay deployment (keep the output **private and backed up** —
losing the private key means every app's baked-in ciphertext must be rotated):

```bash
mkdir -p .dev && cd .dev

# 1. Generate a 2048-bit RSA private key
openssl genrsa -out private.pem 2048

# 2. Derive the public key (safe to distribute to apps)
openssl rsa -in private.pem -pubout -out public.pem

# 3. Export the private key as PKCS8 DER, then base64 — this is the secret value
openssl pkcs8 -topk8 -nocrypt -in private.pem -outform DER -out private_pkcs8.der
base64 -w0 private_pkcs8.der > private_pkcs8_b64.txt
```

> **Never commit `.dev/`.** It is gitignored. Treat `private.pem` and
> `private_pkcs8_b64.txt` as root-level secrets and back them up offline.

## 2. Provision the Worker private key

Set the base64 PKCS8 private key as the Worker secret `FEEDBACK_PRIVATE_KEY_PKCS8`:

```bash
cd relay
# Paste the contents of .dev/private_pkcs8_b64.txt when prompted
wrangler secret put FEEDBACK_PRIVATE_KEY_PKCS8
```

The Worker base64-decodes this and imports it via Web Crypto `importKey`
(`RSA-OAEP`, `SHA-256`) to decrypt incoming product ids.

## 3. Encrypt a product id (once per product, per keypair)

Each app ships a **pre-encrypted** product id as a config constant. The app
never does crypto — it just POSTs this ciphertext verbatim. Encrypt the
plaintext id once with the public key and bake the base64 ciphertext into the
app's config.

```bash
cd .dev

# Encrypt the plaintext product id with the PUBLIC key (OAEP / SHA-256,
# matching the Worker's Web Crypto decrypt).
echo -n "your-product-id" > id_plain.txt
openssl pkeyutl -encrypt -pubin -inkey public.pem \
  -pkeyopt rsa_padding_mode:oaep \
  -pkeyopt rsa_oaep_md:sha256 \
  -in id_plain.txt -out id_enc.bin

# Base64 the ciphertext — paste this into the app config
base64 -w0 id_enc.bin
```

> The product id is **not secret** — it only selects which secret bundle the
> Worker uses. Encryption adds a mild anti-spoofing layer; the real abuse
> protection is the Worker's IP rate-limit. Re-encrypting with the current
> public key is all that's needed if you rotate the keypair.

**Padding note (important):** you must encrypt with `rsa_padding_mode:oaep` and
`rsa_oaep_md:sha256`. The default `openssl pkeyutl -encrypt` uses PKCS1 v1.5
padding, which the Worker's Web Crypto `RSA-OAEP` decrypt will **reject**.

## 4. Register a product (one secret per product)

Each product is a JSON secret named `PRODUCT_<UPPER_ID>` containing the GitHub
repo, a GitHub token (with `repo`/`issues` scope on that repo), and an imgbb
API key:

```json
{
  "github_repo": "owner/repo-name",
  "github_token": "ghp_xxxxxxxxxxxxxxxxxxxx",
  "imgbb_key": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
}
```

Register it:

```bash
cd relay
# For a product id "your-product-id" → secret name PRODUCT_YOUR_PRODUCT_ID
wrangler secret put PRODUCT_YOUR_PRODUCT_ID
# paste the JSON bundle when prompted
```

The Worker uppercases the decrypted product id, replaces non-alphanumerics with
`_`, and looks up `env.PRODUCT_<ID>`. So `your-product-id` →
`PRODUCT_YOUR_PRODUCT_ID`.

That's it — adding a product is one secret. No Worker code change.

## 5. Wire an app (per app)

In the app, point the `feedback_relay` package at the deployed Worker and pass
the pre-encrypted id:

```dart
RelayFeedback.wrap(
  child: MyApp(),
  config: RelayFeedbackConfig(
    backendUrl: 'https://your-worker.workers.dev',
    productIdEnc: '<base64 ciphertext from step 3>',
  ),
)
```

See `feedback_relay/README.md` for the full API.

## 6. Rotate a product secret

If a product's GitHub token or imgbb key leaks or expires, just overwrite the
secret:

```bash
cd relay
wrangler secret put PRODUCT_YOUR_PRODUCT_ID
# paste the new JSON bundle
```

No app change, no re-encryption, no redeploy.

## 7. Rotate the RSA keypair

Rotating the keypair requires re-encrypting every app's product id and
re-provisioning the Worker private key. Plan for app releases.

```bash
cd .dev
# Regenerate (step 1), then:
wrangler secret put FEEDBACK_PRIVATE_KEY_PKCS8   # new private key
# Re-encrypt each product id (step 3) and ship app updates with the new ciphertext.
```

## Verification

After provisioning, verify the loop without an app by POSTing directly to the
Worker:

```bash
curl -X POST https://your-worker.workers.dev/feedback \
  -H 'Content-Type: application/json' \
  -d '{
    "product_id_enc": "<base64 ciphertext from step 3>",
    "screenshot_b64": "<base64 of a small png>",
    "text": "Relay smoke test",
    "app_version": "0.0.0-test",
    "device_info": {}
  }'
```

Expect `{"ok":true,"issue_url":"https://github.com/owner/repo/issues/N"}`.
