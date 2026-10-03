/// Host fixture B: a tracker product with a different product id and build.
///
/// This fixture uses the development mode name and a different draft store
/// setup, so it proves that the package carries no product assumption.
library;

import 'package:feedback_relay/feedback_relay.dart';
import 'package:flutter/material.dart';

/// The product settings of this host.
const FeedbackBuildSpec betaSpec = FeedbackBuildSpec.forDevelopment(
  backendUrl: 'https://relay.beta.test',
  productId: 'beta-tracker',
  testerToken: 'beta-token',
  productName: 'Beta Tracker',
);

/// The host facts of this fixture.
class BetaContextSource implements FeedbackContextSource {
  /// Creates the source around one screen name.
  BetaContextSource(this.screenName, {this.revision = kUnknownFact});

  /// The screen that is open now.
  final ValueNotifier<String> screenName;

  /// The revision recorded in the build settings, when the host has one.
  final String revision;

  @override
  String get appVersion => '2.1.0';

  @override
  String get buildNumber => '301';

  @override
  String get screen => screenName.value;

  @override
  String get sourceRevision => revision;

  @override
  DeviceFacts get device => const DeviceFacts(model: 'Pixel 7', platform: 'android', osVersion: 'Android 15', locale: 'de');
}

/// Builds the fixture app for one build spec.
Widget betaHost({
  required FeedbackBuildSpec spec,
  required DraftStore store,
  required ValueNotifier<String> screenName,
  RelayClient? client,
  DeviceFacts? device,
}) {
  return FeedbackHost(
    spec: spec,
    store: store,
    client: client,
    contextSource: BetaContextSource(screenName),
    child: MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Beta Tracker')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            const Text('Tracked items'),
            const SizedBox(height: 12),
            const FeedbackEntryButton(label: 'Report a problem'),
            const SizedBox(height: 24),
            const FeedbackDraftList(emptyText: 'No report is saved.'),
          ],
        ),
      ),
    ),
  );
}
