import 'dart:convert';
import 'dart:typed_data';

import 'package:feedback_relay/feedback_relay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:host_alpha/host.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

List<Map<String, dynamic>> capturedBodies = <Map<String, dynamic>>[];

/// A 1x1 PNG, so the preview renders a real image in the check.
final Uint8List onePixelPng = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

RelayClient clientThatCreates(String issueUrl) => RelayClient(
  spec: alphaSpec,
  httpClient: MockClient((request) async {
    capturedBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
    return http.Response(jsonEncode(<String, dynamic>{'ok': true, 'status': 'created', 'issue_url': issueUrl}), 201);
  }),
);

RelayClient clientThatFails() => RelayClient(
  spec: alphaSpec,
  httpClient: MockClient((request) async {
    throw http.ClientException('offline');
  }),
);

Future<void> submitReport(WidgetTester tester, {String text = 'The note list lost its order.', bool withImage = false}) async {
  await tester.tap(find.byKey(const Key('feedback_entry_button')));
  await tester.pump();
  final context = tester.element(find.byKey(const Key('feedback_entry_button')));
  BetterFeedback.of(context).onFeedback!(
    UserFeedback(text: text, screenshot: withImage ? onePixelPng : Uint8List(0)),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> tapSheet(WidgetTester tester, Key key) async {
  await tester.tap(find.byKey(key));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUp(() => capturedBodies = <Map<String, dynamic>>[]);

  testWidgets('the host sends a report with its own product id', (tester) async {
    final store = MemoryDraftStore();
    await tester.pumpWidget(
      alphaHost(spec: alphaSpec, store: store, screenName: ValueNotifier<String>('notes_list'), client: clientThatCreates('https://github.com/example/alpha/issues/3')),
    );

    await submitReport(tester, withImage: true);
    await tapSheet(tester, const Key('feedback_preview_send'));

    final body = capturedBodies.single;
    expect(body['schema'], kReportSchema);
    expect((body['context'] as Map<String, dynamic>)['product_id'], 'alpha-notes');
    expect((body['context'] as Map<String, dynamic>)['app_version'], '0.4.2');
    expect((body['context'] as Map<String, dynamic>)['build_number'], '18');
    expect((body['context'] as Map<String, dynamic>)['screen'], 'notes_list');
    expect(body['screenshot_b64'], isNotNull);
    expect(find.text('Sent'), findsOneWidget);
  });

  testWidgets('the host accepts a report without an image', (tester) async {
    final store = MemoryDraftStore();
    await tester.pumpWidget(
      alphaHost(spec: alphaSpec, store: store, screenName: ValueNotifier<String>('notes_list'), client: clientThatCreates('https://github.com/example/alpha/issues/4')),
    );

    await submitReport(tester);
    await tapSheet(tester, const Key('feedback_preview_keep'));

    final draft = (await store.list()).single;
    expect(draft.report.hasScreenshot, isFalse);
    expect(draft.report.text, 'The note list lost its order.');
  });

  testWidgets('the open screen travels with the report', (tester) async {
    final store = MemoryDraftStore();
    final screenName = ValueNotifier<String>('notes_list');
    await tester.pumpWidget(alphaHost(spec: alphaSpec, store: store, screenName: screenName, client: clientThatCreates('https://github.com/example/alpha/issues/5')));

    await tester.tap(find.byKey(const Key('alpha_add_note')));
    await tester.pump();
    await submitReport(tester, text: 'The editor closes by itself.');
    await tapSheet(tester, const Key('feedback_preview_send'));

    expect((capturedBodies.single['context'] as Map<String, dynamic>)['screen'], 'note_editor');
  });

  testWidgets('a draft from an earlier run comes back after a restart', (tester) async {
    final store = MemoryDraftStore();
    final report = FeedbackReport.create(text: 'An old note.', productId: 'alpha-notes', screen: 'notes_list');
    await store.save(ReportDraft(report: report, state: ReportDeliveryState.waiting));

    await tester.pumpWidget(
      alphaHost(spec: alphaSpec, store: store, screenName: ValueNotifier<String>('notes_list'), client: clientThatFails()),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('An old note.'), findsOneWidget);
    expect(find.text('Needs a check'), findsOneWidget);
  });

  testWidgets('the host stays usable when the build closes feedback', (tester) async {
    const production = FeedbackBuildSpec.production();
    await tester.pumpWidget(
      alphaHost(spec: production, store: MemoryDraftStore(), screenName: ValueNotifier<String>('notes_list')),
    );

    expect(find.byKey(const Key('feedback_entry_button')), findsNothing);
    expect(find.text('No report is saved.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('alpha_add_note')));
    await tester.pump();
    expect(find.text('Notes list'), findsOneWidget);
  });
}
