/// The Flutter-free part of the shared feedback tool.
///
/// Use this library in a command line check, in a server side tool, or in a
/// future app type that is not Flutter. It holds the report format, the build
/// boundary, the draft model, and the relay client. It holds no widget.
///
/// The file store is separate, because it needs a file system:
/// `package:feedback_relay/file_draft_store.dart`.
library;

export 'src/build_spec.dart';
export 'src/draft_store.dart';
export 'src/relay_client.dart';
export 'src/report.dart';
