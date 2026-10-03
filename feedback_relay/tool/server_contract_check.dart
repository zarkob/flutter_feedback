/// A local contract check between the package and the relay server.
///
/// It sends a real report through the public package code to a running relay,
/// then repeats the same report id and reads the delivery state back. Start
/// the local relay first:
///
/// ```bash
/// cd ../relay && node src/local_server.ts --port 8791 &
/// dart run tool/server_contract_check.dart --url http://127.0.0.1:8791
/// ```
///
/// The check uses the package model and the package client only. It never
/// calls a real service.
library;

import 'dart:io';

import 'package:feedback_relay/feedback_relay_core.dart';

Future<void> main(List<String> args) async {
  final url = _option(args, '--url') ?? 'http://127.0.0.1:8791';
  final productId = _option(args, '--product') ?? 'local-product';
  final token = _option(args, '--token') ?? 'local-tester-token';

  final spec = FeedbackBuildSpec.forTest(backendUrl: url, productId: productId, testerToken: token);
  final client = RelayClient(spec: spec);
  final report = FeedbackReport.create(
    text: 'Contract check: the list is empty after a restart.',
    expected: 'The saved items stay visible.',
    steps: '1. Add one item\n2. Restart the app',
    productId: productId,
    appVersion: '1.2.4',
    buildNumber: '77',
    buildMode: spec.mode,
    screen: 'contract_check',
    device: const DeviceFacts(model: 'Pixel 7', platform: 'linux', osVersion: 'Ubuntu 24.04', locale: 'en_US'),
  );

  var failures = 0;

  final first = await client.submit(report);
  failures += _expect(first, 'the first send is confirmed', (result) => result is DeliveryConfirmed);

  final repeat = await client.submit(report);
  failures += _expect(
    repeat,
    'a repeated send of the same report id is a duplicate',
    (result) => result is DeliveryConfirmed && result.duplicate,
  );

  final check = await client.check(report.id);
  failures += _expect(
    check,
    'the delivery check proves the report',
    (result) => result is DeliveryConfirmed && result.issueUrl == (first as DeliveryConfirmed).issueUrl,
  );

  final unknown = await client.check('99999999-0000-4000-8000-000000000000');
  failures += _expect(unknown, 'an unknown report id is not recorded', (result) => result is DeliveryNotRecorded);

  final badToken = RelayClient(
    spec: FeedbackBuildSpec.forTest(backendUrl: url, productId: productId, testerToken: 'wrong-token'),
  );
  final denied = await badToken.submit(FeedbackReport.create(text: 'This must not arrive.', productId: productId));
  failures += _expect(
    denied,
    'a wrong tester token is refused',
    (result) => result is DeliveryFailed && result.reason.contains('denied'),
  );

  client.close();
  badToken.close();

  if (failures > 0) {
    stdout.writeln('CONTRACT CHECK FAILED: $failures of 5 checks did not pass.');
    exitCode = 1;
    return;
  }
  stdout.writeln('CONTRACT CHECK PASSED: 5 of 5 checks passed against $url.');
}

int _expect(DeliveryResult result, String what, bool Function(DeliveryResult result) ok) {
  if (ok(result)) {
    stdout.writeln('PASS: $what');
    return 0;
  }
  stdout.writeln('FAIL: $what (result: $result)');
  return 1;
}

String? _option(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index >= 0 && index + 1 < args.length) {
    return args[index + 1];
  }
  return null;
}
