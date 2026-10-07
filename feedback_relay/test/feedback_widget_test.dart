import 'dart:typed_data';

import 'package:feedback_relay/feedback_relay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/relay_fakes.dart';

/// Host facts for the widget checks, so the preview can be checked against
/// known values instead of `Unknown`.
class _FactsSource implements FeedbackContextSource {
  const _FactsSource();

  @override
  String get appVersion => '1.2.4';

  @override
  String get buildNumber => '77';

  @override
  String get screen => 'notes_list';

  @override
  String get sourceRevision => kUnknownFact;

  @override
  DeviceFacts get device => const DeviceFacts(
      model: 'Pixel 7',
      platform: 'android',
      osVersion: 'Android 15',
      locale: 'en_US');
}

Widget _app({
  required FeedbackBuildSpec spec,
  required DraftStore store,
  RelayClient? client,
  FeedbackContextSource contextSource = const UnknownContextSource(),
}) {
  return FeedbackHost(
    spec: spec,
    store: store,
    client: client,
    contextSource: contextSource,
    child: MaterialApp(
      home: Scaffold(
        body: Column(
          children: <Widget>[
            const FeedbackEntryButton(),
            Expanded(child: SingleChildScrollView(child: FeedbackDraftList())),
          ],
        ),
      ),
    ),
  );
}

/// Opens the capture UI from the entry control.
///
/// The annotation layer runs its own animations, so the checks use counted
/// frames instead of `pumpAndSettle`.
Future<void> _enterFeedback(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('feedback_entry_button')));
  await tester.pump();
}

/// Hands one submitted report to the flow, as the capture UI does.
Future<void> _submitFromCapture(WidgetTester tester,
    {String text = 'The list is empty.', Uint8List? screenshot}) async {
  final context =
      tester.element(find.byKey(const Key('feedback_entry_button')));
  final controller = BetterFeedback.of(context);
  controller.onFeedback!(
      UserFeedback(text: text, screenshot: screenshot ?? Uint8List(0)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Taps one preview or draft action and lets the sheet close.
Future<void> _tapAndSettleSheet(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

void main() {
  const production = FeedbackBuildSpec.production();

  group('build boundary in the widget tree', () {
    testWidgets('a production build shows no wrapper and no entry control',
        (tester) async {
      await tester
          .pumpWidget(_app(spec: production, store: MemoryDraftStore()));

      expect(find.byType(BetterFeedback), findsNothing);
      expect(find.byKey(const Key('feedback_entry_button')), findsNothing);
      expect(find.text('Send feedback'), findsNothing);
    });

    testWidgets('a test build in release mode still shows the entry control',
        (tester) async {
      await tester
          .pumpWidget(_app(spec: testSpec(), store: MemoryDraftStore()));
      await tester.pump();

      expect(find.byType(BetterFeedback), findsOneWidget);
      expect(find.byKey(const Key('feedback_entry_button')), findsOneWidget);
    });

    testWidgets('the entry control does nothing without a host',
        (tester) async {
      await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: FeedbackEntryButton())));

      expect(find.byKey(const Key('feedback_entry_button')), findsNothing);
    });
  });

  group('preview and send flow', () {
    testWidgets('the preview shows the text, the screen, and the device facts',
        (tester) async {
      final store = MemoryDraftStore();
      await tester.pumpWidget(_app(
          spec: testSpec(), store: store, contextSource: const _FactsSource()));
      await _enterFeedback(tester);

      await _submitFromCapture(tester, text: 'The list is empty.');

      expect(find.text('Review this report'), findsOneWidget);
      expect(find.text('The list is empty.'), findsOneWidget);
      expect(find.text('alpha-notes'), findsOneWidget);
      expect(find.text('notes_list'), findsOneWidget);
      expect(find.text('Pixel 7'), findsOneWidget);
      expect(find.text('1.2.4'), findsOneWidget);
    });

    testWidgets('the preview keeps an unknown fact honest', (tester) async {
      final store = MemoryDraftStore();
      await tester.pumpWidget(_app(spec: testSpec(), store: store));
      await _enterFeedback(tester);

      await _submitFromCapture(tester, text: 'No facts are known.');

      expect(find.text('Unknown'), findsWidgets);
      expect(find.text('notes_list'), findsNothing);
    });

    testWidgets('cancel keeps no draft and sends nothing', (tester) async {
      final relay = FakeRelay((request) async =>
          createdResponse('https://github.com/o/r/issues/1'));
      final store = MemoryDraftStore();
      await tester.pumpWidget(_app(
          spec: testSpec(),
          store: store,
          client: RelayClient(spec: testSpec(), httpClient: relay.client)));
      await _enterFeedback(tester);
      await _submitFromCapture(tester);

      await _tapAndSettleSheet(
          tester, find.byKey(const Key('feedback_preview_cancel')));

      expect(await store.list(), isEmpty);
      expect(relay.requests, isEmpty);
    });

    testWidgets('keep as draft saves the report without a send',
        (tester) async {
      final relay = FakeRelay((request) async =>
          createdResponse('https://github.com/o/r/issues/1'));
      final store = MemoryDraftStore();
      await tester.pumpWidget(_app(
          spec: testSpec(),
          store: store,
          client: RelayClient(spec: testSpec(), httpClient: relay.client)));
      await _enterFeedback(tester);
      await _submitFromCapture(tester, text: 'Keep this note.');

      await _tapAndSettleSheet(
          tester, find.byKey(const Key('feedback_preview_keep')));

      final drafts = await store.list();
      expect(drafts.single.report.text, 'Keep this note.');
      expect(drafts.single.state, ReportDeliveryState.saved);
      expect(relay.requests, isEmpty);
      expect(find.text('Saved'), findsOneWidget);
    });

    testWidgets('send reports the confirmed state with the issue link',
        (tester) async {
      const note = 'The image was not stored.';
      final relay = FakeRelay((request) async =>
          createdResponse('https://github.com/o/r/issues/42', note: note));
      final store = MemoryDraftStore();
      await tester.pumpWidget(_app(
          spec: testSpec(),
          store: store,
          client: RelayClient(spec: testSpec(), httpClient: relay.client)));
      await _enterFeedback(tester);
      await _submitFromCapture(tester, text: 'Send this note.');

      await _tapAndSettleSheet(
          tester, find.byKey(const Key('feedback_preview_send')));

      expect(relay.postCount, 1);
      expect((await store.list()).single.issueUrl,
          'https://github.com/o/r/issues/42');
      expect(find.text('Sent'), findsOneWidget);
      expect(find.text('https://github.com/o/r/issues/42'), findsOneWidget);
      expect(find.text(note), findsOneWidget);
    });

    testWidgets('a failed send keeps the draft and shows needs a check',
        (tester) async {
      final relay = FakeRelay((request) async => throw Exception('offline'));
      final store = MemoryDraftStore();
      await tester.pumpWidget(_app(
          spec: testSpec(),
          store: store,
          client: RelayClient(spec: testSpec(), httpClient: relay.client)));
      await _enterFeedback(tester);
      await _submitFromCapture(tester, text: 'Offline note.');

      await _tapAndSettleSheet(
          tester, find.byKey(const Key('feedback_preview_send')));

      expect(find.text('Needs a check'), findsOneWidget);
      expect((await store.list()).single.report.text, 'Offline note.');
    });
  });

  group('draft list', () {
    testWidgets('a tester can remove a saved draft', (tester) async {
      final store = MemoryDraftStore();
      final report = sampleReport(text: 'Remove me.');
      await store.save(ReportDraft(report: report));
      await tester.pumpWidget(_app(spec: testSpec(), store: store));
      await tester.pump();

      expect(find.text('Remove me.'), findsOneWidget);

      await tester.tap(find.byKey(Key('draft_remove_${report.id}')));
      await tester.pump();

      expect(find.text('Remove me.'), findsNothing);
      expect(await store.list(), isEmpty);
    });

    testWidgets('a needs-check draft offers a delivery check', (tester) async {
      final relay = FakeRelay((request) async => checkResponse('created',
          issueUrl: 'https://github.com/o/r/issues/11'));
      final store = MemoryDraftStore();
      final report = sampleReport(text: 'Check me.');
      await store.save(ReportDraft(
          report: report,
          state: ReportDeliveryState.needsCheck,
          note: 'No answer yet.'));
      await tester.pumpWidget(_app(
          spec: testSpec(),
          store: store,
          client: RelayClient(spec: testSpec(), httpClient: relay.client)));
      await tester.pump();

      await tester.tap(find.byKey(Key('draft_check_${report.id}')));
      await tester.pump();

      expect(relay.checkCount, 1);
      expect(find.text('Sent'), findsOneWidget);
    });

    testWidgets('the draft list keeps a production build free of controls',
        (tester) async {
      await tester
          .pumpWidget(_app(spec: production, store: MemoryDraftStore()));

      expect(find.text('No saved reports.'), findsOneWidget);
    });
  });
}
