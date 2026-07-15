# feedback_relay

Companion package for the [`feedback`](https://pub.dev/packages/feedback)
Flutter plugin. It keeps the upstream screenshot capture + on-screen annotation
experience and replaces the submission path: instead of routing feedback to a
third party, it POSTs the annotated screenshot and comment to **your own**
serverless backend, which files them as a GitHub issue.

The matching backend is the sibling [`relay/`](../relay) Cloudflare Worker.

## Why

- **No secrets in the app.** The app ships only a backend URL and a
  pre-encrypted product id. The GitHub token, the image-host API key, and the
  private decryption key all live server-side. Decompiling the app leaks only a
  public key and a ciphertext — useless without the backend.
- **Product-agnostic and config-driven.** One package, one backend, any number
  of apps. Adding an app is a config constant, not a code change.
- **Testers-only by construction.** You wrap the app only in non-release build
  flavors; release builds have no feedback surface.

## Install

```yaml
dependencies:
  feedback_relay:
    git:
      url: https://github.com/zarkob/flutter_feedback.git
      path: feedback_relay
```

## Usage

1. Deploy the [`relay/`](../relay) Worker and follow
   [`relay/docs/OPERATOR_RUNBOOK.md`](../relay/docs/OPERATOR_RUNBOOK.md) to
   provision the keypair and your product's secret bundle.
2. Pre-encrypt your product id once (offline) with the backend's public key and
   bake the base64 ciphertext into your app config.
3. Wrap your app (in a non-release flavor) and trigger feedback from a button:

```dart
import 'package:feedback_relay/feedback_relay.dart';

const config = RelayFeedbackConfig(
  backendUrl: 'https://your-worker.workers.dev',
  // Pre-encrypted with the backend's RSA public key (see OPERATOR_RUNBOOK.md).
  // NOT secret — only selects which GitHub repo the issue is filed in.
  productIdEnc: '<base64 ciphertext of your product id>',
);

void main() {
  runApp(
    RelayFeedback.wrap(
      MyApp(),
      // config is consumed where you trigger feedback (see below)
    ),
  );
}

// Somewhere in your UI (e.g. a "Send feedback" button):
BetterFeedback.of(context).showRelayFeedback(
  config,
  onResult: (result) {
    switch (result) {
      case RelayFeedbackSuccess(:final issueUrl):
        // show "Feedback sent ✓" + a link to issueUrl
        break;
      case RelayFeedbackFailure(:final reason):
        // show the (safe, non-secret) reason
        break;
    }
  },
);
```

The upstream capture + annotation UI is unchanged — only the submit target is
swapped.

## API

| Name | Purpose |
|---|---|
| `RelayFeedbackConfig` | Backend URL + pre-encrypted product id (+ optional static metadata) |
| `RelayFeedback.wrap(child, …)` | Wraps the app in `BetterFeedback` (shorthand constructor) |
| `RelayFeedback(child, …)` | Widget form of the wrapper; forwards all `BetterFeedback` params |
| `FeedbackController.showRelayFeedback(config, {onResult})` | Opens the UI and submits to the relay on completion |
| `RelayFeedbackResult` (`Success` / `Failure`) | Outcome returned via `onResult` |

## Build flavor gating

This package does **not** decide who can send feedback — that lives in your
app. Wrap the app only in your tester/beta/dev flavors so release builds have
no feedback surface:

```dart
runApp(
  enableFeedback ? RelayFeedback.wrap(MyApp()) : MyApp(),
);
```

## Related

- [`../feedback/`](../feedback/) — the upstream screenshot + annotation plugin
- [`../relay/`](../relay/) — the matching Cloudflare Worker backend
- [`../relay/docs/OPERATOR_RUNBOOK.md`](../relay/docs/OPERATOR_RUNBOOK.md) — provisioning & keygen
