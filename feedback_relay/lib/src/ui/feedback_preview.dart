/// The preview step of the shared feedback tool.
///
/// The tester sees the text and the image before Send. The tester can send,
/// keep the report as a draft, or cancel.
library;

import 'package:flutter/material.dart';

import '../report.dart';

/// What the tester chose in the preview.
enum FeedbackPreviewAction {
  /// Send the report now.
  send,

  /// Keep the report as a draft and send it later.
  keepDraft,

  /// Drop the report.
  cancel,
}

/// Shows the report text, the image, and the known facts before Send.
class FeedbackPreviewSheet extends StatelessWidget {
  /// Creates the preview for one report.
  const FeedbackPreviewSheet({required this.report, super.key});

  /// The report under review.
  final FeedbackReport report;

  /// Opens the preview and returns the tester's choice, or null when it closes.
  static Future<FeedbackPreviewAction?> show(
      BuildContext context, FeedbackReport report) async {
    final navigator = Navigator.of(context);
    final localizations = MaterialLocalizations.of(context);
    final route = ModalBottomSheetRoute<FeedbackPreviewAction>(
      builder: (_) => FeedbackPreviewSheet(report: report),
      capturedThemes:
          InheritedTheme.capture(from: context, to: navigator.context),
      barrierLabel: localizations.scrimLabel,
      barrierOnTapHint:
          localizations.scrimOnTapHint(localizations.bottomSheetLabel),
      modalBarrierColor: Theme.of(context).bottomSheetTheme.modalBarrierColor,
      isScrollControlled: true,
      useSafeArea: true,
    );
    final action = await navigator.push(route);
    await route.completed;
    return action;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final context_ = report.context;
    final facts = <String, String>{
      'Product': context_.productId,
      'App version': context_.appVersion,
      'Build number': context_.buildNumber,
      'Build mode': context_.buildMode,
      'Screen': context_.screen,
      'Captured at': context_.capturedAt.toUtc().toIso8601String(),
      'Source revision': context_.sourceRevision,
      'Device model': context_.device.model,
      'Platform': context_.device.platform,
      'OS version': context_.device.osVersion,
      'Locale': context_.device.locale,
    };

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, controller) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('Review this report', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('Report ID ${report.id}', style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                controller: controller,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _section(context, 'What happened', report.text),
                    if (report.expected != null)
                      _section(context, 'Expected', report.expected!),
                    if (report.steps != null)
                      _section(context, 'Steps', report.steps!),
                    if (report.hasScreenshot) ...<Widget>[
                      Text('Image', style: theme.textTheme.labelLarge),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(
                          report.screenshot!,
                          height: 180,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stack) =>
                              const Text('The image cannot be shown.'),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Text('Build and device facts',
                        style: theme.textTheme.labelLarge),
                    const SizedBox(height: 4),
                    for (final entry in facts.entries)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            SizedBox(
                                width: 120,
                                child: Text(entry.key,
                                    style: theme.textTheme.bodySmall)),
                            Expanded(
                                child: Text(entry.value,
                                    style: theme.textTheme.bodySmall)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const Key('feedback_preview_send'),
              onPressed: () =>
                  Navigator.of(context).pop(FeedbackPreviewAction.send),
              icon: const Icon(Icons.send_outlined),
              label: const Text('Send'),
            ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              key: const Key('feedback_preview_keep'),
              onPressed: () =>
                  Navigator.of(context).pop(FeedbackPreviewAction.keepDraft),
              icon: const Icon(Icons.save_outlined),
              label: const Text('Keep as draft'),
            ),
            const SizedBox(height: 6),
            TextButton(
              key: const Key('feedback_preview_cancel'),
              onPressed: () =>
                  Navigator.of(context).pop(FeedbackPreviewAction.cancel),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String title, String body) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          Text(body, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
