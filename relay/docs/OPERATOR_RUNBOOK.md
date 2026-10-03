# Operator Runbook — Feedback Relay

This runbook tells the operator how to set up the relay, add one product, make
one tester token, and rotate a credential.

The relay stays product-agnostic. One product is one destination and one tester
list.

## What the relay needs

- The `wrangler` CLI, signed in (`wrangler login`).
- `node` 22 or newer for the local checks.
- One GitHub token with issue write access on the product repository.
- One tester token per tester, made by the operator.

## 1. Create the store

The relay keeps delivery records and rate-limit counters in one KV namespace.

```bash
cd relay
wrangler kv namespace create FEEDBACK_STORE
# Paste the returned id into wrangler.toml.
```

## 2. Add one product

A product lives in one secret named `PRODUCT_<UPPER_ID>`. The id is the public
product id in upper case, with dashes replaced by underscores. The product
`ohridskiprolog2` uses `PRODUCT_OHRIDSKIPROLOG2`.

```bash
wrangler secret put PRODUCT_OHRIDSKIPROLOG2
# Paste this JSON when prompted:
# {
#   "github_repo": "zarkob/ohridskiprolog2",
#   "github_token": "<github token with issue write>",
#   "image_api_key": "<image host key, optional>",
#   "testers": [ { "name": "zarko", "token_sha256": "<64 hex>" } ]
# }
```

Rules that the relay checks at startup:

- `github_repo` must look like `owner/name`.
- `github_token` must be present.
- `testers` must hold at least one entry, and every entry needs a 64-hex
  `token_sha256`.
- A broken product setting refuses every report. The relay never falls back.

## 3. Make one tester token

```bash
token="$(openssl rand -hex 24)"           # 48 hex characters
printf '%s' "$token" | sha256sum          # the value for token_sha256
```

Send the token to the tester through a private channel. Store only the hash.
The token is not a GitHub account and gives no GitHub access.

A tester token can send a report only for the products that list its hash.

## 4. Deploy and check

```bash
npm install
npm run typecheck
npm test
wrangler deploy
```

Check the deployed relay with the tester token:

```bash
curl -s https://<your-relay>/reports/00000000-0000-4000-8000-000000000000 \
  -H "X-Tester-Token: $token"
# {"ok":true,"status":"not_found"}
```

A wrong token answers `403`. An unknown product answers `404`. Neither answer
holds a secret.

## 5. Rotate

- **One tester leaves:** remove the entry from the `testers` list and put the
  secret again.
- **One token leaks:** make a new token, replace the hash, and send the new
  token to that tester.
- **The GitHub token leaks:** revoke it at GitHub, make a new one, and put the
  product secret again.

## Honest behavior

The relay files one issue for one report id. Before it creates an issue, it
looks in the backlog for the report marker. A lost answer becomes `unknown`
until the relay can prove the result. A late GitHub search index keeps the
state `unknown`; the app then shows `Needs a check` and does not send again.

The relay never returns a token, a key, or a repository name in a response.

## Local checks

The local relay uses a fake backlog and a fake image host. It files no real
issue and uploads no real image.

```bash
npm test              # 32 checks with fake services
npm run local         # local relay on a free port
```

## Related

- [LIVE_STORAGE_PROPOSAL.md](LIVE_STORAGE_PROPOSAL.md) — image storage and
  tester access proposal for the first live trial
