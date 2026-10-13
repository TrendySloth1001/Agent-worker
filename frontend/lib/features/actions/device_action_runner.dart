import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/constants/device_actions.dart';
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

  /// Runs [action]. Only ever called from the card's Confirm button.
  Future<ActionOutcome> run(DeviceAction action);
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
Map<String, Object> deviceActionsRequest([DateTime? now]) => {
  DeviceActionWire.localTime: localIso(now ?? DateTime.now()),
};

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
