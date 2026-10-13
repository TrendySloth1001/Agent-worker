import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/constants/live_voice.dart';
import '../../core/haptics.dart';
import 'speakable.dart';
import 'speaker.dart';

/// Where a Live conversation is.
enum LivePhase { off, listening, thinking, speaking }

/// The latest answer as Live sees it: its text so far and whether it ended.
typedef LiveAnswer = ({String text, bool done});

/// One `listen` of the microphone; callbacks of an older one are ignored.
class _Turn {}

/// Live mode: listen, send when the user pauses, read the answer aloud as it
/// streams (sentence by sentence), then listen again. Tapping (or, while it
/// talks, the user starting to talk) interrupts it. Ends on [end], when the
/// overlay closes, or after [LiveConfig.maxSilentTurns] silent listens.
///
/// It owns no network or UI: [ask] sends a question (false when it did not
/// go), [answer] reads the latest reply, [onInterrupt] stops a reply still
/// streaming, and the owner calls [answerChanged] when the reply grows.
class LiveVoice extends ChangeNotifier {
  LiveVoice({
    required this.ears,
    required this.speaker,
    required this.ask,
    required this.answer,
    this.onInterrupt,
    this.lang,
    this.bargeInByVoice = true,
  });

  final LiveEars ears;
  final Speaker speaker;
  final Future<bool> Function(String text) ask;
  final LiveAnswer? Function() answer;
  final VoidCallback? onInterrupt;

  /// BCP-47 tag to speak in (the user's language setting); null: the
  /// device's.
  final String? Function()? lang;

  /// While sparky talks, keep the mic open so speaking interrupts it.
  final bool bargeInByVoice;

  LivePhase _phase = LivePhase.off;
  LivePhase get phase => _phase;
  bool get active => _phase != LivePhase.off;

  /// What the mic heard in this turn (shown while listening).
  String heard = '';

  /// Set when Live stopped by itself (nothing heard for a while).
  bool endedBySilence = false;

  /// The listen whose words count now.
  _Turn? _ear;

  /// Bumped whenever speech is cut off: a late "spoken" stops there.
  int _speech = 0;
  int _silent = 0;
  int _consumed = 0;
  final _queue = <String>[];
  bool _talking = false;
  String _said = '';

  void _set(LivePhase p) {
    _phase = p;
    notifyListeners();
  }

  /// Starts a Live conversation (the mic permission is checked by the caller).
  void start() {
    if (active) return;
    Haptics.recordStart();
    endedBySilence = false;
    _silent = 0;
    unawaited(_listen());
  }

  /// Ends it: silence, mic off.
  void end({bool silence = false}) {
    if (!active) return;
    _ear = null;
    _speech++;
    _queue.clear();
    _talking = false;
    heard = '';
    endedBySilence = silence;
    unawaited(speaker.stop());
    unawaited(ears.stop());
    Haptics.recordStop();
    _set(LivePhase.off);
  }

  /// Tap while thinking or speaking: stop and listen to the user now.
  void interrupt() {
    if (_phase != LivePhase.speaking && _phase != LivePhase.thinking) return;
    Haptics.tap();
    _cut();
    unawaited(_listen());
  }

  void _cut() {
    _speech++;
    _queue.clear();
    _talking = false;
    unawaited(speaker.stop());
    onInterrupt?.call();
  }

  Future<void> _listen() async {
    final turn = _Turn();
    _ear = turn;
    heard = '';
    _set(LivePhase.listening);
    await ears.stop();
    if (_ear != turn) return;
    await ears.listen(
      onText: (text, isFinal) => _onHeard(turn, text, isFinal),
      onSilence: () => _onSilence(turn),
    );
  }

  void _onHeard(_Turn turn, String text, bool isFinal) {
    if (turn != _ear) return;
    if (_phase == LivePhase.speaking) {
      if (!isBargeIn(text, _said)) return;
      // The user talks over sparky: stop it; this listen goes on as the
      // user's turn.
      _cut();
      _phase = LivePhase.listening;
    }
    if (_phase != LivePhase.listening) return;
    heard = text;
    notifyListeners();
    if (isFinal && text.trim().isNotEmpty) unawaited(_send(text.trim()));
  }

  void _onSilence(_Turn turn) {
    if (turn != _ear) return;
    if (_phase != LivePhase.listening) {
      // The barge-in listen ended while sparky talks: nothing to do.
      _ear = null;
      return;
    }
    _silent++;
    if (_silent >= LiveConfig.maxSilentTurns) {
      end(silence: true);
    } else {
      unawaited(_listen());
    }
  }

  Future<void> _send(String text) async {
    _ear = null;
    final speech = ++_speech;
    _silent = 0;
    _consumed = 0;
    _said = '';
    _queue.clear();
    heard = text;
    Haptics.send();
    _set(LivePhase.thinking);
    unawaited(ears.stop());
    final sent = await ask(text);
    if (speech != _speech || !active) return;
    if (!sent) {
      unawaited(_listen());
      return;
    }
    answerChanged();
  }

  /// The reply grew or ended: queue its finished sentences.
  void answerChanged() {
    if (_phase != LivePhase.thinking && _phase != LivePhase.speaking) return;
    final a = answer();
    if (a == null) return;
    final (chunk, next) = nextChunk(a.text, _consumed, done: a.done);
    _consumed = next;
    if (chunk.isNotEmpty) _queue.add(chunk);
    if (_queue.isNotEmpty) {
      unawaited(_pump());
    } else if (a.done && !_talking) {
      unawaited(_listen());
    }
  }

  Future<void> _pump() async {
    if (_talking || _queue.isEmpty) return;
    final speech = _speech;
    _talking = true;
    if (_phase != LivePhase.speaking) {
      _set(LivePhase.speaking);
      if (bargeInByVoice && !ears.listening) {
        final turn = _Turn();
        _ear = turn;
        unawaited(
          ears.listen(
            onText: (text, isFinal) => _onHeard(turn, text, isFinal),
            onSilence: () => _onSilence(turn),
          ),
        );
      }
    }
    final chunk = _queue.removeAt(0);
    _said = '$_said $chunk';
    await speaker.speak(chunk, lang: lang?.call());
    if (speech != _speech) return;
    _talking = false;
    if (_queue.isNotEmpty) {
      unawaited(_pump());
      return;
    }
    final a = answer();
    if (a != null && !a.done) return;
    // Anything that arrived while speaking, else the user's turn.
    final (rest, next) = a == null
        ? ('', _consumed)
        : nextChunk(a.text, _consumed, done: true);
    _consumed = next;
    if (rest.isNotEmpty) {
      _queue.add(rest);
      unawaited(_pump());
    } else {
      unawaited(_listen());
    }
  }

  @override
  void dispose() {
    _ear = null;
    _speech++;
    unawaited(speaker.stop());
    unawaited(ears.stop());
    super.dispose();
  }
}
