/// The entry control and the draft list for the shared feedback tool.
///
/// Both widgets stay hidden when the build is closed. One shared build control
/// gates them, the wrapper, and the sending path.
library;

import 'package:feedback/feedback.dart';
import 'package:flutter/material.dart';

import '../draft_store.dart';
import '../feedback_flow.dart';
import '../relay_client.dart';
import 'feedback_form.dart';
import 'feedback_host.dart';
import 'feedback_preview.dart';

/// A short, honest label for one delivery state.
String deliveryStateLabel(ReportDeliveryState state) {
  switch (state) {
    case ReportDeliveryState.saved:
      return 'Saved';
    case ReportDeliveryState.waiting:
      return 'Waiting to send';
    case ReportDeliveryState.sent:
      return 'Sent';
    case ReportDeliveryState.needsCheck:
      return 'Needs a check';
    case ReportDeliveryState.failed:
      return 'Not sent';
  }
}

/// Opens the capture and preview flow for the nearest host.
///
/// The upstream capture and drawing controls stay unchanged. After the tester
/// submits, the preview shows the text and the image before any send.
Future<void> openFeedbackCapture(BuildContext context, {void Function(DeliveryResult result)? onResult}) async {
  final flow = FeedbackScope.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  final controller = BetterFeedback.of(context);
  controller.show((UserFeedback feedback) async {
    // The capture layer closes first. The screenshot and the tester text are
    // already captured, and the preview must be the top surface.
    controller.hide();
    final extra = feedback.extra ?? const <String, dynamic>{};
    final report = flow.buildReport(
      text: feedback.text,
      expected: extra[kExpectedExtraKey] is String ? extra[kExpectedExtraKey] as String : null,
      steps: extra[kStepsExtraKey] is String ? extra[kStepsExtraKey] as String : null,
      screenshot: feedback.screenshot,
    );
    final action = await FeedbackPreviewSheet.show(navigator.context, report);
    switch (action) {
      case FeedbackPreviewAction.send:
        final result = await flow.send(report);
        onResult?.call(result);
      case FeedbackPreviewAction.keepDraft:
        await flow.keep(report);
      case FeedbackPreviewAction.cancel:
      case null:
        break;
    }
  });
}

/// A button that opens the feedback flow.
///
/// The button renders nothing when the nearest host is absent or the build is
/// closed, so a hidden control never leaves a live sending path.
class FeedbackEntryButton extends StatelessWidget {
  /// Creates the entry button.
  const FeedbackEntryButton({
    super.key,
    this.label = 'Send feedback',
    this.icon = Icons.feedback_outlined,
    this.onResult,
  });

  /// The button text.
  final String label;

  /// The button icon.
  final IconData icon;

  /// Called after a send, with the honest result.
  final void Function(DeliveryResult result)? onResult;

  @override
  Widget build(BuildContext context) {
    final flow = FeedbackScope.maybeOf(context);
    if (flow == null || !flow.spec.isEnabled) {
      return const SizedBox.shrink();
    }
    return FilledButton.icon(
      key: const Key('feedback_entry_button'),
      onPressed: () => openFeedbackCapture(context, onResult: onResult),
      icon: Icon(icon),
      label: Text(label),
    );
  }
}

/// Lists the saved drafts with their honest state.
///
/// The tester can check a report, retry a safe send, or remove a draft.
class FeedbackDraftList extends StatelessWidget {
  /// Creates the draft list.
  const FeedbackDraftList({super.key, this.emptyText = 'No saved reports.'});

  /// The text shown when no draft is saved.
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final flow = FeedbackScope.maybeOf(context);
    if (flow == null || !flow.spec.isEnabled) {
      return Text(emptyText, style: Theme.of(context).textTheme.bodyMedium);
    }
    return ListenableBuilder(
      listenable: flow,
      builder: (context, _) {
        final drafts = flow.drafts;
        if (drafts.isEmpty) {
          return Text(emptyText, style: Theme.of(context).textTheme.bodyMedium);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (final draft in drafts) _DraftTile(flow: flow, draft: draft),
          ],
        );
      },
    );
  }
}

class _DraftTile extends StatelessWidget {
  const _DraftTile({required this.flow, required this.draft});

  final FeedbackFlow flow;
  final ReportDraft draft;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final report = draft.report;
    final sending = flow.isSending(draft.id);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '${deliveryStateLabel(draft.state)}${sending ? ' — sending now' : ''}',
              style: theme.textTheme.titleSmall,
              key: Key('draft_state_${draft.id}'),
            ),
            const SizedBox(height: 4),
            Text(report.text, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            Text(
              '${report.context.screen} · ${report.context.capturedAt.toUtc().toIso8601String()} · ${report.id}',
              style: theme.textTheme.bodySmall,
            ),
            if (draft.note != null) ...<Widget>[
              const SizedBox(height: 4),
              Text(draft.note!, style: theme.textTheme.bodySmall),
            ],
            if (draft.issueUrl != null) ...<Widget>[
              const SizedBox(height: 4),
              SelectableText(draft.issueUrl!, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: <Widget>[
                if (draft.state == ReportDeliveryState.needsCheck)
                  OutlinedButton(
                    key: Key('draft_check_${draft.id}'),
                    onPressed: sending ? null : () => flow.check(draft.id),
                    child: const Text('Check delivery'),
                  ),
                if (draft.state != ReportDeliveryState.sent && draft.state != ReportDeliveryState.needsCheck)
                  OutlinedButton(
                    key: Key('draft_retry_${draft.id}'),
                    onPressed: sending ? null : () => flow.retry(draft.id),
                    child: const Text('Send again'),
                  ),
                TextButton(
                  key: Key('draft_remove_${draft.id}'),
                  onPressed: () => flow.remove(draft.id),
                  child: const Text('Remove'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
