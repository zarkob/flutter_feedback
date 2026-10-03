/// Host fixture A: a notes product with its own settings and screen names.
///
/// The host knows nothing about RoutineSpark or Avensora OS. It supplies its
/// product id, its screen names, and its draft store.
library;

import 'package:feedback_relay/feedback_relay.dart';
import 'package:flutter/material.dart';

/// The product settings of this host.
const FeedbackBuildSpec alphaSpec = FeedbackBuildSpec.forTest(
  backendUrl: 'https://relay.test',
  productId: 'alpha-notes',
  testerToken: 'alpha-token',
  productName: 'Alpha Notes',
);

/// The host facts of this fixture.
class AlphaContextSource implements FeedbackContextSource {
  /// Creates the source around the current screen name.
  AlphaContextSource(this.screenName);

  /// The screen that is open now.
  final ValueNotifier<String> screenName;

  @override
  String get appVersion => '0.4.2';

  @override
  String get buildNumber => '18';

  @override
  String get screen => screenName.value;

  @override
  String get sourceRevision => kUnknownFact;

  @override
  DeviceFacts get device => DeviceFacts.unknown;
}

/// Builds the fixture app for one build spec.
Widget alphaHost({
  required FeedbackBuildSpec spec,
  required DraftStore store,
  required ValueNotifier<String> screenName,
  RelayClient? client,
  void Function(DeliveryResult result)? onResult,
}) {
  return FeedbackHost(
    spec: spec,
    store: store,
    client: client,
    contextSource: AlphaContextSource(screenName),
    child: MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Alpha Notes')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            const Text('Notes list'),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('alpha_add_note'),
              onPressed: () => screenName.value = 'note_editor',
              child: const Text('Add a note'),
            ),
            const SizedBox(height: 12),
            FeedbackEntryButton(onResult: onResult),
            const SizedBox(height: 24),
            const FeedbackDraftList(emptyText: 'No report is saved.'),
          ],
        ),
      ),
    ),
  );
}
