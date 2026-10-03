import 'dart:convert';
import 'dart:math';

import 'package:feedback_relay/feedback_relay.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/relay_fakes.dart';

void main() {
  group('FeedbackReport', () {
    test('keeps a stable id across a retry', () {
      final report = sampleReport();
      final again = FeedbackReport(
        id: report.id,
        text: report.text,
        expected: report.expected,
        steps: report.steps,
        context: report.context,
      );
      expect(again.id, report.id);
      expect(again.copyWith(text: 'changed').id, report.id);
    });

    test('makes a version 4 shaped id from a fixed random source', () {
      final id = newReportId(Random(7));
      expect(id, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    });

    test('makes a different id for each report', () {
      final ids = <String>{for (var i = 0; i < 200; i++) newReportId()};
      expect(ids.length, 200);
    });

    test('writes the versioned report format with known build facts', () {
      final json = sampleReport(screenshot: onePixelPng).toJson();
      expect(json['schema'], kReportSchema);
      expect(json['report_id'], '11111111-2222-4333-8444-555555555555');
      expect(json['text'], 'The list is empty after a restart.');
      expect(json['expected'], 'The saved items stay visible.');
      expect(json['screenshot_b64'], base64Encode(onePixelPng));
      final context = json['context'] as Map<String, dynamic>;
      expect(context['product_id'], 'alpha-notes');
      expect(context['app_version'], '1.2.4');
      expect(context['build_number'], '77');
      expect(context['build_mode'], 'test');
      expect(context['screen'], 'notes_list');
      expect(context['captured_at'], endsWith('Z'));
      expect(context['device'], <String, dynamic>{
        'model': 'Pixel 7',
        'platform': 'android',
        'os_version': 'Android 15',
        'locale': 'en_US',
      });
    });

    test('keeps unknown facts as Unknown and allows a text-only report', () {
      final report = FeedbackReport.create(text: 'Only text.', productId: 'beta-tracker');
      final json = report.toJson();
      expect(json['screenshot_b64'], isNull);
      expect(report.hasScreenshot, isFalse);
      final context = json['context'] as Map<String, dynamic>;
      expect(context['app_version'], kUnknownFact);
      expect(context['build_number'], kUnknownFact);
      expect(context['screen'], kUnknownFact);
      expect(context['source_revision'], kUnknownFact);
      expect(context['device'], <String, dynamic>{
        'model': kUnknownFact,
        'platform': kUnknownFact,
        'os_version': kUnknownFact,
        'locale': kUnknownFact,
      });
      expect(context.containsKey('product_name'), isFalse);
    });

    test('reads back the same report from JSON', () {
      final report = sampleReport(screenshot: onePixelPng);
      final restored = FeedbackReport.fromJson(jsonDecode(jsonEncode(report.toJson())) as Map<String, dynamic>);
      expect(restored.id, report.id);
      expect(restored.text, report.text);
      expect(restored.expected, report.expected);
      expect(restored.steps, report.steps);
      expect(restored.screenshot, equals(onePixelPng));
      expect(restored.context.productId, 'alpha-notes');
      expect(restored.context.device, report.context.device);
      expect(restored.context.capturedAt.toUtc(), report.context.capturedAt.toUtc());
    });

    test('drops empty optional text instead of sending blank fields', () {
      final report = FeedbackReport.create(text: 'Text.', productId: 'alpha-notes', expected: '   ', steps: '');
      expect(report.expected, isNull);
      expect(report.steps, isNull);
    });

    test('carries no source revision unless the host supplies one', () {
      final without = FeedbackReport.create(text: 'Text.', productId: 'alpha-notes');
      expect(without.context.sourceRevision, kUnknownFact);
      final with_ = FeedbackReport.create(text: 'Text.', productId: 'alpha-notes', sourceRevision: '9f8e7d6');
      expect(with_.context.sourceRevision, '9f8e7d6');
    });

    test('the published caps agree with the relay limits', () {
      // The relay refuses a longer text or a larger image. The app must not
      // send a report that the relay will reject.
      expect(kMaxReportTextLength, 10000);
      expect(kMaxScreenshotBytes, 4 * 1024 * 1024);
    });
  });

  group('DeviceFacts', () {
    test('keeps a missing fact as Unknown', () {
      final facts = DeviceFacts.fromJson(<String, dynamic>{'model': 'Pixel 7'});
      expect(facts.model, 'Pixel 7');
      expect(facts.platform, kUnknownFact);
      expect(facts.osVersion, kUnknownFact);
      expect(facts.locale, kUnknownFact);
    });
  });
}
