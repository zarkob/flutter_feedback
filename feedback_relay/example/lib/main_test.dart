/// The test build entry of the example product.
///
/// This entry includes the feedback tool. Build it with the three relay
/// settings. A build without them stops at startup, so a test build can never
/// run with a half-configured tool.
///
/// ```bash
/// flutter run -t lib/main_test.dart \
///   --dart-define=FEEDBACK_BUILD_MODE=test \
///   --dart-define=FEEDBACK_BACKEND_URL=http://127.0.0.1:8791 \
///   --dart-define=FEEDBACK_PRODUCT_ID=local-product \
///   --dart-define=FEEDBACK_TESTER_TOKEN=local-tester-token
/// ```
library;

import 'package:feedback_relay/feedback_relay.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'host_setup.dart';

/// Starts the example product with the feedback tool.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final spec = FeedbackBuildSpec.fromEnvironment().checked();
  final store = await openDraftStore();
  final deviceFacts = await readDeviceFacts();
  final screenName = ValueNotifier<String>('home');
  runApp(
    FeedbackHost(
      spec: spec,
      store: store,
      contextSource: ExampleContextSource(
        screenName: screenName,
        appVersion: '1.0.0',
        buildNumber: '1',
        deviceFacts: deviceFacts,
      ),
      child: ExampleApp(
        onScreenChanged: (name) => screenName.value = name,
        feedbackActions: const <Widget>[FeedbackEntryButton()],
        reportsSection: const FeedbackDraftList(emptyText: 'No report is saved yet.'),
      ),
    ),
  );
}
