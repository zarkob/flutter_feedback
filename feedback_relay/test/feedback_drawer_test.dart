import 'dart:async';

import 'package:feedback_relay/feedback_relay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/relay_fakes.dart';

const _hostKey = Key('drawer_host_bounds');

class _Harness {
  _Harness(
      {required this.widget, required this.navigatorKey, required this.store});

  final Widget widget;
  final GlobalKey<NavigatorState> navigatorKey;
  final MemoryDraftStore store;
}

_Harness _harness({
  bool enabled = true,
  Future<void> Function()? onSaved,
  void Function(DeliveryResult result)? onResult,
  RelayClient? client,
}) {
  final navigatorKey = GlobalKey<NavigatorState>();
  final store = MemoryDraftStore();
  final app = MaterialApp(
    navigatorKey: navigatorKey,
    builder: (context, child) => FeedbackDrawerOverlay(
      navigatorKey: navigatorKey,
      onOpenSavedReports: onSaved ?? () async {},
      onResult: onResult,
      feedbackLabel: 'Повратне информације',
      sendLabel: 'Пошаљи извештај',
      savedLabel: 'Извештаји',
      closeLabel: 'Затвори',
      child: child!,
    ),
    home: Scaffold(
      body: SizedBox.expand(
        key: _hostKey,
        child: const ColoredBox(color: Colors.white),
      ),
    ),
  );
  return _Harness(
    widget: FeedbackHost(
      spec: enabled ? testSpec() : const FeedbackBuildSpec.production(),
      store: store,
      client: client,
      child: app,
    ),
    navigatorKey: navigatorKey,
    store: store,
  );
}

Future<void> _openSend(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('feedback_drawer_tab')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('feedback_drawer_send')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('text_input_field')), findsOneWidget);
  expect(find.byKey(const Key('feedback_drawer_tab')), findsNothing);
}

Future<void> _submitCapture(WidgetTester tester, _Harness harness) async {
  final controller =
      BetterFeedback.of(harness.navigatorKey.currentState!.context);
  controller.onFeedback!(
    UserFeedback(text: 'A test report.', screenshot: onePixelPng),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('feedback_preview_cancel')), findsOneWidget);
  expect(find.byKey(const Key('feedback_drawer_tab')), findsNothing);
}

Future<void> _tapPreviewAction(WidgetTester tester, Key key) async {
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('production keeps the child and hides the drawer',
      (tester) async {
    final app = _harness(enabled: false);
    await tester.pumpWidget(app.widget);

    expect(find.byKey(_hostKey), findsOneWidget);
    expect(find.byKey(const Key('feedback_drawer_tab')), findsNothing);
  });

  testWidgets('closed drawer keeps host bounds and a large safe-edge tab',
      (tester) async {
    tester.view.physicalSize = const Size(390, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final baseline = MaterialApp(
      home: Scaffold(body: SizedBox.expand(key: _hostKey)),
    );
    await tester.pumpWidget(baseline);
    final before = tester.getRect(find.byKey(_hostKey));

    final app = _harness();
    await tester.pumpWidget(app.widget);
    final after = tester.getRect(find.byKey(_hostKey));
    final tab = tester.getSize(find.byKey(const Key('feedback_drawer_tab')));
    expect(after, before);
    expect(tab.width, greaterThanOrEqualTo(48));
    expect(tab.height, greaterThanOrEqualTo(48));
    final semantics = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.byKey(const Key('feedback_drawer_tab'))).label,
      contains('Повратне информације'),
    );
    semantics.dispose();
  });

  testWidgets('drawer shows translated labels and closes with its action',
      (tester) async {
    final app = _harness();
    await tester.pumpWidget(app.widget);
    await tester.tap(find.byKey(const Key('feedback_drawer_tab')));
    await tester.pumpAndSettle();

    expect(find.text('Повратне информације'), findsOneWidget);
    expect(find.text('Пошаљи извештај'), findsOneWidget);
    expect(find.text('Извештаји'), findsOneWidget);
    await tester.tap(find.byKey(const Key('feedback_drawer_close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('feedback_drawer_tab')), findsOneWidget);
    expect(find.byKey(const Key('feedback_drawer_panel')), findsNothing);
  });

  testWidgets('Back and outside tap close the root drawer route',
      (tester) async {
    tester.view.physicalSize = const Size(400, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final app = _harness();
    await tester.pumpWidget(app.widget);
    await tester.tap(find.byKey(const Key('feedback_drawer_tab')));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('feedback_drawer_tab')), findsOneWidget);

    await tester.tap(find.byKey(const Key('feedback_drawer_tab')));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 300));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('feedback_drawer_panel')), findsNothing);
    expect(find.byKey(const Key('feedback_drawer_tab')), findsOneWidget);
  });

  testWidgets('small screen drawer fits the screen and can scroll',
      (tester) async {
    tester.view.physicalSize = const Size(280, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final app = _harness();
    await tester.pumpWidget(app.widget);
    await tester.tap(find.byKey(const Key('feedback_drawer_tab')));
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byKey(const Key('feedback_drawer_panel'))).width,
        lessThanOrEqualTo(280));
    expect(find.byType(ListView), findsOneWidget);
  });

  testWidgets('saved reports start after drawer exit and keep the tab hidden',
      (tester) async {
    var callbackStarted = false;
    var drawerWasClosed = false;
    final finishCallback = Completer<void>();
    final app = _harness(onSaved: () async {
      callbackStarted = true;
      drawerWasClosed =
          find.byKey(const Key('feedback_drawer_panel')).evaluate().isEmpty;
      expect(find.byKey(const Key('feedback_drawer_tab')), findsNothing);
      await finishCallback.future;
    });
    await tester.pumpWidget(app.widget);
    await tester.tap(find.byKey(const Key('feedback_drawer_tab')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('feedback_drawer_saved')));
    await tester.pumpAndSettle();

    expect(callbackStarted, isTrue);
    expect(drawerWasClosed, isTrue);
    expect(find.byKey(const Key('feedback_drawer_tab')), findsNothing);
    finishCallback.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('feedback_drawer_tab')), findsOneWidget);
  });

  testWidgets('capture cancellation restores the tab and saves nothing',
      (tester) async {
    final app = _harness();
    await tester.pumpWidget(app.widget);
    await _openSend(tester);
    final controller =
        BetterFeedback.of(app.navigatorKey.currentState!.context);
    controller.hide();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('feedback_drawer_tab')), findsNothing);
    expect(await app.store.list(), isEmpty);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('feedback_drawer_tab')), findsOneWidget);
    expect(find.text('Review this report'), findsNothing);
    expect(await app.store.list(), isEmpty);
  });

  testWidgets('host removal ends the capture and removes its host listener',
      (tester) async {
    late BuildContext hostContext;
    late Future<void> capture;
    final app = _harness();
    await tester.pumpWidget(
      FeedbackHost(
        spec: testSpec(),
        store: app.store,
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              hostContext = context;
              return const Scaffold(body: SizedBox.expand());
            },
          ),
        ),
      ),
    );
    expect(FeedbackScope.lifecycleOf(hostContext), isNotNull);
    capture = openFeedbackCapture(hostContext);
    await tester.pumpAndSettle();
    var captureDone = false;
    capture.then((_) => captureDone = true);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(find.byType(FeedbackHost), findsNothing);
    await tester.pump();
    expect(captureDone, isTrue);
  });

  testWidgets('tab stays hidden through preview and returns after Cancel',
      (tester) async {
    final app = _harness();
    await tester.pumpWidget(app.widget);
    await _openSend(tester);
    await _submitCapture(tester, app);
    await _tapPreviewAction(tester, const Key('feedback_preview_cancel'));

    expect(await app.store.list(), isEmpty);
    expect(find.byKey(const Key('feedback_drawer_tab')), findsOneWidget);
  });

  testWidgets('Send and Keep finish the full flow and restore the tab',
      (tester) async {
    final relay = FakeRelay(
        (request) async => createdResponse('https://github.com/o/r/issues/7'));
    final results = <DeliveryResult>[];
    final app = _harness(
      client: RelayClient(spec: testSpec(), httpClient: relay.client),
      onResult: results.add,
    );
    await tester.pumpWidget(app.widget);
    await _openSend(tester);
    await _submitCapture(tester, app);
    await _tapPreviewAction(tester, const Key('feedback_preview_send'));

    expect(relay.postCount, 1);
    expect(results.single, isA<DeliveryConfirmed>());
    expect(find.byKey(const Key('feedback_drawer_tab')), findsOneWidget);

    await _openSend(tester);
    await _submitCapture(tester, app);
    await _tapPreviewAction(tester, const Key('feedback_preview_keep'));

    expect((await app.store.list()).length, 2);
    expect(find.byKey(const Key('feedback_drawer_tab')), findsOneWidget);
  });

  testWidgets('saved page failure restores the tab', (tester) async {
    final errors = <Object>[];
    final oldOnError = FlutterError.onError;
    FlutterError.onError = (details) => errors.add(details.exception);
    addTearDown(() => FlutterError.onError = oldOnError);
    final app = _harness(onSaved: () async => throw StateError('open failed'));
    await tester.pumpWidget(app.widget);
    await tester.tap(find.byKey(const Key('feedback_drawer_tab')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('feedback_drawer_saved')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('feedback_drawer_tab')), findsOneWidget);
    expect(errors.single, isA<StateError>());
  });
}
