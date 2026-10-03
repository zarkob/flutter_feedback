// Boundary check: a production run with a feedback setting stops early.
//
// This file must run with a conflicting setting. The check script does that:
//
//   flutter test test_boundary/production_conflict_test.dart \
//     --dart-define=FEEDBACK_BUILD_MODE=test \
//     --dart-define=FEEDBACK_BACKEND_URL=https://relay.test
//
// The production entry refuses the settings, so a conflicting build fails
// instead of shipping a hidden feedback path.

import 'package:feedback_relay_example/main_production.dart' as production;
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a conflicting feedback setting stops the production entry', () {
    expect(() => production.main(), throwsStateError);
  });
}
