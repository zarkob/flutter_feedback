/// The development entry of the example product.
///
/// It points at the local relay by default, so a local check needs one command:
///
/// ```bash
/// cd ../relay && node src/local_server.ts --port 8791
/// cd ../feedback_relay/example && flutter run -t lib/main_development.dart
/// ```
///
/// The default product id and tester token belong to the local relay only.
/// Never use them for a shared or live relay.
library;

import 'package:feedback_relay/feedback_relay.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'host_setup.dart';

/// Starts the example product for local development.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const url = String.fromEnvironment('FEEDBACK_BACKEND_URL', defaultValue: 'http://127.0.0.1:8791');
  const productId = String.fromEnvironment('FEEDBACK_PRODUCT_ID', defaultValue: 'local-product');
  const token = String.fromEnvironment('FEEDBACK_TESTER_TOKEN', defaultValue: 'local-tester-token');
  const spec = FeedbackBuildSpec(
    mode: FeedbackBuildModes.development,
    backendUrl: url,
    productId: productId,
    testerToken: token,
    productName: 'Example product',
  );
  final store = await openDraftStore();
  final deviceFacts = await readDeviceFacts();
  final screenName = ValueNotifier<String>('home');
  runApp(
    FeedbackHost(
      spec: spec.checked(),
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
