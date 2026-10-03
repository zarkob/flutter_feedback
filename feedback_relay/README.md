# feedback_relay

The shared feedback tool for Avensora development and test builds. A tester
reports what happened in a few taps. The report carries the build, screen,
time, and a small set of device facts. The tester sees the text and the image
before Send.

The package is independent. It needs no product code and no Avensora OS code.
It works in any Flutter app and the report format is plain JSON.

Version: `0.2.0`. Original source: this repository's `feedback_relay` package
at revision `38b6a436c0a9e53856563c2f170744e3fd385f9c`.

## What the tester gets

- One entry control in the app.
- The annotation and comment screen of the [`feedback`][feedback] plugin.
- A preview of the text, the image, and the known facts.
- Three clear actions: **Send**, **Keep as draft**, **Cancel**.
- Honest states: `Saved`, `Waiting to send`, `Sent`, `Needs a check`,
  `Not sent`. `Sent` is used only after the relay confirms delivery.

A report does not need a GitHub account. The tester token is issued by the
operator.

## What the app ships

The app ships only three values: the relay URL, a public product id, and a
tester token. The GitHub token, the image host key, and the destination map
stay on the relay.

## Install

```yaml
dependencies:
  feedback_relay:
    git:
      url: https://github.com/zarkob/flutter_feedback.git
      path: feedback_relay
      ref: <checked revision>
```

## Attach it to an app

1. Add the dependency above.
2. Give the host its facts. The package cannot read the app version, the
   screen name, or the device model by itself:

```dart
class MyContextSource implements FeedbackContextSource {
  MyContextSource(this.screenName);

  final ValueNotifier<String> screenName;

  @override
  String get appVersion => '1.2.4';           // from the build settings
  @override
  String get buildNumber => '77';             // from the build settings
  @override
  String get screen => screenName.value;      // the screen that is open now
  @override
  String get sourceRevision => kUnknownFact;  // only when the build has one
  @override
  DeviceFacts get device => const DeviceFacts(model: 'Pixel 7', platform: 'android');
}
```

3. Wrap the app once, in a development or test entry only:

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final spec = FeedbackBuildSpec.fromEnvironment().checked();
  final directory = await getApplicationSupportDirectory(); // private storage
  runApp(
    FeedbackHost(
      spec: spec,
      store: FileDraftStore(Directory('${directory.path}/feedback_drafts')),
      contextSource: MyContextSource(screenName),
      child: MyApp(onScreenChanged: (name) => screenName.value = name),
    ),
  );
}
```

4. Add the entry control where the tester can reach it:

```dart
const FeedbackEntryButton(),
// and, when the saved reports should be on screen:
const FeedbackDraftList(),
```

5. Build the test variant with the relay settings:

```bash
flutter build apk --release -t lib/main_test.dart \
  --dart-define=FEEDBACK_BUILD_MODE=test \
  --dart-define=FEEDBACK_BACKEND_URL=https://<your-relay> \
  --dart-define=FEEDBACK_PRODUCT_ID=<your-product-id> \
  --dart-define=FEEDBACK_TESTER_TOKEN=<your-tester-token>
```

## Build boundary

One value, `FeedbackBuildSpec`, gates the wrapper, the entry controls, and the
sending path. A build with no feedback setting is a production build, so the
tool fails closed.

| Setting | Meaning |
|---|---|
| `FEEDBACK_BUILD_MODE` | `development`, `test`, or `production`. The default is `production`. |
| `FEEDBACK_BACKEND_URL` | The relay endpoint, with no trailing slash. |
| `FEEDBACK_PRODUCT_ID` | The public product id. The relay maps it to one destination. |
| `FEEDBACK_TESTER_TOKEN` | The tester access token from the operator. |
| `FEEDBACK_PRODUCT_NAME` | An optional readable product name. |
| `FEEDBACK_ENABLED` | An optional switch. It must agree with the mode. |

Rejected settings, all at startup:

- an unknown mode name;
- a `production` build that carries any relay setting;
- `FEEDBACK_ENABLED=true` with `production`;
- `FEEDBACK_ENABLED=false` with `development` or `test`;
- an enabled build that misses one relay setting.

Flutter release mode alone does not decide the boundary. A test build can use
release mode and still hold the tool.

## Remove it from an app

1. Delete the `feedback_relay` dependency from `pubspec.yaml`.
2. Delete the test entry file, `FeedbackHost`, and the entry controls.
3. Delete the `FEEDBACK_*` build settings from the test build script.
4. Run `flutter pub get` and build the production entry.

The production entry never imports the package, so the production app keeps
working. `tool/check_build_boundary.sh` proves this path on the example app.

## Drafts and retries

- A draft holds the text, the optional image, the report id, and the known
  facts. It survives a failed send and an app restart.
- The report id never changes during a retry.
- A send with no answer is `needsCheck`, not `sent` and not `failed`.
- `FeedbackFlow.retry` checks delivery first. It sends again only when the
  relay proves that it holds no record of the report id.
- The tester can remove any saved draft.

Drafts live where the host puts them. Use a private app directory. The default
`MemoryDraftStore` is for tests and small fixtures.

## Report format

`avensora-report/1`. The format has no Flutter type, so another app type can
produce it.

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

A fact that the host cannot read stays `Unknown`. The package collects no
account data, no device serial, no log, and no private setting.

## Server

The matching relay is [`../relay`](../relay). Its calls:

| Call | Purpose |
|---|---|
| `POST /reports` | Send one report. The relay checks tester access and the destination. |
| `GET /reports/<report_id>` | Read the delivery state: `created`, `unknown`, or `not_found`. |

## Local checks

From this folder:

```bash
flutter analyze
flutter test
bash tool/check_local_server.sh          # package client against the local relay
bash tool/check_build_boundary.sh        # test inclusion, production exclusion, detachment
```

Host fixtures and the runnable example:

```bash
(cd fixtures/host_alpha && flutter test)
(cd fixtures/host_beta && flutter test)
(cd example && flutter test)
```

## License and provenance

The package is Apache-2.0, the same license as the upstream `feedback` plugin
that it builds on. The plugin stays a normal dependency; no plugin source is
copied into this package. See [LICENSE](LICENSE) and
[CHANGELOG.md](CHANGELOG.md).

[feedback]: https://pub.dev/packages/feedback
