/// The capture form of the shared feedback tool.
///
/// The form keeps the upstream sheet shape and adds the two optional fields
/// that the report format carries: what the tester expected, and the steps
/// that led to the observation. Both values travel in the upstream `extra`
/// map, so no upstream code changes.
library;

import 'package:feedback/feedback.dart';
import 'package:flutter/material.dart';

/// The key of the expected behavior value in the extra map.
const String kExpectedExtraKey = 'expected';

/// The key of the steps value in the extra map.
const String kStepsExtraKey = 'steps';

/// Builds the capture form that [FeedbackHost] uses by default.
Widget relayFeedbackBuilder(
  BuildContext context,
  OnSubmit onSubmit,
  ScrollController? scrollController,
) => FeedbackForm(onSubmit: onSubmit, scrollController: scrollController);

/// The capture form: what happened, what was expected, and the steps.
class FeedbackForm extends StatefulWidget {
  /// Creates the capture form.
  const FeedbackForm({required this.onSubmit, required this.scrollController, super.key});

  /// Called with the tester's words and the optional extra values.
  final OnSubmit onSubmit;

  /// The scroll controller of a draggable sheet, when the theme allows dragging.
  final ScrollController? scrollController;

  @override
  State<FeedbackForm> createState() => _FeedbackFormState();
}

class _FeedbackFormState extends State<FeedbackForm> {
  final TextEditingController _what = TextEditingController();
  final TextEditingController _expected = TextEditingController();
  final TextEditingController _steps = TextEditingController();
  bool _showMissingText = false;

  @override
  void dispose() {
    _what.dispose();
    _expected.dispose();
    _steps.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final what = _what.text.trim();
    if (what.isEmpty) {
      setState(() => _showMissingText = true);
      return;
    }
    await widget.onSubmit(
      what,
      extras: <String, dynamic>{
        kExpectedExtraKey: _expected.text.trim(),
        kStepsExtraKey: _steps.text.trim(),
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The upstream strings are used when the host provides the feedback
    // localizations. The form also works on its own.
    final l10n = Localizations.of<FeedbackLocalizations>(context, FeedbackLocalizations);
    return Column(
      children: <Widget>[
        Expanded(
          child: Stack(
            children: <Widget>[
              SingleChildScrollView(
                controller: widget.scrollController,
                padding: EdgeInsets.fromLTRB(16, widget.scrollController != null ? 20 : 16, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      l10n?.feedbackDescriptionText ?? 'Tell us what happened.',
                      maxLines: 2,
                      style: theme.textTheme.bodySmall,
                    ),
                    TextField(
                      key: const Key('text_input_field'),
                      minLines: 2,
                      maxLines: 3,
                      controller: _what,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'What happened'),
                    ),
                    if (_showMissingText)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text('Write what happened first.', style: TextStyle(color: Colors.red)),
                      ),
                    const SizedBox(height: 8),
                    TextField(
                      key: const Key('expected_input_field'),
                      minLines: 1,
                      maxLines: 2,
                      controller: _expected,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Expected (optional)'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      key: const Key('steps_input_field'),
                      minLines: 1,
                      maxLines: 3,
                      controller: _steps,
                      decoration: const InputDecoration(labelText: 'Steps (optional)'),
                    ),
                  ],
                ),
              ),
              if (widget.scrollController != null) const FeedbackSheetDragHandle(),
            ],
          ),
        ),
        TextButton(
          key: const Key('submit_feedback_button'),
          onPressed: _submit,
          child: Text(l10n?.submitButtonText ?? 'Send', style: TextStyle(color: theme.colorScheme.primary)),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
