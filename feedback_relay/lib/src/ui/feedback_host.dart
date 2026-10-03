/// The host wrapper for the shared feedback tool.
///
/// One [FeedbackHost] above the app supplies the flow to every entry control
/// below it. In a production build the host returns the child unchanged, so
/// the wrapper, the controls, and the sending path all stay out.
library;

import 'package:feedback/feedback.dart';
import 'package:flutter/material.dart';

import '../build_spec.dart';
import '../draft_store.dart';
import '../feedback_flow.dart';
import '../relay_client.dart';
import 'feedback_form.dart';

/// Gives the [FeedbackFlow] to the widgets below it.
class FeedbackScope extends InheritedNotifier<FeedbackFlow> {
  /// Creates a scope around one flow.
  const FeedbackScope({required super.notifier, required super.child, super.key});

  /// The flow of the nearest host, or null when no host is present.
  static FeedbackFlow? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<FeedbackScope>()?.notifier;

  /// The flow of the nearest host.
  ///
  /// Throws when no [FeedbackHost] is above this context.
  static FeedbackFlow of(BuildContext context) {
    final flow = maybeOf(context);
    if (flow == null) {
      throw FlutterError('No FeedbackHost is above this widget. Wrap the app once with FeedbackHost.');
    }
    return flow;
  }
}

/// Wraps the app for a development or test build.
///
/// The same [spec] value gates this wrapper, the entry controls, and the relay
/// client. A production spec returns [child] unchanged.
class FeedbackHost extends StatefulWidget {
  /// Creates a host wrapper.
  ///
  /// [store] is required, so a host cannot lose a draft by accident. Use a
  /// `FileDraftStore` on a private app directory, or `MemoryDraftStore` when
  /// the host accepts that drafts do not survive a restart.
  const FeedbackHost({
    required this.spec,
    required this.store,
    required this.child,
    this.contextSource = const UnknownContextSource(),
    this.client,
    super.key,
    this.feedbackBuilder,
    this.themeMode,
    this.theme,
    this.darkTheme,
    this.mode = FeedbackMode.draw,
    this.pixelRatio = 3.0,
  });

  /// The build boundary and relay settings.
  final FeedbackBuildSpec spec;

  /// The app below the wrapper.
  final Widget child;

  /// The draft store. It holds the drafts in private storage.
  final DraftStore store;

  /// The host facts for each report.
  final FeedbackContextSource contextSource;

  /// An optional relay client, used in tests to keep the network out.
  final RelayClient? client;

  /// Forwarded to [BetterFeedback]. See its documentation.
  final FeedbackBuilder? feedbackBuilder;

  /// Forwarded to [BetterFeedback]. See its documentation.
  final ThemeMode? themeMode;

  /// Forwarded to [BetterFeedback]. See its documentation.
  final FeedbackThemeData? theme;

  /// Forwarded to [BetterFeedback]. See its documentation.
  final FeedbackThemeData? darkTheme;

  /// Forwarded to [BetterFeedback]. See its documentation.
  final FeedbackMode mode;

  /// Forwarded to [BetterFeedback]. See its documentation.
  final double pixelRatio;

  @override
  State<FeedbackHost> createState() => _FeedbackHostState();
}

class _FeedbackHostState extends State<FeedbackHost> {
  late FeedbackFlow _flow;
  bool _ownsFlow = false;

  @override
  void initState() {
    super.initState();
    _flow = FeedbackFlow(
      spec: widget.spec,
      store: widget.store,
      contextSource: widget.contextSource,
      client: widget.client,
    );
    _ownsFlow = true;
    _flow.recover();
  }

  @override
  void dispose() {
    if (_ownsFlow) {
      _flow.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.spec.isEnabled) {
      return widget.child;
    }
    return BetterFeedback(
      feedbackBuilder: widget.feedbackBuilder ?? relayFeedbackBuilder,
      themeMode: widget.themeMode,
      theme: widget.theme,
      darkTheme: widget.darkTheme,
      mode: widget.mode,
      pixelRatio: widget.pixelRatio,
      child: FeedbackScope(notifier: _flow, child: widget.child),
    );
  }
}
