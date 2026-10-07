/// A small feedback drawer that stays above the host app.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:feedback/feedback.dart';
import 'package:flutter/material.dart';

import '../relay_client.dart';
import 'feedback_entry.dart';
import 'feedback_host.dart';

/// Opens the shared drawer or one of its two host actions.
class FeedbackDrawerOverlay extends StatefulWidget {
  /// Creates the overlay around the full-size host navigator.
  const FeedbackDrawerOverlay({
    required this.navigatorKey,
    required this.child,
    required this.onOpenSavedReports,
    this.onResult,
    this.feedbackLabel = 'Feedback',
    this.sendLabel = 'Send feedback',
    this.savedLabel = 'Saved reports',
    this.closeLabel = 'Close feedback',
    super.key,
  });

  /// The root navigator key for the host app.
  final GlobalKey<NavigatorState> navigatorKey;

  /// The host navigator, kept at its full size while this overlay is closed.
  final Widget child;

  /// Opens the host's saved report page after the drawer has closed.
  final Future<void> Function() onOpenSavedReports;

  /// Receives a send result from the existing feedback flow.
  final void Function(DeliveryResult result)? onResult;

  /// The accessible label on the edge tab and drawer title.
  final String feedbackLabel;

  /// The drawer action label for a new report.
  final String sendLabel;

  /// The drawer action label for saved reports.
  final String savedLabel;

  /// The drawer action label for closing the panel.
  final String closeLabel;

  @override
  State<FeedbackDrawerOverlay> createState() => _FeedbackDrawerOverlayState();
}

class _FeedbackDrawerOverlayState extends State<FeedbackDrawerOverlay> {
  bool _active = false;
  PopupRoute<_FeedbackDrawerAction>? _drawerRoute;
  FeedbackController? _activeController;

  @override
  void dispose() {
    _activeController?.hide();
    final route = _drawerRoute;
    final navigator = widget.navigatorKey.currentState;
    if (route != null && route.isActive && navigator != null) {
      navigator.removeRoute(route);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final flow = FeedbackScope.maybeOf(context);
    if (flow == null || !flow.spec.isEnabled) return widget.child;

    final safe = MediaQuery.paddingOf(context);
    return Stack(
      fit: StackFit.passthrough,
      children: <Widget>[
        widget.child,
        if (!_active)
          Positioned(
            right: safe.right,
            top: safe.top,
            bottom: safe.bottom,
            child: Align(
              alignment: Alignment.centerRight,
              child: _FeedbackDrawerTab(
                label: widget.feedbackLabel,
                onTap: () {
                  unawaited(
                    _openDrawer()
                        .catchError((Object error, StackTrace stackTrace) {
                      FlutterError.reportError(
                        FlutterErrorDetails(
                          exception: error,
                          stack: stackTrace,
                          library: 'feedback_relay',
                        ),
                      );
                    }),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _openDrawer() async {
    if (_active) return;
    final navigator = widget.navigatorKey.currentState;
    if (navigator == null || !navigator.mounted) return;

    setState(() => _active = true);
    final route = _FeedbackDrawerRoute(
      feedbackLabel: widget.feedbackLabel,
      sendLabel: widget.sendLabel,
      savedLabel: widget.savedLabel,
      closeLabel: widget.closeLabel,
    );
    _drawerRoute = route;

    try {
      final action = await navigator.push(route);
      await route.completed;
      if (action != null && action != _FeedbackDrawerAction.close) {
        await _runHostAction(action);
      }
    } finally {
      _drawerRoute = null;
      _activeController = null;
      if (mounted) setState(() => _active = false);
    }
  }

  Future<void> _runHostAction(_FeedbackDrawerAction action) async {
    if (!mounted) return;
    // Read the host navigator after the drawer route has fully left.
    final hostNavigator = widget.navigatorKey.currentState;
    if (hostNavigator == null || !hostNavigator.mounted) return;
    final hostContext = hostNavigator.overlay?.context;
    if (hostContext == null) return;
    if (action == _FeedbackDrawerAction.savedReports) {
      await widget.onOpenSavedReports();
      return;
    }

    _activeController = BetterFeedback.of(hostContext);
    await openFeedbackCapture(hostContext, onResult: widget.onResult);
  }
}

class _FeedbackDrawerTab extends StatelessWidget {
  const _FeedbackDrawerTab({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: Tooltip(
          message: label,
          child: SizedBox(
            width: 56,
            height: 96,
            child: Material(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(16),
              ),
              elevation: 4,
              child: InkWell(
                key: const Key('feedback_drawer_tab'),
                onTap: onTap,
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Icon(Icons.feedback_outlined,
                          color:
                              Theme.of(context).colorScheme.onPrimaryContainer),
                      const SizedBox(height: 4),
                      Flexible(
                        child: RotatedBox(
                          quarterTurns: 3,
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

enum _FeedbackDrawerAction { close, send, savedReports }

class _FeedbackDrawerRoute extends PopupRoute<_FeedbackDrawerAction> {
  _FeedbackDrawerRoute({
    required this.feedbackLabel,
    required this.sendLabel,
    required this.savedLabel,
    required this.closeLabel,
  });

  final String feedbackLabel;
  final String sendLabel;
  final String savedLabel;
  final String closeLabel;

  @override
  Color get barrierColor => Colors.black54;

  @override
  String get barrierLabel => closeLabel;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 220);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) =>
      _FeedbackDrawerPanel(
        feedbackLabel: feedbackLabel,
        sendLabel: sendLabel,
        savedLabel: savedLabel,
        closeLabel: closeLabel,
        onAction: (action) => navigator?.pop(action),
      );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      SlideTransition(
        position: animation.drive(
          Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).chain(
            CurveTween(curve: Curves.easeOutCubic),
          ),
        ),
        child: child,
      );
}

class _FeedbackDrawerPanel extends StatelessWidget {
  const _FeedbackDrawerPanel({
    required this.feedbackLabel,
    required this.sendLabel,
    required this.savedLabel,
    required this.closeLabel,
    required this.onAction,
  });

  final String feedbackLabel;
  final String sendLabel;
  final String savedLabel;
  final String closeLabel;
  final ValueChanged<_FeedbackDrawerAction> onAction;

  @override
  Widget build(BuildContext context) {
    final width = math.min(320.0, MediaQuery.sizeOf(context).width);
    final theme = Theme.of(context);
    return SafeArea(
      child: Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: width,
          height: double.infinity,
          child: Material(
            key: const Key('feedback_drawer_panel'),
            color: theme.colorScheme.surface,
            elevation: 16,
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Column(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        feedbackLabel,
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      children: <Widget>[
                        ListTile(
                          key: const Key('feedback_drawer_send'),
                          leading: const Icon(Icons.send_outlined),
                          title: Text(sendLabel),
                          onTap: () => onAction(_FeedbackDrawerAction.send),
                        ),
                        ListTile(
                          key: const Key('feedback_drawer_saved'),
                          leading: const Icon(Icons.folder_outlined),
                          title: Text(savedLabel),
                          onTap: () =>
                              onAction(_FeedbackDrawerAction.savedReports),
                        ),
                        ListTile(
                          key: const Key('feedback_drawer_close'),
                          leading: const Icon(Icons.close),
                          title: Text(closeLabel),
                          onTap: () => onAction(_FeedbackDrawerAction.close),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
