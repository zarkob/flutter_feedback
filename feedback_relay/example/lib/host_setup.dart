/// The host side of the example: build settings, private storage, host facts.
///
/// This file imports the feedback package. The production entry must not
/// import this file.
library;

import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:feedback_relay/feedback_relay.dart';
import 'package:feedback_relay/file_draft_store.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

/// The host facts for the example product.
class ExampleContextSource implements FeedbackContextSource {
  /// Creates the source with the facts that the host could read.
  ExampleContextSource({
    required this.screenName,
    required this.appVersion,
    required this.buildNumber,
    required this.deviceFacts,
  });

  /// The current screen name. The app updates this value on navigation.
  final ValueNotifier<String> screenName;

  @override
  final String appVersion;

  @override
  final String buildNumber;

  /// The device facts that the host could read.
  final DeviceFacts deviceFacts;

  @override
  String get screen => screenName.value;

  @override
  String get sourceRevision => kUnknownFact;

  @override
  DeviceFacts get device => deviceFacts;
}

/// Reads the small named set of device facts.
///
/// A fact that this host cannot read stays `Unknown`. The set holds no account
/// data, no device serial, and no log.
Future<DeviceFacts> readDeviceFacts() async {
  final plugin = DeviceInfoPlugin();
  final locale = WidgetsBinding.instance.platformDispatcher.locale.toString();
  try {
    if (Platform.isAndroid) {
      final info = await plugin.androidInfo;
      return DeviceFacts(
        model: info.model,
        platform: 'android',
        osVersion: 'Android ${info.version.release}',
        locale: locale,
      );
    }
    if (Platform.isIOS) {
      final info = await plugin.iosInfo;
      return DeviceFacts(
        model: info.utsname.machine,
        platform: 'ios',
        osVersion: '${info.systemName} ${info.systemVersion}',
        locale: locale,
      );
    }
    return DeviceFacts(
      model: kUnknownFact,
      platform: Platform.operatingSystem,
      osVersion: Platform.operatingSystemVersion,
      locale: locale,
    );
  } catch (_) {
    return DeviceFacts.unknown;
  }
}

/// Opens the private draft folder of the app.
Future<FileDraftStore> openDraftStore() async {
  final root = await getApplicationSupportDirectory();
  return FileDraftStore(Directory('${root.path}${Platform.pathSeparator}feedback_drafts'));
}
