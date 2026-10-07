import 'package:feedback_relay/feedback_relay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/relay_fakes.dart';

void main() {
  testWidgets('the capture form keeps an empty report out of the flow',
      (tester) async {
    String? sent;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeedbackForm(
              onSubmit: (text, {extras}) async => sent = text,
              scrollController: null),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('submit_feedback_button')));
    await tester.pump();

    expect(sent, isNull);
    expect(find.text('Write what happened first.'), findsOneWidget);
  });

  testWidgets('the capture form carries what happened, expected, and steps',
      (tester) async {
    String? sentText;
    Map<String, dynamic>? sentExtras;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeedbackForm(
            onSubmit: (String value, {Map<String, dynamic>? extras}) async {
              sentText = value;
              sentExtras = extras;
            },
            scrollController: null,
          ),
        ),
      ),
    );

    await tester.enterText(
        find.byKey(const Key('text_input_field')), 'The list is empty.');
    await tester.enterText(
        find.byKey(const Key('expected_input_field')), 'The saved items stay.');
    await tester.enterText(
        find.byKey(const Key('steps_input_field')), '1. Add one item');
    await tester.tap(find.byKey(const Key('submit_feedback_button')));
    await tester.pump();

    expect(sentText, 'The list is empty.');
    expect(sentExtras![kExpectedExtraKey], 'The saved items stay.');
    expect(sentExtras![kStepsExtraKey], '1. Add one item');
  });

  testWidgets('the entry flow puts expected and steps into the report',
      (tester) async {
    final store = MemoryDraftStore();
    await tester.pumpWidget(
      FeedbackHost(
        spec: testSpec(),
        store: store,
        child: const MaterialApp(
          home: Scaffold(body: FeedbackEntryButton()),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('feedback_entry_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.enterText(
        find.byKey(const Key('text_input_field')), 'The count is wrong.');
    await tester.enterText(find.byKey(const Key('expected_input_field')),
        'The count stays at three.');
    await tester.enterText(
        find.byKey(const Key('steps_input_field')), '1. Open the list');
    await tester.tap(find.byKey(const Key('submit_feedback_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // The preview shows the two optional values before any send.
    expect(find.text('The count stays at three.'), findsOneWidget);
    expect(find.text('1. Open the list'), findsOneWidget);
  });
}
