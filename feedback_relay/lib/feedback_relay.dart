/// The shared feedback tool for Avensora test builds.
///
/// One package gives a product a quick feedback entry, a preview step, saved
/// drafts, safe retries, and honest delivery states. The report format is a
/// plain JSON object, so a future app type can produce the same format without
/// Flutter.
///
/// The package never holds a GitHub token, a storage key, or a private key.
/// The app ships only a relay URL, a public product id, and a tester token.
/// The relay holds the destination secrets and checks tester access.
///
/// The build boundary is one value. It gates the wrapper, the entry controls,
/// and the sending path. A production build with feedback settings is rejected
/// at startup.
///
/// ```dart
/// final spec = FeedbackBuildSpec.fromEnvironment().checked();
/// runApp(
///   FeedbackHost(
///     spec: spec,
///     store: FileDraftStore(privateDir),
///     contextSource: myContextSource,
///     child: MaterialApp(home: HomePage()),
///   ),
/// );
/// ```
library;

export 'package:feedback/feedback.dart';

export 'src/build_spec.dart';
export 'src/draft_store.dart';
export 'src/feedback_flow.dart';
export 'src/relay_client.dart';
export 'src/report.dart';
export 'src/ui/feedback_entry.dart';
export 'src/ui/feedback_form.dart';
export 'src/ui/feedback_host.dart';
export 'src/ui/feedback_preview.dart';
