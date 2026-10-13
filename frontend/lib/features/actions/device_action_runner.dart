import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/constants/device_actions.dart';
import '../../core/constants/media_apps.dart';
import '../../core/notify/notification_center.dart';
import 'device_action.dart';

/// How a confirmed action went.
enum ActionOutcome { done, unavailable, notFound, notifyOff, failed }

/// The phone side of an action card: the `app/actions` channel
/// (DeviceActions.kt) for intents, local notifications for reminders.
abstract class DeviceActionRunner {
  /// The runner cards use; tests swap in a fake.
  static DeviceActionRunner instance = ChannelDeviceActionRunner();

  /// Whether this platform can run actions at all (tests override it).
  static bool? debugSupported;

  static bool get supported =>
      debugSupported ?? (!kIsWeb && Platform.isAndroid);

  /// Runs [action]. Called from a card's Confirm button, or from an
  /// "Open in {app}" chip the user tapped (opening a link needs no confirm).
  Future<ActionOutcome> run(DeviceAction action);

  /// Which of [packages] are installed (and can open links), by package.
  /// Unknown (no bridge) is reported as not installed.
  Future<Map<String, bool>> appAvailability(List<String> packages);
}

class ChannelDeviceActionRunner implements DeviceActionRunner {
  ChannelDeviceActionRunner({
    MethodChannel channel = const MethodChannel(DeviceActionWire.channel),
    Future<bool> Function(DeviceAction)? remind,
  }) : _channel = channel,
       _remind = remind ?? _notify;

  final MethodChannel _channel;
  final Future<bool> Function(DeviceAction) _remind;

  static Future<bool> _notify(DeviceAction a) => NotificationCenter.instance
      .remind(key: a.key, body: a.title, at: a.when!);

  @override
  Future<ActionOutcome> run(DeviceAction action) async {
    if (action.type == DeviceActionType.reminder) {
      return await _remind(action)
          ? ActionOutcome.done
          : ActionOutcome.notifyOff;
    }
    try {
      final r = await _channel.invokeMethod<String>(
        DeviceActionWire.run,
        action.toChannel(),
      );
      return outcomeOf(r);
    } catch (_) {
      return ActionOutcome.failed;
    }
  }

  @override
  Future<Map<String, bool>> appAvailability(List<String> packages) async {
    if (packages.isEmpty) return const {};
    try {
      final r = await _channel.invokeMapMethod<String, bool>(
        MediaAppWire.availability,
        {MediaAppWire.packages: packages},
      );
      return {for (final p in packages) p: r?[p] ?? false};
    } catch (_) {
      return {for (final p in packages) p: false};
    }
  }
}

/// DeviceActions.kt's result string as an outcome.
ActionOutcome outcomeOf(String? result) => switch (result) {
  DeviceActionWire.ok => ActionOutcome.done,
  DeviceActionWire.notFound => ActionOutcome.notFound,
  DeviceActionWire.unavailable => ActionOutcome.unavailable,
  _ => ActionOutcome.failed,
};

/// The `deviceActions` object of POST /chat: the phone can run actions, and
/// its local time (with offset) for "in 10 minutes" / "tomorrow at 9".
/// [installed]: keys of the known media apps on the phone, so "play it in my
/// music app" picks one that is there.
Map<String, Object> deviceActionsRequest([
  DateTime? now,
  List<String>? installed,
]) => {
  DeviceActionWire.localTime: localIso(now ?? DateTime.now()),
  DeviceActionWire.installedApps: ?installed,
};

/// Which of [MediaApps.all] are installed, by key; asked of the phone at
/// most every [DeviceActionSizes.installedFresh]. Null when unknown (no
/// bridge, or the phone did not answer in time). A request uses [cached]
/// and calls [warm] so it never waits: the overlay warms it when it opens.
abstract final class InstalledMediaApps {
  static List<String>? _keys;
  static DateTime? _at;

  @visibleForTesting
  static void reset() {
    _keys = null;
    _at = null;
  }

  /// What the phone last said (null before it answered or when stale).
  static List<String>? get cached {
    final at = _at;
    return at != null &&
            DateTime.now().difference(at) < DeviceActionSizes.installedFresh
        ? _keys
        : null;
  }

  /// Asks the phone again in the background unless the answer is fresh.
  static void warm({DeviceActionRunner? runner}) {
    if (cached == null) unawaited(keys(runner: runner));
  }

  static Future<List<String>?> keys({DeviceActionRunner? runner}) async {
    if (!DeviceActionRunner.supported) return null;
    final at = _at;
    if (_keys != null &&
        at != null &&
        DateTime.now().difference(at) < DeviceActionSizes.installedFresh) {
      return _keys;
    }
    try {
      final r = await (runner ?? DeviceActionRunner.instance).appAvailability([
        for (final a in MediaApps.all) a.package,
      ]);
      _keys = [
        for (final a in MediaApps.all)
          if (r[a.package] ?? false) a.key,
      ];
      _at = DateTime.now();
      return _keys;
    } catch (_) {
      return _keys;
    }
  }
}

/// "2026-10-13T14:05:00+02:00".
String localIso(DateTime t) {
  String two(int n) => n.abs().toString().padLeft(2, '0');
  final o = t.timeZoneOffset;
  final sign = o.isNegative ? '-' : '+';
  final minutes = o.inMinutes.abs();
  return '${t.year.toString().padLeft(4, '0')}-${two(t.month)}-${two(t.day)}'
      'T${two(t.hour)}:${two(t.minute)}:${two(t.second)}'
      '$sign${two(minutes ~/ 60)}:${two(minutes % 60)}';
}
