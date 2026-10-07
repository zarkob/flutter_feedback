# Live image storage and tester access — proposal

**Status: proposal for the first live trial. Not implemented and not checked
against a live service.**

The task checks use dummy images, a fake image host, and a local relay. The
first live trial needs these two decisions.

The current OP2 test plan uses no image host.
It checks that the relay saves the report and tells the tester that it did not store the image.
This trial does not prove image upload or image retention.

## Decision 1: where tester images live

Two small options.

**Option A — keep the imgbb path (recommended).**

- The relay already holds this adapter. The key stays on the relay.
- Setup cost: one free imgbb key per product, no code change.
- Limit: images live on a third-party host with no retention control. Any
  person with the link can open the image.

**Option B — store images in Cloudflare R2.**

- The relay and the storage live in one account, so one bill and one access
  rule. The relay returns a signed link.
- Setup cost: one bucket, one access key, and a new upload adapter. Retention
  and deletion become possible.
- Limit: more setup work and one more secret to rotate.

Option A is the smaller later image trial because it needs no code change.
Use Option B before tester images may hold private product data.

## Decision 2: how a tester gets access

The product id is public and selects a destination. It proves nothing.

The relay checks a tester token against a hash list of that product:

- One token per tester, made by the operator (see the runbook).
- The relay stores only the SHA-256 hash.
- A token works for one product list.
- The relay rate-limits one token to 10 reports per minute.

**Recommendation: one token per tester, one shared token for the owner.**
This gives a clear removal path when a tester leaves and keeps the setup
small. Move to a per-device token only when more testers join.

## Steps before the first live trial

1. The owner approves the separate test worker and report destination.
2. The operator checks the test `FEEDBACK_STORE` binding and adds the product secret.
3. The operator makes the tester token and sends it in private.
4. The relay is deployed and checked with `curl` (see the runbook).
5. One product builds a test variant with the three relay settings.
6. One tester sends one report with a screenshot and no image host configured.
7. The tester checks `Sent`, the real issue link, and the note that the image was not stored.
8. The owner selects the work from the issue and opens a task.

Step 2 of this list needs its own approved check. This task leaves it open.
