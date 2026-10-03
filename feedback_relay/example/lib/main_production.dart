/// The production entry of the example product.
///
/// This entry does not import the feedback tool, so the production build holds
/// no feedback control and no sending path. It also rejects a production run
/// that carries a feedback setting. A conflicting build fails early instead of
/// shipping a hidden feedback surface.
///
/// ```bash
/// flutter build apk --release -t lib/main_production.dart
/// ```
library;

import 'package:flutter/material.dart';

import 'app.dart';

const String _buildMode = String.fromEnvironment('FEEDBACK_BUILD_MODE', defaultValue: 'production');
const String _backendUrl = String.fromEnvironment('FEEDBACK_BACKEND_URL');
const String _productId = String.fromEnvironment('FEEDBACK_PRODUCT_ID');
const String _testerToken = String.fromEnvironment('FEEDBACK_TESTER_TOKEN');
const bool _feedbackEnabled = bool.fromEnvironment('FEEDBACK_ENABLED');

/// Starts the example product without the feedback tool.
void main() {
  final conflicts = <String>[
    if (_buildMode != 'production') 'FEEDBACK_BUILD_MODE=$_buildMode',
    if (_backendUrl.isNotEmpty) 'FEEDBACK_BACKEND_URL',
    if (_productId.isNotEmpty) 'FEEDBACK_PRODUCT_ID',
    if (_testerToken.isNotEmpty) 'FEEDBACK_TESTER_TOKEN',
    if (_feedbackEnabled) 'FEEDBACK_ENABLED',
  ];
  if (conflicts.isNotEmpty) {
    throw StateError(
      'The production entry must not carry feedback settings. Remove: ${conflicts.join(', ')}.',
    );
  }
  runApp(const ExampleApp());
}
