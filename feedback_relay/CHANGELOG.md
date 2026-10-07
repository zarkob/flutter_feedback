## 0.2.1

- Keep a relay note with a confirmed delivery. The draft list shows when the
  relay did not store an image, including after a delivery check or app restart.
- Keep existing `DeliveryConfirmed` constructor calls valid.

## 0.2.0

Shared feedback tool for Avensora test builds. This version reworks the
package from the 0.1.0 relay wrapper.

- `FeedbackBuildSpec`: one build control for the wrapper, the entry controls,
  and the sending path. Feedback is enabled only for `development` or `test`
  builds. A production build with feedback settings stops the app at startup.
- `FeedbackReport`: a versioned plain JSON report (`avensora-report/1`) with a
  stable report id, text, optional expected behavior, optional steps, and an
  optional screenshot. The new `ReportContext` carries the product id, app
  version, build number, build mode, screen, capture time, optional source
  revision, and a small named set of device facts. Unknown facts stay
  `Unknown`.
- `FeedbackFlow`: capture, preview, draft, and send flow with honest states
  (`saved`, `waiting`, `sent`, `needsCheck`, `failed`). `sent` is used only
  after the destination confirms delivery.
- Drafts: a `DraftStore` interface, a `MemoryDraftStore`, and a file store in
  `file_draft_store.dart`. A draft survives offline use and an app restart.
- Safe retries: the report id does not change. A report whose delivery is
  unknown is checked first. A new issue is created only when the relay proves
  that it holds no record.
- `RelayClient`: submit and delivery-check calls. A send without an answer is
  reported as unknown, not as failed and not as sent.
- UI: `FeedbackHost` wrapper, `FeedbackEntryButton`, `FeedbackPreviewSheet`
  (Send, Keep as draft, Cancel), and `FeedbackDraftList` (check, send again,
  remove).
- Breaking: `RelayFeedbackConfig`, `RelayFeedback`, `sendToRelay`, and
  `submitToRelay` are replaced by the classes above. The relay endpoint moved
  to `POST /reports` and `GET /reports/<report_id>`.

## 0.1.0

- Initial release.
- `RelayFeedbackConfig` (backend URL + pre-encrypted product id).
- `RelayFeedback.wrap` / `RelayFeedback` widget wrapper around `BetterFeedback`.
- `FeedbackController.showRelayFeedback` extension and `submitToRelay` helper.
- `RelayFeedbackResult` sealed result type (`Success` / `Failure`).
