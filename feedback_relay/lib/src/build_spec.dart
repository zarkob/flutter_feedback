/// The build boundary for the shared feedback tool.
///
/// One value decides three things: the wrapper, the entry controls, and the
/// sending path. Feedback is enabled only for an explicit `development` or
/// `test` build. A build with no feedback setting is a production build, so
/// the tool fails closed.
library;

import 'report.dart' show kUnknownFact;

/// The build mode names that the tool accepts.
abstract final class FeedbackBuildModes {
  /// A local development build with feedback enabled.
  static const String development = 'development';

  /// A test build with feedback enabled. It can use release mode.
  static const String test = 'test';

  /// A production build. It has no feedback surface and cannot send.
  static const String production = 'production';

  /// All accepted mode names.
  static const List<String> all = <String>[development, test, production];
}

/// A conflicting or missing feedback build setting.
///
/// The app boundary throws this error during startup. A start failure is
/// better than a production build with a hidden feedback path.
class FeedbackBoundaryError extends Error {
  /// Creates the error with the reason that the boundary found.
  FeedbackBoundaryError(this.reason);

  /// A short, honest reason for the rejected settings.
  final String reason;

  @override
  String toString() => 'FeedbackBoundaryError: $reason';
}

/// The resolved build boundary and its relay settings.
///
/// Build the value once at the app boundary with [FeedbackBuildSpec.fromEnvironment],
/// or with the named constructors in tests and fixtures. Pass the same value to
/// the wrapper, the entry controls, and the relay client. That single value is
/// the shared control for the whole tool.
class FeedbackBuildSpec {
  /// Creates a spec directly. Prefer [FeedbackBuildSpec.fromEnvironment].
  const FeedbackBuildSpec({
    required this.mode,
    this.backendUrl,
    this.productId,
    this.testerToken,
    this.productName,
    this.extra = const <String, String>{},
  });

  /// Reads the boundary from compile-time settings.
  ///
  /// Accepted defines:
  /// - `FEEDBACK_BUILD_MODE`: `development`, `test`, or `production`. The
  ///   default is `production`, so a build without the define stays closed.
  /// - `FEEDBACK_BACKEND_URL`: the relay endpoint, no trailing slash.
  /// - `FEEDBACK_PRODUCT_ID`: the public product id.
  /// - `FEEDBACK_TESTER_TOKEN`: the tester access token.
  /// - `FEEDBACK_PRODUCT_NAME`: an optional readable product name.
  /// - `FEEDBACK_ENABLED`: an optional explicit switch. It must agree with the
  ///   mode. A conflict stops the app at startup.
  factory FeedbackBuildSpec.fromEnvironment() {
    const mode = String.fromEnvironment('FEEDBACK_BUILD_MODE', defaultValue: FeedbackBuildModes.production);
    const backendUrl = String.fromEnvironment('FEEDBACK_BACKEND_URL');
    const productId = String.fromEnvironment('FEEDBACK_PRODUCT_ID');
    const testerToken = String.fromEnvironment('FEEDBACK_TESTER_TOKEN');
    const productName = String.fromEnvironment('FEEDBACK_PRODUCT_NAME');
    const enabled = bool.fromEnvironment('FEEDBACK_ENABLED', defaultValue: false);
    const hasEnabledFlag = bool.hasEnvironment('FEEDBACK_ENABLED');
    return FeedbackBuildSpec(
      mode: mode,
      backendUrl: backendUrl.isEmpty ? null : backendUrl,
      productId: productId.isEmpty ? null : productId,
      testerToken: testerToken.isEmpty ? null : testerToken,
      productName: productName.isEmpty ? null : productName,
      extra: hasEnabledFlag ? <String, String>{'FEEDBACK_ENABLED': '$enabled'} : const <String, String>{},
    ).checked();
  }

  /// A production spec. It has no relay settings and stays disabled.
  const FeedbackBuildSpec.production() : mode = FeedbackBuildModes.production, backendUrl = null, productId = null, testerToken = null, productName = null, extra = const <String, String>{};

  /// A test spec for fixtures and tests.
  const FeedbackBuildSpec.forTest({
    required this.backendUrl,
    required this.productId,
    required this.testerToken,
    this.productName,
    this.mode = FeedbackBuildModes.test,
  }) : extra = const <String, String>{};

  /// A development spec for a local run.
  const FeedbackBuildSpec.forDevelopment({
    required this.backendUrl,
    required this.productId,
    required this.testerToken,
    this.productName,
  }) : mode = FeedbackBuildModes.development, extra = const <String, String>{};

  /// The resolved build mode.
  final String mode;

  /// The relay endpoint, without a trailing slash.
  final String? backendUrl;

  /// The public product id. The server maps it to one destination.
  final String? productId;

  /// The tester access token. The server checks it before it accepts a report.
  final String? testerToken;

  /// An optional readable product name for the report context.
  final String? productName;

  /// Extra build settings, used only to detect conflicts. Not sent anywhere.
  final Map<String, String> extra;

  /// True when this build shows the wrapper, the entry controls, and sending.
  bool get isEnabled => mode != FeedbackBuildModes.production;

  /// True for a production build. The tool stays out of that build.
  bool get isProduction => mode == FeedbackBuildModes.production;

  /// The relay settings as one config, or null when the build is closed.
  FeedbackRelaySettings? get settings {
    final url = backendUrl;
    final product = productId;
    final token = testerToken;
    if (!isEnabled || url == null || product == null || token == null) {
      return null;
    }
    return FeedbackRelaySettings(backendUrl: url, productId: product, testerToken: token, productName: productName);
  }

  /// Checks the boundary and returns itself when the settings agree.
  ///
  /// Throws [FeedbackBoundaryError] for an unknown mode, for a production
  /// build with feedback settings, or for an enabled build with a missing
  /// relay setting.
  FeedbackBuildSpec checked() {
    if (!FeedbackBuildModes.all.contains(mode)) {
      throw FeedbackBoundaryError('Unknown feedback build mode "$mode". Use development, test, or production.');
    }
    final enabledFlag = extra['FEEDBACK_ENABLED'];
    final hasRelaySettings = backendUrl != null || productId != null || testerToken != null || productName != null;
    if (isProduction) {
      if (hasRelaySettings) {
        throw FeedbackBoundaryError('A production build must not carry feedback relay settings. Remove the FEEDBACK_* defines from this build.');
      }
      if (enabledFlag == 'true') {
        throw FeedbackBoundaryError('FEEDBACK_ENABLED=true conflicts with FEEDBACK_BUILD_MODE=production.');
      }
      return this;
    }
    if (enabledFlag == 'false') {
      throw FeedbackBoundaryError('FEEDBACK_ENABLED=false conflicts with FEEDBACK_BUILD_MODE=$mode.');
    }
    final missing = <String>[
      if (backendUrl == null) 'FEEDBACK_BACKEND_URL',
      if (productId == null) 'FEEDBACK_PRODUCT_ID',
      if (testerToken == null) 'FEEDBACK_TESTER_TOKEN',
    ];
    if (missing.isNotEmpty) {
      throw FeedbackBoundaryError('Feedback build mode "$mode" needs ${missing.join(', ')}.');
    }
    if (backendUrl!.endsWith('/')) {
      throw FeedbackBoundaryError('FEEDBACK_BACKEND_URL must not end with a slash.');
    }
    return this;
  }

  @override
  String toString() => 'FeedbackBuildSpec($mode, product: ${productId ?? kUnknownFact})';
}

/// The relay settings that one enabled build needs.
class FeedbackRelaySettings {
  /// Creates relay settings.
  const FeedbackRelaySettings({
    required this.backendUrl,
    required this.productId,
    required this.testerToken,
    this.productName,
  });

  /// The relay endpoint, without a trailing slash.
  final String backendUrl;

  /// The public product id.
  final String productId;

  /// The tester access token.
  final String testerToken;

  /// An optional readable product name.
  final String? productName;

  @override
  bool operator ==(Object other) =>
      other is FeedbackRelaySettings &&
      other.backendUrl == backendUrl &&
      other.productId == productId &&
      other.testerToken == testerToken &&
      other.productName == productName;

  @override
  int get hashCode => Object.hash(backendUrl, productId, testerToken, productName);
}
