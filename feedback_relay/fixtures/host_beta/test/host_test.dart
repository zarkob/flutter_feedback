import 'dart:convert';
import 'dart:typed_data';

import 'package:feedback_relay/feedback_relay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:host_beta/host.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A relay that answers from a script of answers, in order.
class ScriptedRelay {
  ScriptedRelay(this.answers);

  final List<http.Response> answers;
  final List<http.Request> requests = <http.Request>[];

  RelayClient get client => RelayClient(
    spec: betaSpec,
    httpClient: MockClient((request) async {
      requests.add(request);
      return answers.isEmpty ? http.Response('{}', 500) : answers.removeAt(0);
    }),
  );
}

Future<void> submitReport(WidgetTester tester, {String text = 'The tracker shows a wrong count.'}) async {
  await tester.tap(find.byKey(const Key('feedback_entry_button')));
  await tester.pump();
  final context = tester.element(find.byKey(const Key('feedback_entry_button')));
  BetterFeedback.of(context).onFeedback!(UserFeedback(text: text, screenshot: Uint8List(0)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> tapSheet(WidgetTester tester, Key key) async {
  await tester.tap(find.byKey(key));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

http.Response created(String url) => http.Response(jsonEncode(<String, dynamic>{'ok': true, 'status': 'created', 'issue_url': url}), 201);
http.Response checkCreated(String url) => http.Response(jsonEncode(<String, dynamic>{'ok': true, 'status': 'created', 'issue_url': url}), 200);
http.Response notRecorded() => http.Response(jsonEncode(<String, dynamic>{'ok': true, 'status': 'not_found'}), 200);

void main() {
  testWidgets('the development host sends with its own product id', (tester) async {
    final store = MemoryDraftStore();
    final relay = ScriptedRelay(<http.Response>[created('https://github.com/example/beta/issues/7')]);
    await tester.pumpWidget(betaHost(spec: betaSpec, store: store, screenName: ValueNotifier<String>('tracker_home'), client: relay.client));

    await submitReport(tester);
    await tapSheet(tester, const Key('feedback_preview_send'));

    final body = jsonDecode(relay.requests.single.body) as Map<String, dynamic>;
    expect((body['context'] as Map<String, dynamic>)['product_id'], 'beta-tracker');
    expect((body['context'] as Map<String, dynamic>)['build_mode'], 'development');
    expect((body['context'] as Map<String, dynamic>)['product_name'], 'Beta Tracker');
    expect(find.text('Sent'), findsOneWidget);
  });

  testWidgets('a report with an unknown delivery is checked before it is sent again', (tester) async {
    final store = MemoryDraftStore();
    final relay = ScriptedRelay(<http.Response>[
      http.Response('{}', 502),
      notRecorded(),
      created('https://github.com/example/beta/issues/8'),
    ]);
    await tester.pumpWidget(betaHost(spec: betaSpec, store: store, screenName: ValueNotifier<String>('tracker_home'), client: relay.client));

    await submitReport(tester);
    await tapSheet(tester, const Key('feedback_preview_send'));
    expect(find.text('Needs a check'), findsOneWidget);

    final id = (await store.list()).single.id;
    await tester.tap(find.byKey(Key('draft_check_$id')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // The check says that no report is recorded. The app may send it again.
    expect(relay.requests.length, 2);
    await tester.tap(find.byKey(Key('draft_retry_$id')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(relay.requests.length, 3);
    expect((await store.list()).single.state, ReportDeliveryState.sent);
  });

  testWidgets('a production build keeps the host and hides the tool', (tester) async {
    const production = FeedbackBuildSpec.production();
    await tester.pumpWidget(betaHost(spec: production, store: MemoryDraftStore(), screenName: ValueNotifier<String>('tracker_home')));

    expect(find.byKey(const Key('feedback_entry_button')), findsNothing);
    expect(find.text('Tracked items'), findsOneWidget);
    expect(find.text('No report is saved.'), findsOneWidget);
  });

  testWidgets('the tester can remove a saved draft', (tester) async {
    final store = MemoryDraftStore();
    final report = FeedbackReport.create(text: 'Remove this report.', productId: 'beta-tracker', screen: 'tracker_home');
    await store.save(ReportDraft(report: report));
    await tester.pumpWidget(betaHost(spec: betaSpec, store: store, screenName: ValueNotifier<String>('tracker_home')));
    await tester.pump();

    await tester.tap(find.byKey(Key('draft_remove_${report.id}')));
    await tester.pump();

    expect(await store.list(), isEmpty);
    expect(find.text('No report is saved.'), findsOneWidget);
  });
}
