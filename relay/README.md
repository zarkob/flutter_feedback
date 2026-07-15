# Feedback Relay Worker

A Cloudflare Worker that receives in-app feedback from the
[`feedback_relay`](../feedback_relay) Flutter package and files it as a
**GitHub issue** in the relevant product's repository — with the screenshot
attached via [imgbb](https://imgbb.com/).

## How it works

```
App (feedback_relay)
  POST {product_id_enc, screenshot_b64, text, app_version, device_info}
        │
        ▼
Feedback Relay Worker
  1. validate + size-cap input
  2. rate-limit by IP (KV)
  3. RSA-OAEP decrypt product_id_enc → plaintext product id
  4. look up PRODUCT_<ID> secret bundle → {github_repo, github_token, imgbb_key}
  5. upload screenshot to imgbb → imageUrl
  6. create GitHub issue (body = text + screenshot + env info)
  7. return {ok, issue_url}
```

The app ships **only** the backend URL and a pre-encrypted product id. No
GitHub token, no imgbb key, no private key ever enters the APK. Decompiling the
app leaks only a public key (used to pre-encrypt the id) and the ciphertext —
both useless without the Worker's private key.

## Product-agnostic

Adding a new product requires **no code change**. Register one secret and
rebuild the app with the new pre-encrypted id. See
[`docs/OPERATOR_RUNBOOK.md`](docs/OPERATOR_RUNBOOK.md).

## Deploy

Prerequisites: the `wrangler` CLI, authenticated (`wrangler login`).

```bash
cd relay
npm install

# Create the rate-limit KV namespace
wrangler kv namespace create FEEDBACK_RATELIMIT
# → paste the returned id into wrangler.toml

# Provision secrets (see docs/OPERATOR_RUNBOOK.md for full instructions)
wrangler secret put FEEDBACK_PRIVATE_KEY_PKCS8
wrangler secret put PRODUCT_YOUR_PRODUCT_ID

# Deploy
wrangler deploy
```

## Environment

| Binding / secret | Kind | Purpose |
|---|---|---|
| `FEEDBACK_RATELIMIT` | KV namespace | IP rate-limit counters |
| `FEEDBACK_PRIVATE_KEY_PKCS8` | secret | Base64 PKCS8 RSA private key (decrypts product ids) |
| `PRODUCT_<UPPER_ID>` | secret | JSON `{github_repo, github_token, imgbb_key}` per product |

## Request / response

`POST /feedback`

```json
{
  "product_id_enc": "<base64 RSA-OAEP ciphertext of the product id>",
  "screenshot_b64": "<base64 PNG>",
  "text": "the tester's comment",
  "app_version": "1.2.3 (optional)",
  "device_info": { "platform": "android", "optional": true }
}
```

Success:

```json
{ "ok": true, "issue_url": "https://github.com/owner/repo/issues/42" }
```

Errors (no secrets are ever leaked in responses):

```json
{ "ok": false, "error": "human-readable reason" }
```

## Limits

- Screenshot: 4 MB decoded.
- Feedback text: 10 000 characters.
- Rate limit: 5 submissions / minute / IP.

## Related

- [`docs/OPERATOR_RUNBOOK.md`](docs/OPERATOR_RUNBOOK.md) — keygen, provisioning, rotation
- [`../feedback_relay/`](../feedback_relay/) — the Flutter companion package
- [`../feedback/`](../feedback/) — the upstream screenshot + annotation UI
