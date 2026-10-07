/// The capture, preview, draft, and send flow for the shared feedback tool.
///
/// One flow belongs to one host app. It owns the drafts, the honest delivery
/// states, and the safe retry route.
library;

import 'package:flutter/foundation.dart';

import 'build_spec.dart';
import 'draft_store.dart';
import 'relay_client.dart';
import 'report.dart';

/// The facts that only the host app can supply.
///
/// The host reads the app version, the build number, the current screen, the
/// source revision, and the small set of device facts. A value that the host
/// cannot read stays [kUnknownFact]. The host must not invent a source
/// revision from the latest Git branch.
abstract interface class FeedbackContextSource {
  /// The app version recorded in the build settings, for example `1.2.4`.
  String get appVersion;

  /// The build number recorded in the build settings, for example `77`.
  String get buildNumber;

  /// The name of the screen that is open now.
  String get screen;

  /// The source revision recorded in the build settings.
  String get sourceRevision;

  /// The small named set of device facts.
  DeviceFacts get device;
}

/// A context source that reports every fact as unknown.
///
/// Use it in a small host, in a test, or before the host can read the facts.
class UnknownContextSource implements FeedbackContextSource {
  /// Creates the unknown context source.
  const UnknownContextSource();

  @override
  String get appVersion => kUnknownFact;

  @override
  String get buildNumber => kUnknownFact;

  @override
  String get screen => kUnknownFact;

  @override
  String get sourceRevision => kUnknownFact;

  @override
  DeviceFacts get device => DeviceFacts.unknown;
}

/// One flow for one host app: drafts, honest states, and safe sends.
class FeedbackFlow extends ChangeNotifier {
  /// Creates a flow.
  ///
  /// [spec] is the shared build control. [store] keeps the drafts. The host
  /// supplies [contextSource] for the facts that the package cannot know.
  FeedbackFlow({
    required this.spec,
    required this.store,
    this.contextSource = const UnknownContextSource(),
    RelayClient? client,
  }) : _client = client ?? RelayClient(spec: spec);

  /// The build boundary. This value also gates sending.
  final FeedbackBuildSpec spec;

  /// The draft store that the host supplied.
  final DraftStore store;

  /// The host facts for every new report.
  final FeedbackContextSource contextSource;

  final RelayClient _client;
  final Map<String, ReportDraft> _drafts = <String, ReportDraft>{};
  final Map<String, Future<DeliveryResult>> _inFlight =
      <String, Future<DeliveryResult>>{};
  bool _recovered = false;

  /// The known drafts, newest first.
  List<ReportDraft> get drafts {
    final list = _drafts.values.toList()
      ..sort((a, b) =>
          b.report.context.capturedAt.compareTo(a.report.context.capturedAt));
    return list;
  }

  /// True when a send for [id] is running now.
  bool isSending(String id) => _inFlight.containsKey(id);

  /// Builds a report from tester text and the host facts.
  FeedbackReport buildReport({
    required String text,
    String? expected,
    String? steps,
    Uint8List? screenshot,
    DateTime? capturedAt,
  }) {
    final settings = spec.settings;
    if (settings == null) {
      throw StateError(
          'Feedback is not enabled in this build, so it cannot build a report.');
    }
    return FeedbackReport.create(
      text: text,
      expected: expected,
      steps: steps,
      screenshot: screenshot,
      productId: settings.productId,
      productName: settings.productName,
      appVersion: contextSource.appVersion,
      buildNumber: contextSource.buildNumber,
      buildMode: spec.mode,
      screen: contextSource.screen,
      sourceRevision: contextSource.sourceRevision,
      device: contextSource.device,
      capturedAt: capturedAt,
    );
  }

  /// Loads the saved drafts and resolves any interrupted send.
  ///
  /// Call this once when the host starts, so a report from an earlier run is
  /// visible again.
  Future<void> recover() async {
    if (_recovered) {
      return;
    }
    _recovered = true;
    final saved = await store.list();
    for (final draft in saved) {
      _drafts[draft.id] = draft;
    }
    notifyListeners();
    for (final draft
        in saved.where((d) => d.state == ReportDeliveryState.waiting)) {
      await check(draft.id);
    }
  }

  /// Saves one report as a draft without sending it.
  Future<ReportDraft> keep(FeedbackReport report) async {
    final draft = ReportDraft(report: report, state: ReportDeliveryState.saved);
    _drafts[report.id] = draft;
    await store.save(draft);
    notifyListeners();
    return draft;
  }

  /// Sends one report and saves its honest state.
  ///
  /// The draft is saved before the send, so an interrupted send keeps the
  /// tester's note. A repeated call for a report that is sending now returns
  /// the same result and sends one request.
  Future<DeliveryResult> send(FeedbackReport report) {
    final running = _inFlight[report.id];
    if (running != null) {
      return running;
    }
    final future = _send(report);
    _inFlight[report.id] = future;
    return future.whenComplete(() => _inFlight.remove(report.id));
  }

  Future<DeliveryResult> _send(FeedbackReport report) async {
    await _record(
        ReportDraft(report: report, state: ReportDeliveryState.waiting));
    final result = await _client.submit(report);
    await _apply(report, result);
    return result;
  }

  /// Retries one saved draft with the same report id.
  ///
  /// A draft whose last result was unknown is checked first. A new issue is
  /// created only when the relay proves that it holds no record.
  Future<DeliveryResult> retry(String id) async {
    final draft = _drafts[id];
    if (draft == null) {
      return const DeliveryFailed('The draft is not saved.', retryable: false);
    }
    if (isSending(id)) {
      return _inFlight[id]!;
    }
    if (draft.state == ReportDeliveryState.needsCheck) {
      final checked = await check(id);
      if (checked is! DeliveryNotRecorded) {
        return checked;
      }
    }
    return send(draft.report);
  }

  /// Reads the delivery state of one report from the relay.
  Future<DeliveryResult> check(String id) async {
    final draft = _drafts[id];
    if (draft == null) {
      return const DeliveryFailed('The draft is not saved.', retryable: false);
    }
    final result = await _client.check(id);
    await _apply(draft.report, result);
    return result;
  }

  /// Removes one saved draft and its image.
  Future<void> remove(String id) async {
    _drafts.remove(id);
    await store.remove(id);
    notifyListeners();
  }

  Future<void> _apply(FeedbackReport report, DeliveryResult result) async {
    switch (result) {
      case DeliveryConfirmed(:final issueUrl, :final note):
        await _record(ReportDraft(
            report: report,
            state: ReportDeliveryState.sent,
            issueUrl: issueUrl,
            note: note));
      case DeliveryUnknown(:final reason):
        await _record(ReportDraft(
            report: report,
            state: ReportDeliveryState.needsCheck,
            note: reason));
      case DeliveryNotRecorded(:final reason):
        await _record(ReportDraft(
            report: report, state: ReportDeliveryState.waiting, note: reason));
      case DeliveryFailed(:final reason, :final retryable):
        await _record(
          ReportDraft(
            report: report,
            state: retryable
                ? ReportDeliveryState.waiting
                : ReportDeliveryState.failed,
            note: reason,
          ),
        );
    }
  }

  Future<void> _record(ReportDraft draft) async {
    _drafts[draft.id] = draft;
    await store.save(draft);
    notifyListeners();
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }
}
