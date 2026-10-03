import 'dart:convert';
import 'dart:typed_data';

import 'package:feedback_relay/feedback_relay.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/relay_fakes.dart';

void main() {
  group('RelayClient.submit', () {
    test('reports a confirmed delivery with the issue link', () async {
      final relay = FakeRelay((request) async => createdResponse('https://github.com/o/r/issues/12'));
      final client = RelayClient(spec: testSpec(), httpClient: relay.client);

      final result = await client.submit(sampleReport(screenshot: onePixelPng));

      expect(result, isA<DeliveryConfirmed>());
      expect((result as DeliveryConfirmed).issueUrl, 'https://github.com/o/r/issues/12');
      expect(result.duplicate, isFalse);
      expect(relay.requests.single.method, 'POST');
      expect(relay.requests.single.url.toString(), 'https://relay.test/reports');
      expect(relay.requests.single.headers['X-Tester-Token'], 'tester-token');
      expect(relay.requests.single.headers['Content-Type'], startsWith('application/json'));
    });

    test('reads a repeat of the same report as a duplicate, not a new issue', () async {
      final relay = FakeRelay((request) async => createdResponse('https://github.com/o/r/issues/12', status: 'duplicate'));
      final client = RelayClient(spec: testSpec(), httpClient: relay.client);

      final result = await client.submit(sampleReport());

      expect(result, isA<DeliveryConfirmed>());
      expect((result as DeliveryConfirmed).duplicate, isTrue);
    });

    test('keeps a timeout unknown, not failed and not sent', () async {
      final relay = FakeRelay((request) async => throw http.ClientException('connection closed before full header'));
      final client = RelayClient(spec: testSpec(), httpClient: relay.client);

      final result = await client.submit(sampleReport());

      expect(result, isA<DeliveryUnknown>());
      expect((result as DeliveryUnknown).reason, contains('may have arrived'));
    });

    test('keeps a 502 answer without a proven state unknown', () async {
      final relay = FakeRelay((request) async => errorResponse('Issue creation failed', 502));
      final client = RelayClient(spec: testSpec(), httpClient: relay.client);

      expect(await client.submit(sampleReport()), isA<DeliveryUnknown>());
    });

    test('reads a proven relay failure as a retryable failure', () async {
      final relay = FakeRelay((request) async => errorResponse('Issue creation failed', 502, delivery: 'failed'));
      final client = RelayClient(spec: testSpec(), httpClient: relay.client);

      final result = await client.submit(sampleReport());

      expect(result, isA<DeliveryFailed>());
      expect((result as DeliveryFailed).retryable, isTrue);
    });

    test('reads a rejected report as a failure that a retry cannot fix', () async {
      final relay = FakeRelay((request) async => errorResponse('Tester access denied', 403));
      final client = RelayClient(spec: testSpec(), httpClient: relay.client);

      final result = await client.submit(sampleReport()) as DeliveryFailed;

      expect(result.reason, 'Tester access denied');
      expect(result.retryable, isFalse);
    });

    test('keeps a rate limit retryable', () async {
      final relay = FakeRelay((request) async => errorResponse('Rate limit exceeded. Try again later.', 429));
      final client = RelayClient(spec: testSpec(), httpClient: relay.client);

      final result = await client.submit(sampleReport());

      expect(result, isA<DeliveryFailed>());
      expect((result as DeliveryFailed).retryable, isTrue);
    });

    test('keeps an unreadable success answer unknown', () async {
      final relay = FakeRelay((request) async => http.Response(jsonEncode(<String, dynamic>{'ok': true, 'status': 'created'}), 201));
      final client = RelayClient(spec: testSpec(), httpClient: relay.client);

      expect(await client.submit(sampleReport()), isA<DeliveryUnknown>());
    });

    test('refuses to send from a production build', () async {
      final relay = FakeRelay((request) async => createdResponse('https://github.com/o/r/issues/1'));
      final client = RelayClient(spec: const FeedbackBuildSpec.production(), httpClient: relay.client);

      final result = await client.submit(sampleReport());

      expect(result, isA<DeliveryFailed>());
      expect(relay.requests, isEmpty);
    });

    test('refuses an empty report before the network call', () async {
      final relay = FakeRelay((request) async => createdResponse('https://github.com/o/r/issues/1'));
      final client = RelayClient(spec: testSpec(), httpClient: relay.client);

      final result = await client.submit(sampleReport(text: '   '));

      expect(result, isA<DeliveryFailed>());
      expect(relay.requests, isEmpty);
    });

    test('refuses a report above the image limit before the network call', () async {
      final relay = FakeRelay((request) async => createdResponse('https://github.com/o/r/issues/1'));
      final client = RelayClient(spec: testSpec(), httpClient: relay.client);

      final result = await client.submit(sampleReport(screenshot: Uint8List(kMaxScreenshotBytes + 1)));

      expect(result, isA<DeliveryFailed>());
      expect((result as DeliveryFailed).reason, contains('too large'));
      expect(relay.requests, isEmpty);
    });

    test('sends a text-only report without an image field value', () async {
      final relay = FakeRelay((request) async => createdResponse('https://github.com/o/r/issues/3'));
      final client = RelayClient(spec: testSpec(), httpClient: relay.client);

      await client.submit(sampleReport());

      expect(relay.lastBody['screenshot_b64'], isNull);
      expect(relay.lastBody['text'], 'The list is empty after a restart.');
    });
  });

  group('RelayClient.check', () {
    test('reads a proven delivery', () async {
      final relay = FakeRelay((request) async => checkResponse('created', issueUrl: 'https://github.com/o/r/issues/9'));
      final client = RelayClient(spec: testSpec(), httpClient: relay.client);

      final result = await client.check('abc');

      expect(result, isA<DeliveryConfirmed>());
      expect(relay.requests.single.url.toString(), 'https://relay.test/reports/abc');
      expect(relay.requests.single.method, 'GET');
    });

    test('reads a missing record as safe to send again', () async {
      final relay = FakeRelay((request) async => checkResponse('not_found'));
      final client = RelayClient(spec: testSpec(), httpClient: relay.client);

      expect(await client.check('abc'), isA<DeliveryNotRecorded>());
    });

    test('keeps an unproven record unknown', () async {
      final relay = FakeRelay((request) async => checkResponse('unknown'));
      final client = RelayClient(spec: testSpec(), httpClient: relay.client);

      expect(await client.check('abc'), isA<DeliveryUnknown>());
    });
  });
}
