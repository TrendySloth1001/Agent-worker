import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../constants/errors.dart';
import 'error_queue.dart';

/// How the process before this one ended, worked out at launch.
class PreviousRun {
  const PreviousRun({
    required this.sessionId,
    required this.build,
    required this.startedAt,
    required this.outcome,
    this.crash,
    this.exit,
  });

  final String sessionId;
  final int build;
  final int startedAt;

  /// ok | crash | anr | killed | unknown (the server's session outcomes).
  final String outcome;

  /// The Kotlin crash file (type, message, stack, thread, at), if one was left.
  final Map<String, dynamic>? crash;

  /// The ApplicationExitInfo reason (reason, description, at), if reported.
  final Map<String, dynamic>? exit;
}

/// App sessions. A session starts at a cold start (or when the app comes back to the
/// foreground) and ends `ok` on a clean pause/detach. A start with no end, plus a Kotlin
/// crash file or an exit reason on the next launch, is a crashed session.
class SessionTracker {
  SessionTracker({
    required SharedPreferences prefs,
    required this.build,
    required bool Function() enabled,
    DateTime Function()? clock,
    void Function()? onChange,
  }) : _prefs = prefs,
       _enabled = enabled,
       _clock = clock ?? DateTime.now,
       _onChange = onChange {
    queue = ErrorQueue(prefs, ErrorsPrefs.sessionQueue, clock: _clock);
  }

  final int build;
  final SharedPreferences _prefs;
  final bool Function() _enabled;
  final DateTime Function() _clock;
  final void Function()? _onChange;
  late final ErrorQueue queue;

  String? currentId;
  int _startedAt = 0;
  bool _ended = true;

  static final _rng = Random.secure();

  /// A random version-4 UUID (the server stores sessions by it).
  static String newId() {
    final b = List<int>.generate(16, (_) => _rng.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    String h(int i) => b[i].toRadixString(16).padLeft(2, '0');
    return '${h(0)}${h(1)}${h(2)}${h(3)}-${h(4)}${h(5)}-${h(6)}${h(7)}-'
        '${h(8)}${h(9)}-${h(10)}${h(11)}${h(12)}${h(13)}${h(14)}${h(15)}';
  }

  /// The outcome of a session that has no recorded end, from what Android and Kotlin left behind.
  static String outcomeOf({
    required bool ended,
    Map<String, dynamic>? crash,
    Map<String, dynamic>? exit,
  }) {
    final reason = exit?['reason'];
    if (crash != null || reason == 'crash' || reason == 'crash_native') {
      return 'crash';
    }
    if (reason == 'anr') return 'anr';
    if (ended) return 'ok';
    if (reason == 'low_memory' || reason == 'signaled') return 'killed';
    return 'unknown';
  }

  /// Cold start: settles the previous process's session, then starts a new one.
  Future<PreviousRun?> begin({Map<String, dynamic>? native}) async {
    PreviousRun? previous;
    final raw = _prefs.getString(ErrorsPrefs.currentSession);
    if (raw != null) {
      try {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        final id = j['id'] as String;
        final prevBuild = (j['build'] as num?)?.toInt() ?? build;
        final started = (j['startedAt'] as num?)?.toInt() ?? 0;
        final ended = j['ended'] == true;
        final crash = (native?['crash'] as Map?)?.cast<String, dynamic>();
        final exit = (native?['exit'] as Map?)?.cast<String, dynamic>();
        final outcome = outcomeOf(ended: ended, crash: crash, exit: exit);
        previous = PreviousRun(
          sessionId: id,
          build: prevBuild,
          startedAt: started,
          outcome: outcome,
          crash: crash,
          exit: exit,
        );
        // A clean end was already queued; only abnormal outcomes are news.
        if (!ended || outcome != 'ok') {
          await _enqueue(
            id: id,
            build: prevBuild,
            startedAt: started,
            outcome: outcome,
          );
        }
      } catch (_) {
        // A corrupt record is simply replaced.
      }
    }
    await _start();
    return previous;
  }

  Future<void> _start() async {
    currentId = newId();
    _startedAt = _clock().millisecondsSinceEpoch;
    _ended = false;
    await _persist();
    await _enqueue(
      id: currentId!,
      build: build,
      startedAt: _startedAt,
      outcome: 'unknown',
    );
  }

  /// Clean pause or detach: `session_end(ok)`.
  Future<void> end() async {
    final id = currentId;
    if (id == null || _ended) return;
    _ended = true;
    await _persist();
    await _enqueue(
      id: id,
      build: build,
      startedAt: _startedAt,
      endedAt: _clock().millisecondsSinceEpoch,
      outcome: 'ok',
    );
  }

  /// Back in the foreground after a clean pause: a new session, so a later crash is its own.
  Future<void> resume() async {
    if (currentId != null && !_ended) return;
    await _start();
  }

  Future<void> _persist() => _prefs.setString(
    ErrorsPrefs.currentSession,
    jsonEncode({
      'id': currentId,
      'build': build,
      'startedAt': _startedAt,
      'ended': _ended,
    }),
  );

  Future<void> _enqueue({
    required String id,
    required int build,
    required int startedAt,
    int? endedAt,
    required String outcome,
  }) async {
    if (!_enabled()) return;
    await queue.add({
      'id': id,
      'build': build,
      'startedAt': startedAt,
      'endedAt': ?endedAt,
      'outcome': outcome,
    });
    _onChange?.call();
  }
}
