import 'dart:convert';
import 'dart:typed_data';

import 'package:feedback_relay/feedback_relay.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A 1x1 PNG image. It keeps the widget tests off a real screenshot.
final Uint8List onePixelPng = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

/// A scripted relay that records every request and answers from a handler.
class FakeRelay {
  /// Creates the fake around one handler.
  FakeRelay(this.handler);

  /// Answers one request.
  final Future<http.Response> Function(http.Request request) handler;

  /// Every request that the client sent, in order.
  final List<http.Request> requests = <http.Request>[];

  /// The HTTP client for the relay client under test.
  late final http.Client client = MockClient((request) async {
    requests.add(request);
    return handler(request);
  });

  /// The number of sent reports.
  int get postCount =>
      requests.where((request) => request.method == 'POST').length;

  /// The number of delivery checks.
  int get checkCount =>
      requests.where((request) => request.method == 'GET').length;

  /// The JSON body of the last sent report.
  Map<String, dynamic> get lastBody =>
      jsonDecode(requests.last.body) as Map<String, dynamic>;
}

/// A relay answer for a confirmed report.
http.Response createdResponse(String issueUrl,
        {String status = 'created', String? note}) =>
    http.Response(
      jsonEncode(<String, dynamic>{
        'ok': true,
        'status': status,
        'issue_url': issueUrl,
        if (note != null) 'note': note
      }),
      status == 'created' ? 201 : 200,
    );

/// A relay answer for a rejected report.
http.Response errorResponse(String error, int statusCode, {String? delivery}) =>
    http.Response(
      jsonEncode(<String, dynamic>{
        'ok': false,
        'error': error,
        if (delivery != null) 'delivery': delivery
      }),
      statusCode,
    );

/// A relay answer for a delivery check.
http.Response checkResponse(String status, {String? issueUrl, String? note}) =>
    http.Response(
      jsonEncode(<String, dynamic>{
        'ok': true,
        'status': status,
        if (issueUrl != null) 'issue_url': issueUrl,
        if (note != null) 'note': note
      }),
      200,
    );

/// A test build spec for one product.
FeedbackBuildSpec testSpec({String productId = 'alpha-notes'}) =>
    FeedbackBuildSpec.forTest(
      backendUrl: 'https://relay.test',
      productId: productId,
      testerToken: 'tester-token',
      productName: 'Alpha Notes',
    );

/// A sample report for one product.
FeedbackReport sampleReport({
  String text = 'The list is empty after a restart.',
  Uint8List? screenshot,
  String productId = 'alpha-notes',
  String id = '11111111-2222-4333-8444-555555555555',
}) =>
    FeedbackReport.create(
      id: id,
      text: text,
      expected: 'The saved items stay visible.',
      steps: '1. Add one item\n2. Restart the app',
      screenshot: screenshot,
      productId: productId,
      appVersion: '1.2.4',
      buildNumber: '77',
      buildMode: 'test',
      screen: 'notes_list',
      device: const DeviceFacts(
          model: 'Pixel 7',
          platform: 'android',
          osVersion: 'Android 15',
          locale: 'en_US'),
    );
