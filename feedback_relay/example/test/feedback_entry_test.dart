import 'dart:convert';
import 'dart:typed_data';

import 'package:feedback_relay/feedback_relay.dart';
import 'package:feedback_relay_example/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The example product with the feedback tool, as the test entry builds it.
Widget exampleWithFeedback({
  required DraftStore store,
  required FeedbackContextSource contextSource,
  http.Client? client,
  void Function(String name)? onScreenChanged,
}) {
  const spec = FeedbackBuildSpec.forTest(
    backendUrl: 'https://relay.test',
    productId: 'example-product',
    testerToken: 'tester-token',
    productName: 'Example product',
  );
  final screenName = ValueNotifier<String>('home');
  return FeedbackHost(
    spec: spec,
    store: store,
    client: RelayClient(spec: spec, httpClient: client ?? MockClient((request) async => http.Response('{}', 500))),
    contextSource: _ScreenSource(screenName: screenName, deviceFacts: const DeviceFacts(model: 'Pixel 7', platform: 'android', osVersion: 'Android 15', locale: 'en_US')),
    child: ExampleApp(
      onScreenChanged: (name) {
        screenName.value = name;
        onScreenChanged?.call(name);
      },
      feedbackActions: const <Widget>[FeedbackEntryButton()],
      reportsSection: const FeedbackDraftList(emptyText: 'No report is saved yet.'),
    ),
  );
}

class _ScreenSource implements FeedbackContextSource {
  _ScreenSource({required this.screenName, required this.deviceFacts});

  final ValueNotifier<String> screenName;
  final DeviceFacts deviceFacts;

  @override
  String get appVersion => '1.0.0';

  @override
  String get buildNumber => '1';

  @override
  String get screen => screenName.value;

  @override
  String get sourceRevision => kUnknownFact;

  @override
  DeviceFacts get device => deviceFacts;
}

Future<void> enterFeedback(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('feedback_entry_button')));
  await tester.pump();
}

Future<void> submitFromCapture(WidgetTester tester, String text) async {
  final context = tester.element(find.byKey(const Key('feedback_entry_button')));
  BetterFeedback.of(context).onFeedback!(UserFeedback(text: text, screenshot: Uint8List(0)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> tapSheet(WidgetTester tester, Key key) async {
  await tester.tap(find.byKey(key));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('the product works and carries one feedback entry', (tester) async {
    final store = MemoryDraftStore();
    await tester.pumpWidget(exampleWithFeedback(store: store, contextSource: const UnknownContextSource()));

    expect(find.text('Example product'), findsOneWidget);
    expect(find.byKey(const Key('feedback_entry_button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('add_item')));
    await tester.pump();
    expect(find.text('Items: 1'), findsOneWidget);
  });

  testWidgets('a kept report names the open screen', (tester) async {
    final store = MemoryDraftStore();
    await tester.pumpWidget(exampleWithFeedback(store: store, contextSource: const UnknownContextSource()));

    await enterFeedback(tester);
    await submitFromCapture(tester, 'The count is wrong.');
    await tapSheet(tester, const Key('feedback_preview_keep'));

    final home = (await store.list()).single;
    expect(home.report.text, 'The count is wrong.');
    expect(home.report.context.screen, 'home');
    expect(home.report.context.device.model, 'Pixel 7');
    expect(find.text('Saved'), findsOneWidget);

    await tester.tap(find.byKey(const Key('open_details')));
    await tester.pumpAndSettle();
    await enterFeedback(tester);
    await submitFromCapture(tester, 'The details list is empty.');
    await tapSheet(tester, const Key('feedback_preview_keep'));

    final details = (await store.list()).firstWhere((draft) => draft.report.text == 'The details list is empty.');
    expect(details.report.context.screen, 'details');
  });

  testWidgets('a sent report shows the issue link', (tester) async {
    final store = MemoryDraftStore();
    var bodies = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
      return http.Response(jsonEncode(<String, dynamic>{'ok': true, 'status': 'created', 'issue_url': 'https://github.com/example/issues/5'}), 201);
    });
    await tester.pumpWidget(exampleWithFeedback(store: store, contextSource: const UnknownContextSource(), client: client));

    await enterFeedback(tester);
    await submitFromCapture(tester, 'Send me.');
    await tapSheet(tester, const Key('feedback_preview_send'));

    expect(bodies.single['report_id'], isNotEmpty);
    expect((bodies.single['context'] as Map<String, dynamic>)['product_id'], 'example-product');
    expect(find.text('Sent'), findsOneWidget);
    expect(find.text('https://github.com/example/issues/5'), findsOneWidget);
  });
}
