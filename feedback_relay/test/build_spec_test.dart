import 'package:feedback_relay/feedback_relay.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/relay_fakes.dart';

void main() {
  group('FeedbackBuildSpec', () {
    test('enables feedback in a test build', () {
      final spec = testSpec();
      expect(spec.isEnabled, isTrue);
      expect(spec.isProduction, isFalse);
      expect(spec.settings?.productId, 'alpha-notes');
      expect(spec.settings?.testerToken, 'tester-token');
    });

    test('keeps a production build closed', () {
      const spec = FeedbackBuildSpec.production();
      expect(spec.isEnabled, isFalse);
      expect(spec.isProduction, isTrue);
      expect(spec.settings, isNull);
      expect(spec.checked().isEnabled, isFalse);
    });

    test('rejects a production build that carries relay settings', () {
      const spec = FeedbackBuildSpec(
        mode: FeedbackBuildModes.production,
        backendUrl: 'https://relay.test',
        productId: 'alpha-notes',
        testerToken: 'tester-token',
      );
      expect(spec.checked, throwsA(isA<FeedbackBoundaryError>()));
    });

    test('rejects FEEDBACK_ENABLED=true in a production build', () {
      const spec = FeedbackBuildSpec(
        mode: FeedbackBuildModes.production,
        extra: <String, String>{'FEEDBACK_ENABLED': 'true'},
      );
      expect(spec.checked, throwsA(isA<FeedbackBoundaryError>()));
    });

    test('rejects FEEDBACK_ENABLED=false in a test build', () {
      const spec = FeedbackBuildSpec(
        mode: FeedbackBuildModes.test,
        backendUrl: 'https://relay.test',
        productId: 'alpha-notes',
        testerToken: 'tester-token',
        extra: <String, String>{'FEEDBACK_ENABLED': 'false'},
      );
      expect(spec.checked, throwsA(isA<FeedbackBoundaryError>()));
    });

    test('rejects an unknown build mode', () {
      const spec = FeedbackBuildSpec(mode: 'demo', backendUrl: 'https://relay.test', productId: 'p', testerToken: 't');
      expect(spec.checked, throwsA(isA<FeedbackBoundaryError>()));
    });

    test('rejects an enabled build with a missing relay setting', () {
      const spec = FeedbackBuildSpec(
        mode: FeedbackBuildModes.test,
        backendUrl: 'https://relay.test',
        productId: 'alpha-notes',
      );
      expect(
        spec.checked,
        throwsA(
          isA<FeedbackBoundaryError>().having((error) => error.reason, 'reason', contains('FEEDBACK_TESTER_TOKEN')),
        ),
      );
    });

    test('rejects a backend url with a trailing slash', () {
      const spec = FeedbackBuildSpec(
        mode: FeedbackBuildModes.test,
        backendUrl: 'https://relay.test/',
        productId: 'alpha-notes',
        testerToken: 'tester-token',
      );
      expect(spec.checked, throwsA(isA<FeedbackBoundaryError>()));
    });

    test('reads an absent environment as a closed production build', () {
      // flutter test passes no FEEDBACK_* settings, so the boundary must stay
      // closed. This is the fail-closed check for a plain production build.
      const spec = FeedbackBuildSpec.production();
      final resolved = FeedbackBuildSpec.fromEnvironment();
      expect(spec.checked().isEnabled, isFalse);
      expect(resolved.mode, FeedbackBuildModes.production);
      expect(resolved.isEnabled, isFalse);
    });
  });
}
