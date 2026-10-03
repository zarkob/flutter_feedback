import 'dart:io';

import 'package:feedback_relay/file_draft_store.dart';
import 'package:feedback_relay/feedback_relay.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/relay_fakes.dart';

void main() {
  group('MemoryDraftStore', () {
    test('saves, lists, loads, and removes a draft', () async {
      final store = MemoryDraftStore();
      final draft = ReportDraft(report: sampleReport());
      await store.save(draft);

      expect((await store.list()).single.id, draft.id);
      expect((await store.load(draft.id))?.report.text, draft.report.text);

      await store.remove(draft.id);
      expect(await store.load(draft.id), isNull);
      expect(await store.list(), isEmpty);
    });

    test('lists the newest draft first', () async {
      final store = MemoryDraftStore();
      await store.save(
        ReportDraft(
          report: FeedbackReport.create(
            text: 'older',
            productId: 'p',
            capturedAt: DateTime.utc(2026, 10, 1),
          ),
        ),
      );
      await store.save(
        ReportDraft(
          report: FeedbackReport.create(text: 'newer', productId: 'p', capturedAt: DateTime.utc(2026, 10, 3)),
        ),
      );

      final drafts = await store.list();

      expect(drafts.map((draft) => draft.report.text), <String>['newer', 'older']);
    });
  });

  group('FileDraftStore', () {
    late Directory root;
    late FileDraftStore store;

    setUp(() {
      root = Directory.systemTemp.createTempSync('feedback_drafts_test');
      store = FileDraftStore(root);
    });

    tearDown(() {
      if (root.existsSync()) {
        root.deleteSync(recursive: true);
      }
    });

    test('keeps the text, the image, the report id, and the state', () async {
      final report = sampleReport(screenshot: onePixelPng);
      await store.save(ReportDraft(report: report, state: ReportDeliveryState.needsCheck, note: 'No answer yet.'));

      final restored = await store.load(report.id);

      expect(restored, isNotNull);
      expect(restored!.report.id, report.id);
      expect(restored.report.text, report.text);
      expect(restored.report.screenshot, equals(onePixelPng));
      expect(restored.report.context.device.model, 'Pixel 7');
      expect(restored.state, ReportDeliveryState.needsCheck);
      expect(restored.note, 'No answer yet.');
    });

    test('survives a restart through a new store on the same folder', () async {
      final report = sampleReport();
      await store.save(ReportDraft(report: report));

      final afterRestart = FileDraftStore(root);
      final drafts = await afterRestart.list();

      expect(drafts.single.id, report.id);
      expect(drafts.single.state, ReportDeliveryState.saved);
    });

    test('replaces a draft and its image instead of adding a second one', () async {
      final report = sampleReport(screenshot: onePixelPng);
      await store.save(ReportDraft(report: report));
      await store.save(ReportDraft(report: report.copyWith(text: 'Changed.'), state: ReportDeliveryState.sent, issueUrl: 'https://github.com/o/r/issues/4'));

      final drafts = await store.list();

      expect(drafts.length, 1);
      expect(drafts.single.report.text, 'Changed.');
      expect(drafts.single.state, ReportDeliveryState.sent);
      expect(drafts.single.issueUrl, 'https://github.com/o/r/issues/4');
    });

    test('removes the folder of a draft', () async {
      final report = sampleReport(screenshot: onePixelPng);
      await store.save(ReportDraft(report: report));

      await store.remove(report.id);

      expect(await store.load(report.id), isNull);
      expect(root.listSync(), isEmpty);
    });

    test('refuses a report id that is not safe for a file name', () async {
      await expectLater(() => store.save(ReportDraft(report: sampleReport(id: '../escape'))), throwsArgumentError);
      await expectLater(() => store.load('..'), throwsArgumentError);
    });

    test('ignores a broken draft file instead of failing the whole list', () async {
      final report = sampleReport();
      await store.save(ReportDraft(report: report));
      File('${root.path}/${report.id}/draft.json').writeAsStringSync('{not json');

      expect(await store.list(), isEmpty);
    });

    test('keeps the image out of a saved draft when the report has none', () async {
      final report = sampleReport();
      await store.save(ReportDraft(report: report));

      final restored = await store.load(report.id);

      expect(restored!.report.hasScreenshot, isFalse);
      expect(File('${root.path}/${report.id}/screenshot.png').existsSync(), isFalse);
    });
  });
}
