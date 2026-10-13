import 'dart:async';

import 'package:flutter/services.dart';

import '../../core/constants/live_voice.dart';
import '../../features/chat/voice/voice_controller.dart';

/// Reads text aloud. An interface so Live mode is tested without Android.
abstract class Speaker {
  /// Speaks [text] after what is already queued; completes when it was
  /// spoken or stopped.
  Future<void> speak(String text, {String? lang});

  /// Silences it at once; pending [speak] calls complete.
  Future<void> stop();
}

/// Android TextToSpeech through TtsBridge.kt ('app/tts').
class ChannelSpeaker implements Speaker {
  ChannelSpeaker() {
    _channel.setMethodCallHandler((call) async {
      if (call.method != LiveConfig.onDone) return;
      _pending.remove(call.arguments)?.complete();
    });
  }

  static const _channel = MethodChannel(LiveConfig.channel);
  final _pending = <String, Completer<void>>{};
  var _next = 0;

  @override
  Future<void> speak(String text, {String? lang}) async {
    final id = '${_next++}';
    final done = Completer<void>();
    _pending[id] = done;
    try {
      final ok = await _channel.invokeMethod<bool>(LiveConfig.speak, {
        LiveConfig.text: text,
        LiveConfig.lang: lang,
        LiveConfig.id: id,
      });
      if (ok != true) _pending.remove(id)?.complete();
    } catch (_) {
      _pending.remove(id)?.complete();
    }
    return done.future;
  }

  @override
  Future<void> stop() async {
    for (final c in _pending.values) {
      if (!c.isCompleted) c.complete();
    }
    _pending.clear();
    try {
      await _channel.invokeMethod<void>(LiveConfig.stop);
    } catch (_) {}
  }
}

/// The microphone side of Live mode. An interface so the state machine is
/// tested with fakes.
abstract class LiveEars {
  bool get listening;

  /// Listens once: [onText] gets partial text and then the final text;
  /// [onSilence] when it ended without any (silence, an error).
  Future<void> listen({
    required void Function(String text, bool isFinal) onText,
    required void Function() onSilence,
  });

  Future<void> stop();
}

/// [LiveEars] on the app's dictation ([VoiceController]): Android's
/// recognizer ends a turn by itself when the speaker pauses.
class VoiceEars implements LiveEars {
  VoiceEars(this.voice);

  final VoiceController voice;
  void Function()? _watch;

  @override
  bool get listening => voice.active;

  @override
  Future<void> listen({
    required void Function(String text, bool isFinal) onText,
    required void Function() onSilence,
  }) async {
    _unwatch();
    var heard = false;
    var started = false;
    void watch() {
      if (voice.active) {
        started = true;
        return;
      }
      if (!started) return;
      _unwatch();
      if (voice.phase == VoicePhase.error) voice.dismiss();
      if (!heard) onSilence();
    }

    _watch = watch;
    voice.addListener(watch);
    await voice.start((text, isFinal) {
      if (isFinal) heard = true;
      onText(text, isFinal);
    });
    // Did not start at all (no permission, no recognizer).
    if (!voice.active && !heard) {
      _unwatch();
      if (voice.phase == VoicePhase.error) voice.dismiss();
      onSilence();
    }
  }

  void _unwatch() {
    final w = _watch;
    if (w != null) voice.removeListener(w);
    _watch = null;
  }

  @override
  Future<void> stop() async {
    _unwatch();
    await voice.cancel();
  }
}
