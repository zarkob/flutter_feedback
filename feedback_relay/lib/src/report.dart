/// Feedback report model for the shared feedback tool.
///
/// This file has no Flutter imports. The report format is a plain JSON object.
/// Other app types can build and read the same format without Flutter.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// The value used for a fact that is not known.
///
/// Unknown facts travel to the destination as this exact text. The issue body
/// then shows an honest value instead of a made-up one.
const String kUnknownFact = 'Unknown';

/// The version of the report JSON format.
const String kReportSchema = 'avensora-report/1';

/// The largest report text length, in characters. The server checks the same
/// limit, so a long report fails before any network call.
const int kMaxReportTextLength = 10000;

/// The largest single image size, in bytes. The server checks the same limit.
const int kMaxScreenshotBytes = 4 * 1024 * 1024;

/// The small, named set of device facts that a report may carry.
///
/// No account data, no device serial, no log, and no private setting belongs
/// in this set. A fact that the host cannot read stays [kUnknownFact].
class DeviceFacts {
  /// Creates device facts. Each value defaults to [kUnknownFact].
  const DeviceFacts({
    this.model = kUnknownFact,
    this.platform = kUnknownFact,
    this.osVersion = kUnknownFact,
    this.locale = kUnknownFact,
  });

  /// The device model, for example `Pixel 7`. `Unknown` when not readable.
  final String model;

  /// The platform name, for example `android` or `linux`.
  final String platform;

  /// The platform version, for example `Android 15`.
  final String osVersion;

  /// The locale of the app at capture time, for example `en_US`.
  final String locale;

  /// All facts unknown. Use this when the host reads no device facts.
  static const DeviceFacts unknown = DeviceFacts();

  /// The four named facts as a JSON object.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'model': model,
    'platform': platform,
    'os_version': osVersion,
    'locale': locale,
  };

  /// Reads device facts from a JSON object. Missing facts stay `Unknown`.
  factory DeviceFacts.fromJson(Map<String, dynamic> json) => DeviceFacts(
    model: _text(json['model']),
    platform: _text(json['platform']),
    osVersion: _text(json['os_version']),
    locale: _text(json['locale']),
  );

  @override
  bool operator ==(Object other) =>
      other is DeviceFacts &&
      other.model == model &&
      other.platform == platform &&
      other.osVersion == osVersion &&
      other.locale == locale;

  @override
  int get hashCode => Object.hash(model, platform, osVersion, locale);

  @override
  String toString() =>
      'DeviceFacts(model: $model, platform: $platform, '
      'osVersion: $osVersion, locale: $locale)';
}

/// The build and screen facts that belong to one report.
///
/// The host supplies every fact. The package never invents an app version, a
/// screen name, or a source revision. A fact that the host cannot read stays
/// [kUnknownFact].
class ReportContext {
  /// Creates a report context.
  const ReportContext({
    required this.productId,
    required this.capturedAt,
    this.productName,
    this.appVersion = kUnknownFact,
    this.buildNumber = kUnknownFact,
    this.buildMode = kUnknownFact,
    this.screen = kUnknownFact,
    this.sourceRevision = kUnknownFact,
    this.device = DeviceFacts.unknown,
  });

  /// The public product id from the build settings.
  final String productId;

  /// The time of capture, in UTC.
  final DateTime capturedAt;

  /// An optional readable product name.
  final String? productName;

  /// The app version from the actual build settings, for example `1.2.4`.
  final String appVersion;

  /// The build number from the actual build settings, for example `77`.
  final String buildNumber;

  /// The build mode, for example `test` or `development`.
  final String buildMode;

  /// The name of the screen that was open at capture time.
  final String screen;

  /// The source revision recorded in the build settings.
  ///
  /// The host must read this from the build. It must stay `Unknown` when the
  /// build has no recorded revision.
  final String sourceRevision;

  /// The small named set of device facts.
  final DeviceFacts device;

  /// The context facts as a JSON object.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'product_id': productId,
    if (productName != null) 'product_name': productName,
    'app_version': appVersion,
    'build_number': buildNumber,
    'build_mode': buildMode,
    'screen': screen,
    'source_revision': sourceRevision,
    'captured_at': capturedAt.toUtc().toIso8601String(),
    'device': device.toJson(),
  };

  /// Reads a report context from a JSON object. Missing facts stay `Unknown`.
  factory ReportContext.fromJson(Map<String, dynamic> json) => ReportContext(
    productId: _text(json['product_id']),
    capturedAt: _time(json['captured_at']),
    productName: json['product_name'] is String && (json['product_name'] as String).isNotEmpty ? json['product_name'] as String : null,
    appVersion: _text(json['app_version']),
    buildNumber: _text(json['build_number']),
    buildMode: _text(json['build_mode']),
    screen: _text(json['screen']),
    sourceRevision: _text(json['source_revision']),
    device: json['device'] is Map<String, dynamic> ? DeviceFacts.fromJson(json['device'] as Map<String, dynamic>) : DeviceFacts.unknown,
  );

  @override
  bool operator ==(Object other) =>
      other is ReportContext &&
      other.productId == productId &&
      other.capturedAt.toUtc() == capturedAt.toUtc() &&
      other.productName == productName &&
      other.appVersion == appVersion &&
      other.buildNumber == buildNumber &&
      other.buildMode == buildMode &&
      other.screen == screen &&
      other.sourceRevision == sourceRevision &&
      other.device == device;

  @override
  int get hashCode => Object.hash(productId, capturedAt, productName, appVersion, buildNumber, buildMode, screen, sourceRevision, device);
}

/// One tester observation, ready to send.
///
/// The [id] is stable. A retry of the same report keeps the same [id], so the
/// destination can recognize the repeat.
class FeedbackReport {
  /// Creates a report. Prefer [FeedbackReport.create], which makes the id.
  const FeedbackReport({
    required this.id,
    required this.text,
    required this.context,
    this.expected,
    this.steps,
    this.screenshot,
  });

  /// Creates a report with a new stable id and the current capture time.
  ///
  /// [screen] and the other host facts come from the host context source.
  factory FeedbackReport.create({
    required String text,
    required String productId,
    String? expected,
    String? steps,
    Uint8List? screenshot,
    String? productName,
    String appVersion = kUnknownFact,
    String buildNumber = kUnknownFact,
    String buildMode = kUnknownFact,
    String screen = kUnknownFact,
    String sourceRevision = kUnknownFact,
    DeviceFacts device = DeviceFacts.unknown,
    DateTime? capturedAt,
    String? id,
  }) {
    return FeedbackReport(
      id: id ?? newReportId(),
      text: text,
      expected: _clean(expected),
      steps: _clean(steps),
      screenshot: screenshot,
      context: ReportContext(
        productId: productId,
        productName: productName,
        capturedAt: (capturedAt ?? DateTime.now()).toUtc(),
        appVersion: appVersion,
        buildNumber: buildNumber,
        buildMode: buildMode,
        screen: screen,
        sourceRevision: sourceRevision,
        device: device,
      ),
    );
  }

  /// The stable report id. It does not change during a retry.
  final String id;

  /// What the tester saw. This text is required.
  final String text;

  /// What the tester expected to happen. Optional.
  final String? expected;

  /// The steps that led to the observation. Optional.
  final String? steps;

  /// The optional annotated screenshot as PNG bytes.
  final Uint8List? screenshot;

  /// The build, screen, time, and device facts for this report.
  final ReportContext context;

  /// True when the report carries an image.
  bool get hasScreenshot => screenshot != null && screenshot!.isNotEmpty;

  /// The report as the plain JSON object that the server accepts.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'schema': kReportSchema,
    'report_id': id,
    'created_at': context.capturedAt.toUtc().toIso8601String(),
    'text': text,
    'expected': expected,
    'steps': steps,
    'screenshot_b64': hasScreenshot ? base64Encode(screenshot!) : null,
    'context': context.toJson(),
  };

  /// Reads a report from a JSON object.
  factory FeedbackReport.fromJson(Map<String, dynamic> json) {
    final screenshot = json['screenshot_b64'];
    final context = json['context'];
    return FeedbackReport(
      id: _text(json['report_id']),
      text: _text(json['text']),
      expected: _clean(json['expected'] as String?),
      steps: _clean(json['steps'] as String?),
      screenshot: screenshot is String && screenshot.isNotEmpty ? base64Decode(screenshot) : null,
      context: context is Map<String, dynamic> ? ReportContext.fromJson(context) : ReportContext(productId: kUnknownFact, capturedAt: _time(json['created_at'])),
    );
  }

  /// Returns a copy with changed text fields. The id never changes here.
  FeedbackReport copyWith({
    String? text,
    String? expected,
    String? steps,
    Uint8List? screenshot,
  }) => FeedbackReport(
    id: id,
    text: text ?? this.text,
    expected: expected ?? this.expected,
    steps: steps ?? this.steps,
    screenshot: screenshot ?? this.screenshot,
    context: context,
  );

  /// The size of the encoded image, in bytes. Zero when there is no image.
  int get screenshotBytes => screenshot?.length ?? 0;

  @override
  String toString() => 'FeedbackReport($id, ${text.length} chars, image: $hasScreenshot)';
}

/// Makes a new stable report id in the UUID version 4 shape.
///
/// The package makes the id on the device. A retry keeps the same value.
String newReportId([Random? random]) {
  final rng = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}

String _text(Object? value) {
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  return kUnknownFact;
}

String? _clean(String? value) {
  if (value == null) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

DateTime _time(Object? value) {
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) {
      return parsed.toUtc();
    }
  }
  return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}
