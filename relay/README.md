# Feedback Relay

The relay for the [`feedback_relay`](../feedback_relay) test-build tool. It
checks tester access and the allowed product destination, then files one
report in the product backlog. GitHub Issues is the first destination.

Version: `0.2.0`. Every external service is faked in the local checks, so no
local run files a real issue or uploads a real image.

## Flow

```
Test build (feedback_relay)
  POST /reports  {report_id, text, expected, steps, screenshot_b64, context}
  header X-Tester-Token: <tester token>
        |
        v
Relay
  1. check the request shape and the limits (unknown field = rejection)
  2. read the public product id and find the destination in its own settings
  3. check the tester token against the stored hash list of that product
  4. read the delivery record of the report id
  5. a repeat answers with the same issue link and files nothing new
  6. look in the backlog for the report marker before any new issue
  7. upload the image when the product has an image host
  8. create the issue and store the confirmed link
        |
        v
  {ok: true, status: created|duplicate, issue_url}   or an honest failure
```

## Honest delivery states

| State | Meaning | App state |
|---|---|---|
| `created` | The backlog returned the issue link. | `Sent` |
| `duplicate` | The report id is already filed. The same link is returned. | `Sent` |
| `unknown` | The relay cannot prove what happened. No blind retry. | `Needs a check` |
| `failed` | The relay proved that nothing was filed. A retry is safe. | `Waiting to send` / `Not sent` |
| `not_found` | The relay holds no record of the report id. A send is safe. | `Waiting to send` |

A lost answer is recovered by the report marker in the issue body
(`<!-- avensora-report-id: <id> -->`). The GitHub search index can lag behind
a new issue. A late index keeps the state `unknown` instead of filing a second
issue.

## Endpoints

`POST /reports` — send one report. Header `X-Tester-Token` is required.

```json
{
  "schema": "avensora-report/1",
  "report_id": "5b9f0a3c-1f2e-4d5a-8b7c-0e1f2a3b4c5d",
  "created_at": "2026-10-03T10:00:00.000Z",
  "text": "The list is empty after a restart.",
  "expected": "The saved items stay visible.",
  "steps": "1. Add one item\n2. Restart the app",
  "screenshot_b64": null,
  "context": {
    "product_id": "ohridskiprolog2",
    "app_version": "1.2.4",
    "build_number": "77",
    "build_mode": "test",
    "screen": "today_schedule",
    "source_revision": "Unknown",
    "captured_at": "2026-10-03T10:00:00.000Z",
    "device": {"model": "Pixel 7", "platform": "android", "os_version": "Android 15", "locale": "en_US"}
  }
}
```

`GET /reports/<report_id>` — read the delivery state. Header
`X-Tester-Token` is required.

An unknown top-level field, an unknown context field, or an unknown device
field is rejected with `400`. An app cannot name a repository, a web address,
or a label.

## Settings

| Binding / secret | Kind | Purpose |
|---|---|---|
| `FEEDBACK_STORE` | KV namespace | Delivery records and rate-limit counters |
| `PRODUCT_<UPPER_ID>` | secret | One destination per product (see the runbook) |

The relay holds every secret. A response never holds a token, a key, or a
repository name.

## Local checks

```bash
npm install
npm run typecheck
npm test          # node --test with fake services
npm run local     # local relay with fake backlog and fake image host
```

The local relay prints its URL, its product id, and its tester token. Use it
for a manual check or for the package contract check:

```bash
cd ../feedback_relay
bash tool/check_local_server.sh
```

## Limits

- Report text: 10 000 characters.
- Expected text and steps: 4 000 characters each.
- Image: 4 MB decoded.
- Rate limit: 10 reports per minute for one tester token.

## Deploy

See [docs/OPERATOR_RUNBOOK.md](docs/OPERATOR_RUNBOOK.md). Deployment is a
separate, approved step. The local checks in this task do not deploy.

## Related

- [`../feedback_relay/`](../feedback_relay/) — the Flutter package
- [docs/OPERATOR_RUNBOOK.md](docs/OPERATOR_RUNBOOK.md) — product and tester setup
- [docs/LIVE_STORAGE_PROPOSAL.md](docs/LIVE_STORAGE_PROPOSAL.md) — image storage and access proposal for the first live trial
