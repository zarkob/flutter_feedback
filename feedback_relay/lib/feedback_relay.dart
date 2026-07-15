/// Feedback Relay — companion package for the `feedback` plugin.
///
/// Replaces the default submission path with a configurable backend relay.
/// The user's annotated screenshot and comment are POSTed to your own
/// serverless backend (see the sibling `relay/` Cloudflare Worker), which
/// files them as a GitHub issue in your project's repository.
///
/// The app ships **only** a backend URL and a pre-encrypted product id. No
/// GitHub token, no API key, no private key ever enters the APK. See the
/// `relay/docs/OPERATOR_RUNBOOK.md` for the end-to-end security model.
library;

import 'dart:async';
import 'dart:convert';

import 'package:feedback/feedback.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

export 'package:feedback/feedback.dart';

/// Configuration for the relay backend.
///
/// [backendUrl] is the deployed Worker endpoint (no trailing slash), e.g.
/// `https://your-worker.workers.dev`.
///
/// [productIdEnc] is the RSA-OAEP-encrypted product identifier, base64-encoded.
/// Encrypt the plaintext product id once with the backend's public key (see
/// `relay/docs/OPERATOR_RUNBOOK.md`) and bake the resulting ciphertext into the
/// app config as a constant. This value is **not secret** — it only selects
/// which secret bundle the backend uses.
///
/// [extraEntry] is optional static metadata merged into every submission
/// (e.g. a build channel). Per-submission metadata should be passed via the
/// `extra` map that `BetterFeedback` already collects.
@immutable
class RelayFeedbackConfig {
  /// Creates a relay configuration.
  ///
  /// [backendUrl] and [productIdEnc] are required. See the class doc for how
  /// to produce [productIdEnc] offline.
  const RelayFeedbackConfig({
    required this.backendUrl,
    required this.productIdEnc,
    this.extraEntry,
    this.httpClient,
  });

  /// The deployed relay Worker endpoint, no trailing slash.
  final String backendUrl;

  /// Base64 RSA-OAEP ciphertext of the product id (pre-encrypted offline).
  final String productIdEnc;

  /// Optional static metadata merged into every submission.
  final Map<String, dynamic>? extraEntry;

  /// Optional HTTP client (inject a mock in tests).
  @visibleForTesting
  final http.Client? httpClient;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RelayFeedbackConfig &&
          backendUrl == other.backendUrl &&
          productIdEnc == other.productIdEnc;

  @override
  int get hashCode => Object.hash(backendUrl, productIdEnc);
}

/// The outcome of a relay submission.
sealed class RelayFeedbackResult {
  /// The outcome of a relay submission.
  const RelayFeedbackResult();
}

/// The backend filed the issue successfully; [issueUrl] links to it.
final class RelayFeedbackSuccess extends RelayFeedbackResult {
  /// The backend filed the issue successfully; [issueUrl] links to it.
  const RelayFeedbackSuccess(this.issueUrl);

  /// The URL of the filed GitHub issue.
  final String issueUrl;
}

/// The backend rejected or failed the submission; [reason] is safe to surface
/// to the user (the backend never leaks secrets in responses).
final class RelayFeedbackFailure extends RelayFeedbackResult {
  /// The backend rejected or failed the submission; [reason] is safe to
  /// surface to the user.
  const RelayFeedbackFailure(this.reason);

  /// A human-readable, non-secret reason for the failure.
  final String reason;
}

/// Callback invoked after the relay attempts a submission.
typedef RelayFeedbackCallback = void Function(RelayFeedbackResult result);

/// Extension on [FeedbackController] adding a one-call entry point that opens
/// the upstream capture + annotation UI and submits to the relay on completion.
extension RelayFeedbackX on FeedbackController {
  /// Opens the feedback UI; on submit, sends the [UserFeedback] to the relay
  /// configured by [config] and invokes [onResult] with the outcome.
  ///
  /// This keeps the upstream annotation experience intact — only the submit
  /// target changes.
  void showRelayFeedback(
    RelayFeedbackConfig config, {
    RelayFeedbackCallback? onResult,
  }) {
    show(sendToRelay(config, onResult: onResult));
  }
}

/// Builds the [OnFeedbackCallback] that POSTs feedback to the relay.
///
/// Exposed (like `feedback_sentry`'s `sendToSentry`) so it can be composed or
/// tested independently of [FeedbackController.show].
@visibleForTesting
OnFeedbackCallback sendToRelay(
  RelayFeedbackConfig config, {
  RelayFeedbackCallback? onResult,
}) {
  return (UserFeedback feedback) async {
    final result = await submitToRelay(
      config: config,
      text: feedback.text,
      screenshot: feedback.screenshot,
      extra: feedback.extra,
    );
    onResult?.call(result);
  };
}

/// Submits a single piece of feedback to the relay and returns the outcome.
///
/// Separated from [sendToRelay] so the network call is unit-testable without a
/// live [UserFeedback].
Future<RelayFeedbackResult> submitToRelay({
  required RelayFeedbackConfig config,
  required String text,
  required Uint8List screenshot,
  Map<String, dynamic>? extra,
  String? appVersion,
  Map<String, dynamic>? deviceInfo,
}) async {
  final payload = <String, dynamic>{
    'product_id_enc': config.productIdEnc,
    // The Worker uploads the screenshot bytes to imgbb; encode as base64 here.
    'screenshot_b64': base64Encode(screenshot),
    'text': text,
    if (appVersion != null) 'app_version': appVersion,
    if (deviceInfo != null) 'device_info': deviceInfo,
    if (config.extraEntry != null) 'extra': config.extraEntry,
    if (extra != null && extra.isNotEmpty) 'user_extra': extra,
  };

  final client = config.httpClient ?? http.Client();
  final ownsClient = config.httpClient == null;
  try {
    final res = await client.post(
      Uri.parse('${config.backendUrl}/feedback'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    final body = res.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(res.body) as Map<String, dynamic>;

    if (res.statusCode == 200 && body['ok'] == true) {
      final url = body['issue_url'];
      if (url is String && url.isNotEmpty) {
        return RelayFeedbackSuccess(url);
      }
      return const RelayFeedbackFailure('Malformed success response');
    }

    final err = body['error'];
    return RelayFeedbackFailure(
      err is String && err.isNotEmpty ? err : 'Submission failed',
    );
  } catch (_) {
    return const RelayFeedbackFailure('Network error');
  } finally {
    if (ownsClient) {
      client.close();
    }
  }
}

/// Convenience wrapper that places a [BetterFeedback] widget above [child],
/// enabling `BetterFeedback.of(context).showRelayFeedback(...)` anywhere below.
///
/// This is the typical integration point: wrap your root app once, then trigger
/// feedback from a button anywhere in the tree. All upstream [BetterFeedback]
/// parameters (theme, localization, feedback builder, …) are forwarded.
class RelayFeedback extends StatelessWidget {
  /// Creates a [RelayFeedback] wrapper that forwards all parameters to
  /// [BetterFeedback]. Prefer [RelayFeedback.wrap] for the common case.
  const RelayFeedback({
    required this.child,
    super.key,
    this.feedbackBuilder,
    this.themeMode,
    this.theme,
    this.darkTheme,
    this.localizationsDelegates,
    this.localeOverride,
    this.mode = FeedbackMode.draw,
    this.pixelRatio = 3.0,
  }) : assert(pixelRatio > 0, 'pixelRatio needs to be larger than 0');

  /// The application to wrap, typically a [MaterialApp].
  final Widget child;

  /// Forwarded to [BetterFeedback]. See its docs.
  final FeedbackBuilder? feedbackBuilder;

  /// Forwarded to [BetterFeedback]. See its docs.
  final ThemeMode? themeMode;

  /// Forwarded to [BetterFeedback]. See its docs.
  final FeedbackThemeData? theme;

  /// Forwarded to [BetterFeedback]. See its docs.
  final FeedbackThemeData? darkTheme;

  /// Forwarded to [BetterFeedback]. See its docs.
  final List<LocalizationsDelegate<dynamic>>? localizationsDelegates;

  /// Forwarded to [BetterFeedback]. See its docs.
  final Locale? localeOverride;

  /// Forwarded to [BetterFeedback]. See its docs.
  final FeedbackMode mode;

  /// Forwarded to [BetterFeedback]. See its docs.
  final double pixelRatio;

  @override
  Widget build(BuildContext context) {
    return BetterFeedback(
      key: key,
      feedbackBuilder: feedbackBuilder,
      themeMode: themeMode,
      theme: theme,
      darkTheme: darkTheme,
      localizationsDelegates: localizationsDelegates,
      localeOverride: localeOverride,
      mode: mode,
      pixelRatio: pixelRatio,
      child: child,
    );
  }

  /// Shorthand for `RelayFeedback(child: child)` — mirrors the brief's
  /// `RelayFeedback.wrap(child)` call shape.
  static Widget wrap(
    Widget child, {
    Key? key,
    FeedbackBuilder? feedbackBuilder,
    ThemeMode? themeMode,
    FeedbackThemeData? theme,
    FeedbackThemeData? darkTheme,
    Iterable<LocalizationsDelegate<dynamic>>? localizationsDelegates,
    Locale? localeOverride,
    FeedbackMode mode = FeedbackMode.draw,
    double pixelRatio = 3.0,
  }) {
    return RelayFeedback(
      key: key,
      feedbackBuilder: feedbackBuilder,
      themeMode: themeMode,
      theme: theme,
      darkTheme: darkTheme,
      localizationsDelegates: localizationsDelegates?.toList(),
      localeOverride: localeOverride,
      mode: mode,
      pixelRatio: pixelRatio,
      child: child,
    );
  }
}
