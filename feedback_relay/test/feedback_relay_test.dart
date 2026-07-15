import 'dart:convert';
import 'dart:typed_data';

import 'package:feedback_relay/feedback_relay.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('submitToRelay', () {
    final screenshot = Uint8List.fromList([1, 2, 3, 4]);

    test('returns success with issue url on 200 {ok:true}', () async {
      final client = MockClient((request) async {
        expect(request.url.toString(), 'https://example.com/feedback');
        expect(request.headers['Content-Type'], 'application/json');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['product_id_enc'], 'enc-id');
        expect(body['text'], 'hello');
        expect(body['screenshot_b64'], base64Encode(screenshot));
        return http.Response(
          jsonEncode({'ok': true, 'issue_url': 'https://github.com/o/r/issues/1'}),
          200,
        );
      });

      final result = await submitToRelay(
        config: RelayFeedbackConfig(
          backendUrl: 'https://example.com',
          productIdEnc: 'enc-id',
          httpClient: client,
        ),
        text: 'hello',
        screenshot: screenshot,
      );

      expect(result, isA<RelayFeedbackSuccess>());
      expect(
        (result as RelayFeedbackSuccess).issueUrl,
        'https://github.com/o/r/issues/1',
      );
    });

    test('returns failure with backend reason on error response', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({'ok': false, 'error': 'Rate limit exceeded'}),
          429,
        );
      });

      final result = await submitToRelay(
        config: RelayFeedbackConfig(
          backendUrl: 'https://example.com',
          productIdEnc: 'enc-id',
          httpClient: client,
        ),
        text: 'hello',
        screenshot: screenshot,
      );

      expect(result, isA<RelayFeedbackFailure>());
      expect((result as RelayFeedbackFailure).reason, 'Rate limit exceeded');
    });

    test('returns generic failure on network error', () async {
      final client = MockClient((request) async {
        throw http.ClientException('connection refused');
      });

      final result = await submitToRelay(
        config: RelayFeedbackConfig(
          backendUrl: 'https://example.com',
          productIdEnc: 'enc-id',
          httpClient: client,
        ),
        text: 'hello',
        screenshot: screenshot,
      );

      expect(result, isA<RelayFeedbackFailure>());
      expect((result as RelayFeedbackFailure).reason, 'Network error');
    });

    test('returns failure on malformed success (missing issue_url)', () async {
      final client = MockClient((request) async {
        return http.Response(jsonEncode({'ok': true}), 200);
      });

      final result = await submitToRelay(
        config: RelayFeedbackConfig(
          backendUrl: 'https://example.com',
          productIdEnc: 'enc-id',
          httpClient: client,
        ),
        text: 'hello',
        screenshot: screenshot,
      );

      expect(result, isA<RelayFeedbackFailure>());
    });

    test('includes optional app_version and device_info when provided', () async {
      String? capturedBody;
      final client = MockClient((request) async {
        capturedBody = request.body;
        return http.Response(
          jsonEncode({'ok': true, 'issue_url': 'https://github.com/o/r/issues/2'}),
          200,
        );
      });

      await submitToRelay(
        config: RelayFeedbackConfig(
          backendUrl: 'https://example.com',
          productIdEnc: 'enc-id',
          httpClient: client,
        ),
        text: 'hello',
        screenshot: screenshot,
        appVersion: '1.2.3',
        deviceInfo: {'platform': 'android'},
      );

      final body = jsonDecode(capturedBody!) as Map<String, dynamic>;
      expect(body['app_version'], '1.2.3');
      expect(body['device_info'], {'platform': 'android'});
    });
  });

  group('RelayFeedbackConfig', () {
    test('equality is based on backendUrl and productIdEnc', () {
      const a = RelayFeedbackConfig(
        backendUrl: 'https://x.com',
        productIdEnc: 'id',
      );
      const b = RelayFeedbackConfig(
        backendUrl: 'https://x.com',
        productIdEnc: 'id',
        extraEntry: {'k': 'v'},
      );
      expect(a, b);
    });
  });
}
