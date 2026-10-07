# Operator runbook for the OP2 test relay

Use this runbook for the new Ohridski Prolog test relay.
The checked config is `wrangler.op2-test.jsonc`.
It has its own worker and `FEEDBACK_STORE` namespace.
It keeps the older `feedback-relay` worker and its clients separate.

Do not use `wrangler.toml` for the OP2 test relay.
Do not change the old worker secrets.
Do not put secret values in source files or build logs.

## Required access

- Use Node 22 or newer and the local `wrangler` package.
- Sign in to the Cloudflare account that owns the OP2 test config.
- Use a fine-grained GitHub token for `zarkob/ohridskiprolog2` only.
- Give that token `Issues: Read and write` permission.
- Do not give the token `Contents`, `Actions`, or organization permissions.
- The relay searches issues and creates one issue for each confirmed report.
- Make one relay tester token for each tester.

The relay stores the tester token hash, not the token.
A hash is a one-way value that the relay uses to check a token.
Keep each raw tester token private.

## 1. Check local files

Run these commands from `relay/`:

```bash
npm ci
npm run typecheck
npm test
npm audit
npx wrangler deploy --dry-run --config wrangler.op2-test.jsonc
```

The dry run checks the worker bundle.
It does not publish the worker.
The local tests use fake issue and image services.
They do not create an issue or upload an image.

Run the shared package checks from `feedback_relay/`:

```bash
flutter analyze
flutter test
bash tool/check_local_server.sh
bash tool/check_build_boundary.sh
```

Run both host fixture tests and the example test:

```bash
(cd fixtures/host_alpha && flutter test)
(cd fixtures/host_beta && flutter test)
(cd example && flutter test)
```

## 2. Add the product secret

The existing OP2 test config supplies the `FEEDBACK_STORE` binding.
Do not create or replace that namespace for this trial.

Create `PRODUCT_OHRIDSKIPROLOG2` with the following fields:

```json
{
  "github_repo": "zarkob/ohridskiprolog2",
  "github_token": "<private fine-grained token>",
  "testers": [
    { "name": "<tester name>", "token_sha256": "<64 hex characters>" }
  ]
}
```

Do not add `image_api_key` for the first trial.
The relay will save the issue without the image.
The relay will return a note that says it did not store the image.
The app must show that note beside `Sent`.
The issue body must say that no image was attached.

Open the secret prompt from `relay/`:

```bash
npx wrangler secret put PRODUCT_OHRIDSKIPROLOG2 --config wrangler.op2-test.jsonc
```

Paste the JSON into the prompt.
Do not place secret JSON in a command argument or tracked file.

## 3. Make a tester token

Make one token for each tester.
Keep the raw value in a private password store.
Store its SHA-256 hash in the product secret.

```bash
tester_token="$(openssl rand -hex 24)"
printf '%s' "$tester_token" | sha256sum
```

The token has 48 hexadecimal characters.
Give it to the tester through a private channel.
Do not send it in a public issue or commit.

## 4. Deploy after approval

The owner must approve the live test setup before this step.
The operator must confirm the product secret and tester token first.

```bash
npx wrangler deploy --config wrangler.op2-test.jsonc
```

Save the HTTPS worker URL from the command output.
Do not use the old endpoint for this relay.
The old endpoint uses the older `/feedback` protocol.

## 5. Check the live relay

Use one valid tester token for these checks.
Replace the sample id and URL with test values.

```bash
curl -s https://<new-worker-url>/reports/<unused-report-id> \
  -H "X-Tester-Token: $tester_token"
```

The answer must say `not_found`.
A wrong token must answer `403`.
An unknown product must answer `404`.
No answer may show a key, token, or repository secret.

Send one test report with a screenshot.
The relay must create one issue and return `status: created`.
The answer must include a note that the image was not stored.
The issue must say that no image was attached.
The app must show `Sent`, the issue link, and the image note.
Check the same report id again.
It must return the same issue link and the same note.

## 6. Build the test app

Use the checked package revision and the separate test entry.
Pass these values only to the test build:

```bash
flutter build apk --release -t lib/main_feedback.dart \
  --dart-define=FEEDBACK_BUILD_MODE=test \
  --dart-define=FEEDBACK_BACKEND_URL=https://<new-worker-url> \
  --dart-define=FEEDBACK_PRODUCT_ID=ohridskiprolog2 \
  --dart-define=FEEDBACK_TESTER_TOKEN=<private-token>
```

Do not put the raw token in source or the build record.
Record the source revision, package, version, build number, APK hash, and screens checked.
Keep the normal app entry free of feedback imports and build values.
Build and check the normal production APK without any `FEEDBACK_*` values.

## 7. Close a tester token

Remove a tester hash from `PRODUCT_OHRIDSKIPROLOG2` when access must end.
Replace a leaked token with a new token and hash.
Revoke a leaked GitHub token at GitHub.
Then update the product secret.

## Limits

The first trial has no image host.
The relay will not store or link the screenshot.
Cloudflare KV has no compare-and-swap claim.
Keep the first trial to one tester and do not send one report twice at once.
The local relay serializes sends, so local checks do not prove this limit safe.
