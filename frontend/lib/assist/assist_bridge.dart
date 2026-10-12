import 'dart:async';

import 'package:flutter/services.dart';

import '../core/constants/assist.dart';
import 'screen_text.dart';

/// How the overlay was opened.
enum AssistSource {
  /// The assistant session: power-button hold, corner swipe, Home hold.
  session,

  /// An ASSIST or VOICE_COMMAND intent (no screen context).
  assist,

  /// Settings > Assistant > Try it.
  tryIt;

  static AssistSource parse(Object? raw) => switch (raw) {
    AssistChannel.sourceSession => session,
    AssistChannel.sourceTry => tryIt,
    _ => assist,
  };
}

/// One opening of the overlay.
class AssistShow {
  const AssistShow({required this.source, this.screen = false});

  final AssistSource source;

  /// The system will deliver screen context for this session.
  final bool screen;

  static AssistShow? parse(Object? raw) {
    if (raw is! Map) return null;
    return AssistShow(
      source: AssistSource.parse(raw[AssistChannel.source]),
      screen: raw[AssistChannel.screen] == true,
    );
  }
}

/// The overlay's side of the `app/assist` channel (AssistEngine.kt).
/// An interface so widget tests run without Android.
abstract class AssistBridge {
  /// Each new opening of the overlay (the first one included).
  Stream<AssistShow> get shows;

  /// Starts listening; returns a show that came before Dart was ready.
  Future<AssistShow?> ready();

  /// The pill is on screen (for the open-latency log).
  Future<void> shown();

  /// Closes the overlay and ends the system session.
  Future<void> close();

  /// The screen the session saw, or null when there is none.
  Future<ScreenContext?> screenContext();

  /// Opens the app (on [link], e.g. `sparky://chat/<id>`) and closes the overlay.
  Future<bool> openApp([String? link]);

  /// Opens the system's assistant settings (screenshot / screen text toggles).
  Future<void> assistantSettings();

  /// Opens the app so it can ask for the microphone, and closes the overlay.
  Future<void> allowMicInApp();
}

class ChannelAssistBridge implements AssistBridge {
  ChannelAssistBridge() {
    _channel.setMethodCallHandler((call) async {
      if (call.method != AssistChannel.onShow) return;
      final show = AssistShow.parse(call.arguments);
      if (show != null) _shows.add(show);
    });
  }

  static const _channel = MethodChannel(AssistConfig.channel);
  final _shows = StreamController<AssistShow>.broadcast();

  @override
  Stream<AssistShow> get shows => _shows.stream;

  @override
  Future<AssistShow?> ready() async {
    try {
      return AssistShow.parse(
        await _channel.invokeMethod<Object?>(AssistChannel.ready),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> shown() => _call(AssistChannel.shown);

  @override
  Future<void> close() => _call(AssistChannel.close);

  @override
  Future<void> allowMicInApp() => _call(AssistChannel.allowMic);

  @override
  Future<ScreenContext?> screenContext() async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        AssistChannel.screenContext,
      );
      if (raw == null || raw[AssistChannel.available] != true) return null;
      return ScreenContext.fromChannel(raw);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> openApp([String? link]) async {
    try {
      return await _channel.invokeMethod<bool>(AssistChannel.openApp, {
            AssistChannel.link: link,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> assistantSettings() => _call(AssistChannel.assistantSettings);

  Future<void> _call(String method) async {
    try {
      await _channel.invokeMethod<Object?>(method);
    } catch (_) {}
  }
}
