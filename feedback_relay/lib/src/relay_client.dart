/// The relay client for the shared feedback tool.
///
/// The client sends one report to the relay and reads the delivery state
/// back. It never decides that a report was delivered: only the destination
/// confirmation counts. A send without an answer stays unknown.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'build_spec.dart';
import 'report.dart';

/// The result of a relay call.
sealed class DeliveryResult {
  /// Creates a result.
  const DeliveryResult();
}

/// The destination confirmed the report.
final class DeliveryConfirmed extends DeliveryResult {
  /// Creates a confirmed result with the issue link.
  const DeliveryConfirmed(this.issueUrl, {this.duplicate = false, this.note});

  /// The link to the product issue.
  final String issueUrl;

  /// True when the destination already held this report id.
  final bool duplicate;

  /// An optional note about what the relay could not store.
  final String? note;
}

/// The relay holds no record of this report id, so a send is safe.
final class DeliveryNotRecorded extends DeliveryResult {
  /// Creates a not-recorded result.
  const DeliveryNotRecorded(this.reason);

  /// A short honest reason.
  final String reason;
}

/// The delivery state is unknown. The report may or may not have arrived.
final class DeliveryUnknown extends DeliveryResult {
  /// Creates an unknown result.
  const DeliveryUnknown(this.reason);

  /// A short honest reason.
  final String reason;
}

/// The relay rejected the report, or the send could not start.
final class DeliveryFailed extends DeliveryResult {
  /// Creates a failed result.
  const DeliveryFailed(this.reason, {this.retryable = false});

  /// A short honest reason that is safe to show.
  final String reason;

  /// True when a later retry can succeed without a settings change.
  final bool retryable;
}

/// Sends reports to the relay and reads delivery state back.
///
/// The client uses the build spec as its switch. A disabled build cannot send,
/// even when a report object exists.
class RelayClient {
  /// Creates a client for one enabled build.
  RelayClient({
    required this.spec,
    http.Client? httpClient,
    this.sendTimeout = const Duration(seconds: 30),
    this.checkTimeout = const Duration(seconds: 15),
  })  : _httpClient = httpClient ?? http.Client(),
        _ownsClient = httpClient == null;

  /// The build boundary. A production spec keeps the client closed.
  final FeedbackBuildSpec spec;

  /// The timeout for one send. A timeout leaves the delivery state unknown.
  final Duration sendTimeout;

  /// The timeout for one delivery check.
  final Duration checkTimeout;

  final http.Client _httpClient;
  final bool _ownsClient;

  /// Sends one report.
  ///
  /// The report id travels with the report. A repeat of the same id cannot
  /// create a second issue.
  Future<DeliveryResult> submit(FeedbackReport report) async {
    final settings = spec.settings;
    if (settings == null) {
      return const DeliveryFailed('Feedback is not enabled in this build.',
          retryable: false);
    }
    final problem = _checkReport(report);
    if (problem != null) {
      return DeliveryFailed(problem, retryable: false);
    }
    return _post(
      settings: settings,
      path: '/reports',
      body: jsonEncode(report.toJson()),
      timeout: sendTimeout,
    );
  }

  /// Reads the delivery state for one report id.
  ///
  /// No record means that the relay never claimed the report, so a send is
  /// safe. Any other answer keeps the state unknown until the relay proves it.
  Future<DeliveryResult> check(String reportId) async {
    final settings = spec.settings;
    if (settings == null) {
      return const DeliveryFailed('Feedback is not enabled in this build.',
          retryable: false);
    }
    return _post(
      settings: settings,
      path: '/reports/$reportId',
      body: null,
      timeout: checkTimeout,
    );
  }

  /// Closes the client when it owns the HTTP client.
  void close() {
    if (_ownsClient) {
      _httpClient.close();
    }
  }

  String? _checkReport(FeedbackReport report) {
    if (report.text.trim().isEmpty) {
      return 'The report has no text.';
    }
    if (report.text.length > kMaxReportTextLength) {
      return 'The report text is too long.';
    }
    if (report.screenshotBytes > kMaxScreenshotBytes) {
      return 'The screenshot is too large.';
    }
    return null;
  }

  Future<DeliveryResult> _post({
    required FeedbackRelaySettings settings,
    required String path,
    required String? body,
    required Duration timeout,
  }) async {
    final uri = Uri.parse('${settings.backendUrl}$path');
    try {
      final request = http.Request(body == null ? 'GET' : 'POST', uri)
        ..headers['Accept'] = 'application/json'
        ..headers['X-Tester-Token'] = settings.testerToken;
      if (body != null) {
        request.headers['Content-Type'] = 'application/json';
        request.body = body;
      }
      final streamed = await _httpClient.send(request).timeout(timeout);
      final response =
          await http.Response.fromStream(streamed).timeout(timeout);
      return _readResult(response);
    } on TimeoutException {
      return const DeliveryUnknown(
          'The relay did not answer in time. The report may have arrived.');
    } on http.ClientException catch (error) {
      return DeliveryUnknown(
          'The relay was not reachable (${error.message}). The report may have arrived.');
    } catch (error) {
      return DeliveryUnknown(
          'The send stopped with an unexpected error. The report may have arrived.');
    }
  }

  DeliveryResult _readResult(http.Response response) {
    Map<String, dynamic> body = const <String, dynamic>{};
    if (response.body.isNotEmpty) {
      try {
        final value = jsonDecode(response.body);
        if (value is Map<String, dynamic>) {
          body = value;
        }
      } on FormatException {
        return DeliveryUnknown(
            'The relay sent an answer that this app cannot read.');
      }
    }

    final status = body['status'];
    final issueUrl = body['issue_url'];
    final error = body['error'];
    final reason = error is String && error.isNotEmpty
        ? error
        : 'The relay rejected the report.';

    if (response.statusCode == 200 || response.statusCode == 201) {
      if (body['ok'] == true) {
        if (issueUrl is String &&
            issueUrl.isNotEmpty &&
            (status == 'created' || status == 'duplicate')) {
          final note = body['note'];
          return DeliveryConfirmed(
            issueUrl,
            duplicate: status == 'duplicate',
            note: note is String && note.isNotEmpty ? note : null,
          );
        }
        if (status == 'not_found') {
          return const DeliveryNotRecorded(
              'The relay holds no record of this report.');
        }
        if (status == 'unknown') {
          return DeliveryUnknown(reason);
        }
        return const DeliveryUnknown(
            'The relay answered without a delivery result.');
      }
      return DeliveryFailed(reason, retryable: false);
    }

    if (response.statusCode >= 500) {
      final delivery = body['delivery'];
      if (delivery == 'failed') {
        return DeliveryFailed(reason, retryable: true);
      }
      return DeliveryUnknown(reason);
    }

    final retryable = response.statusCode == 429 || response.statusCode == 408;
    return DeliveryFailed(reason, retryable: retryable);
  }
}
