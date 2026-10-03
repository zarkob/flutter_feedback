/// Saved drafts for the shared feedback tool.
///
/// A draft holds the report text, the optional image, the stable report id,
/// and the known build context. A draft survives a failed send and an app
/// restart. This file has no Flutter imports and no file system access.
library;

import 'dart:convert';

import 'report.dart';

/// The delivery state of one report.
///
/// The state tells the truth about delivery. `sent` is used only after the
/// destination confirms the report.
enum ReportDeliveryState {
  /// The report is saved and not sent.
  saved,

  /// The report is waiting for a send or a retry.
  waiting,

  /// The destination confirmed delivery.
  sent,

  /// The send result is unknown. The tester must check delivery.
  needsCheck,

  /// The destination rejected the report, or the settings are wrong.
  failed,
}

/// One saved report with its local delivery state.
class ReportDraft {
  /// Creates a draft around one report.
  const ReportDraft({
    required this.report,
    this.state = ReportDeliveryState.saved,
    this.issueUrl,
    this.note,
  });

  /// The report. Its id stays the same for every retry.
  final FeedbackReport report;

  /// The local delivery state.
  final ReportDeliveryState state;

  /// The issue link, present only after a confirmed delivery.
  final String? issueUrl;

  /// A short honest note, for example a failure reason.
  final String? note;

  /// The report id.
  String get id => report.id;

  /// Returns a copy with a changed state. The report id never changes.
  ReportDraft copyWith({
    FeedbackReport? report,
    ReportDeliveryState? state,
    String? issueUrl,
    String? note,
    bool clearIssueUrl = false,
    bool clearNote = false,
  }) => ReportDraft(
    report: report ?? this.report,
    state: state ?? this.state,
    issueUrl: clearIssueUrl ? null : (issueUrl ?? this.issueUrl),
    note: clearNote ? null : (note ?? this.note),
  );

  /// The saved form of the draft. It holds the report and the local state.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'report': report.toJson(),
    'state': state.name,
    if (issueUrl != null) 'issue_url': issueUrl,
    if (note != null) 'note': note,
  };

  /// Reads a draft from its saved form.
  factory ReportDraft.fromJson(Map<String, dynamic> json) {
    final report = json['report'];
    return ReportDraft(
      report: FeedbackReport.fromJson(report is Map<String, dynamic> ? report : const <String, dynamic>{}),
      state: _state(json['state']),
      issueUrl: json['issue_url'] is String ? json['issue_url'] as String : null,
      note: json['note'] is String ? json['note'] as String : null,
    );
  }

  /// The draft as JSON text.
  String encode() => jsonEncode(toJson());

  /// Reads a draft from JSON text. Returns null when the text is broken.
  static ReportDraft? decode(String text) {
    try {
      final value = jsonDecode(text);
      if (value is Map<String, dynamic>) {
        return ReportDraft.fromJson(value);
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  @override
  String toString() => 'ReportDraft($id, ${state.name})';
}

/// Keeps drafts in private storage.
///
/// The host supplies the storage. The package writes only report data and the
/// optional image. No account data and no device serial is stored.
abstract interface class DraftStore {
  /// Saves or replaces one draft.
  Future<void> save(ReportDraft draft);

  /// Loads one draft, or null when the id is not stored.
  Future<ReportDraft?> load(String id);

  /// Lists the stored drafts, newest first.
  Future<List<ReportDraft>> list();

  /// Removes one draft and its image. Does nothing when it is absent.
  Future<void> remove(String id);
}

/// A draft store that keeps drafts in memory.
///
/// Use it in tests and in a host that has no private storage yet. It does not
/// survive an app restart.
class MemoryDraftStore implements DraftStore {
  final Map<String, ReportDraft> _drafts = <String, ReportDraft>{};

  @override
  Future<void> save(ReportDraft draft) async {
    _drafts[draft.id] = draft;
  }

  @override
  Future<ReportDraft?> load(String id) async => _drafts[id];

  @override
  Future<List<ReportDraft>> list() async {
    final drafts = _drafts.values.toList()
      ..sort((a, b) => b.report.context.capturedAt.compareTo(a.report.context.capturedAt));
    return drafts;
  }

  @override
  Future<void> remove(String id) async {
    _drafts.remove(id);
  }
}

ReportDeliveryState _state(Object? value) {
  for (final state in ReportDeliveryState.values) {
    if (state.name == value) {
      return state;
    }
  }
  return ReportDeliveryState.saved;
}
