import 'package:feedback_relay/feedback_relay.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/relay_fakes.dart';

class _FixedContext implements FeedbackContextSource {
  const _FixedContext();

  @override
  String get appVersion => '1.2.4';

  @override
  String get buildNumber => '77';

  @override
  String get screen => 'notes_list';

  @override
  String get sourceRevision => 'Unknown';

  @override
  DeviceFacts get device => const DeviceFacts(model: 'Pixel 7', platform: 'android', osVersion: 'Android 15', locale: 'en_US');
}

void main() {
  group('FeedbackFlow', () {
    test('builds a report from tester text and host facts', () {
      final flow = FeedbackFlow(spec: testSpec(), store: MemoryDraftStore(), contextSource: const _FixedContext());

      final report = flow.buildReport(text: 'The list is empty.', screenshot: onePixelPng);

      expect(report.context.productId, 'alpha-notes');
      expect(report.context.productName, 'Alpha Notes');
      expect(report.context.appVersion, '1.2.4');
      expect(report.context.buildNumber, '77');
      expect(report.context.buildMode, 'test');
      expect(report.context.screen, 'notes_list');
      expect(report.context.sourceRevision, kUnknownFact);
      expect(report.context.device.model, 'Pixel 7');
    });

    test('refuses to build a report in a production build', () {
      final flow = FeedbackFlow(spec: const FeedbackBuildSpec.production(), store: MemoryDraftStore());
      expect(() => flow.buildReport(text: 'Text.'), throwsStateError);
    });

    test('keeps a draft without sending it', () async {
      final relay = FakeRelay((request) async => createdResponse('https://github.com/o/r/issues/1'));
      final store = MemoryDraftStore();
      final flow = FeedbackFlow(spec: testSpec(), store: store, client: RelayClient(spec: testSpec(), httpClient: relay.client));

      await flow.keep(sampleReport());

      expect(relay.requests, isEmpty);
      expect((await store.list()).single.state, ReportDeliveryState.saved);
    });

    test('marks a report sent only after the destination confirms it', () async {
      final relay = FakeRelay((request) async => createdResponse('https://github.com/o/r/issues/12'));
      final store = MemoryDraftStore();
      final flow = FeedbackFlow(spec: testSpec(), store: store, client: RelayClient(spec: testSpec(), httpClient: relay.client));

      final result = await flow.send(sampleReport());

      expect(result, isA<DeliveryConfirmed>());
      final saved = (await store.list()).single;
      expect(saved.state, ReportDeliveryState.sent);
      expect(saved.issueUrl, 'https://github.com/o/r/issues/12');
    });

    test('keeps the note and the image after a failed send', () async {
      final relay = FakeRelay((request) async => throw http.ClientException('offline'));
      final store = MemoryDraftStore();
      final flow = FeedbackFlow(spec: testSpec(), store: store, client: RelayClient(spec: testSpec(), httpClient: relay.client));

      await flow.send(sampleReport(screenshot: onePixelPng));

      final saved = (await store.list()).single;
      expect(saved.state, ReportDeliveryState.needsCheck);
      expect(saved.report.screenshot, equals(onePixelPng));
      expect(saved.note, contains('may have arrived'));
    });

    test('keeps a rate limited report waiting and a rejected report failed', () async {
      final store = MemoryDraftStore();
      var answer = errorResponse('Rate limit exceeded. Try again later.', 429);
      final relay = FakeRelay((request) async => answer);
      final flow = FeedbackFlow(spec: testSpec(), store: store, client: RelayClient(spec: testSpec(), httpClient: relay.client));

      await flow.send(sampleReport());
      expect((await store.list()).single.state, ReportDeliveryState.waiting);

      answer = errorResponse('Tester access denied', 403);
      await flow.send(sampleReport(id: '22222222-3333-4444-8555-666666666666'));
      final rejected = (await store.list()).firstWhere((draft) => draft.id == '22222222-3333-4444-8555-666666666666');
      expect(rejected.state, ReportDeliveryState.failed);
      expect(rejected.note, 'Tester access denied');
    });

    test('sends one request when the same report is sent twice at once', () async {
      final relay = FakeRelay((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        return createdResponse('https://github.com/o/r/issues/5');
      });
      final flow = FeedbackFlow(spec: testSpec(), store: MemoryDraftStore(), client: RelayClient(spec: testSpec(), httpClient: relay.client));
      final report = sampleReport();

      final results = await Future.wait(<Future<DeliveryResult>>[flow.send(report), flow.send(report)]);

      expect(relay.postCount, 1);
      expect(results.every((result) => result is DeliveryConfirmed), isTrue);
    });

    test('checks an unknown report before it sends again', () async {
      final relay = FakeRelay((request) async {
        if (request.method == 'GET') {
          return checkResponse('not_found');
        }
        return createdResponse('https://github.com/o/r/issues/6');
      });
      final store = MemoryDraftStore();
      final flow = FeedbackFlow(spec: testSpec(), store: store, client: RelayClient(spec: testSpec(), httpClient: relay.client));
      final report = sampleReport();
      await store.save(ReportDraft(report: report, state: ReportDeliveryState.needsCheck, note: 'No answer yet.'));
      await flow.recover();

      final result = await flow.retry(report.id);

      expect(result, isA<DeliveryConfirmed>());
      expect(relay.checkCount, 1);
      expect(relay.postCount, 1);
      expect(relay.lastBody['report_id'], report.id);
    });

    test('does not send again when the check proves the report arrived', () async {
      final relay = FakeRelay((request) async {
        if (request.method == 'GET') {
          return checkResponse('created', issueUrl: 'https://github.com/o/r/issues/7');
        }
        return createdResponse('https://github.com/o/r/issues/7');
      });
      final store = MemoryDraftStore();
      final flow = FeedbackFlow(spec: testSpec(), store: store, client: RelayClient(spec: testSpec(), httpClient: relay.client));
      final report = sampleReport();
      await store.save(ReportDraft(report: report, state: ReportDeliveryState.needsCheck));
      await flow.recover();

      final result = await flow.retry(report.id);

      expect(result, isA<DeliveryConfirmed>());
      expect(relay.postCount, 0);
      expect((await store.list()).single.state, ReportDeliveryState.sent);
      expect((await store.list()).single.issueUrl, 'https://github.com/o/r/issues/7');
    });

    test('keeps an unproven report as needs a check instead of sending blindly', () async {
      final relay = FakeRelay((request) async {
        if (request.method == 'GET') {
          return checkResponse('unknown');
        }
        return createdResponse('https://github.com/o/r/issues/8');
      });
      final store = MemoryDraftStore();
      final flow = FeedbackFlow(spec: testSpec(), store: store, client: RelayClient(spec: testSpec(), httpClient: relay.client));
      final report = sampleReport();
      await store.save(ReportDraft(report: report, state: ReportDeliveryState.needsCheck));
      await flow.recover();

      final result = await flow.retry(report.id);

      expect(result, isA<DeliveryUnknown>());
      expect(relay.postCount, 0);
      expect((await store.list()).single.state, ReportDeliveryState.needsCheck);
    });

    test('recovers a draft from an earlier run and resolves an interrupted send', () async {
      final store = MemoryDraftStore();
      final saved = sampleReport(id: '33333333-4444-4555-8666-777777777777');
      await store.save(ReportDraft(report: saved, state: ReportDeliveryState.saved));
      await store.save(
        ReportDraft(
          report: sampleReport(id: '44444444-5555-4666-8777-888888888888'),
          state: ReportDeliveryState.waiting,
        ),
      );
      final relay = FakeRelay((request) async => checkResponse('created', issueUrl: 'https://github.com/o/r/issues/9'));
      final flow = FeedbackFlow(spec: testSpec(), store: store, client: RelayClient(spec: testSpec(), httpClient: relay.client));

      await flow.recover();

      expect(flow.drafts.length, 2);
      final interrupted = flow.drafts.firstWhere((draft) => draft.id == '44444444-5555-4666-8777-888888888888');
      expect(interrupted.state, ReportDeliveryState.sent);
      expect(interrupted.issueUrl, 'https://github.com/o/r/issues/9');
      final kept = flow.drafts.firstWhere((draft) => draft.id == saved.id);
      expect(kept.state, ReportDeliveryState.saved);
    });

    test('removes a saved draft', () async {
      final store = MemoryDraftStore();
      final flow = FeedbackFlow(spec: testSpec(), store: store);
      final report = sampleReport();
      await flow.keep(report);

      await flow.remove(report.id);

      expect(flow.drafts, isEmpty);
      expect(await store.list(), isEmpty);
    });

    test('reports a missing draft instead of sending something unknown', () async {
      final flow = FeedbackFlow(spec: testSpec(), store: MemoryDraftStore());
      expect(await flow.retry('missing'), isA<DeliveryFailed>());
      expect(await flow.check('missing'), isA<DeliveryFailed>());
    });
  });
}
