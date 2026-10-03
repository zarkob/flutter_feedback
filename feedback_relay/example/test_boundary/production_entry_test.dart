// Boundary check: the production entry runs without the feedback tool.
//
// Run it through `tool/check_build_boundary.sh`, or directly with:
//
//   flutter test test_boundary/production_entry_test.dart

import 'package:feedback_relay/feedback_relay.dart';
import 'package:feedback_relay_example/main_production.dart' as production;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the production entry has no feedback wrapper and no feedback control', (tester) async {
    production.main();
    await tester.pump();

    expect(find.text('Example product'), findsOneWidget);
    expect(find.byType(BetterFeedback), findsNothing);
    expect(find.byKey(const Key('feedback_entry_button')), findsNothing);
    expect(find.text('Send feedback'), findsNothing);
    expect(find.text('Saved reports'), findsNothing);
  });

  testWidgets('the production product still works', (tester) async {
    production.main();
    await tester.pump();

    await tester.tap(find.byKey(const Key('add_item')));
    await tester.pump();

    expect(find.text('Items: 1'), findsOneWidget);
    await tester.tap(find.byKey(const Key('open_details')));
    await tester.pumpAndSettle();
    expect(find.text('The details screen.'), findsOneWidget);
  });
}
