/// A file based draft store for hosts with private app storage.
///
/// Import this library only in an app that runs on a platform with a file
/// system. The host passes its own private directory, for example the value
/// from `path_provider`. The store writes one folder per report inside that
/// directory.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:feedback_relay/src/draft_store.dart';

/// Keeps drafts as files in a host supplied private directory.
class FileDraftStore implements DraftStore {
  /// Creates a store under [root].
  ///
  /// [root] must be a private app directory, not a shared or public folder.
  FileDraftStore(this.root);

  /// The private directory that holds the draft folders.
  final Directory root;

  static final RegExp _safeId = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$');

  Directory _folder(String id) {
    if (!_safeId.hasMatch(id)) {
      throw ArgumentError.value(id, 'id', 'Report id is not safe for a file name');
    }
    return Directory('${root.path}${Platform.pathSeparator}$id');
  }

  @override
  Future<void> save(ReportDraft draft) async {
    final folder = _folder(draft.id);
    await folder.create(recursive: true);
    await File('${folder.path}${Platform.pathSeparator}draft.json').writeAsString(draft.encode(), flush: true);
    final image = draft.report.screenshot;
    final imageFile = File('${folder.path}${Platform.pathSeparator}screenshot.png');
    if (image != null && image.isNotEmpty) {
      await imageFile.writeAsBytes(image, flush: true);
    } else if (imageFile.existsSync()) {
      await imageFile.delete();
    }
  }

  @override
  Future<ReportDraft?> load(String id) async {
    final file = File('${_folder(id).path}${Platform.pathSeparator}draft.json');
    if (!file.existsSync()) {
      return null;
    }
    final draft = ReportDraft.decode(await file.readAsString());
    if (draft == null) {
      return null;
    }
    return _withImage(draft);
  }

  @override
  Future<List<ReportDraft>> list() async {
    if (!root.existsSync()) {
      return <ReportDraft>[];
    }
    final drafts = <ReportDraft>[];
    await for (final entry in root.list()) {
      if (entry is! Directory) {
        continue;
      }
      final name = entry.uri.pathSegments.where((part) => part.isNotEmpty).last;
      if (!_safeId.hasMatch(name)) {
        continue;
      }
      final draft = await load(name);
      if (draft != null) {
        drafts.add(draft);
      }
    }
    drafts.sort((a, b) => b.report.context.capturedAt.compareTo(a.report.context.capturedAt));
    return drafts;
  }

  @override
  Future<void> remove(String id) async {
    final folder = _folder(id);
    if (folder.existsSync()) {
      await folder.delete(recursive: true);
    }
  }

  Future<ReportDraft> _withImage(ReportDraft draft) async {
    final imageFile = File('${_folder(draft.id).path}${Platform.pathSeparator}screenshot.png');
    if (!imageFile.existsSync()) {
      return draft;
    }
    final Uint8List bytes = await imageFile.readAsBytes();
    if (bytes.isEmpty) {
      return draft;
    }
    return draft.copyWith(report: draft.report.copyWith(screenshot: bytes));
  }
}

/// The JSON form of a saved draft. Kept for hosts that share the format.
String encodeDraft(ReportDraft draft) => jsonEncode(draft.toJson());
