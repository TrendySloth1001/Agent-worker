import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../constants/errors.dart';

/// A report waiting to be sent: the JSON body part plus when it was queued.
class QueueEntry {
  const QueueEntry(this.key, this.queuedAt, this.payload);

  /// Unique within the queue; used to remove exactly what was sent.
  final String key;
  final int queuedAt;
  final Map<String, dynamic> payload;

  Map<String, dynamic> toJson() => {'k': key, 'q': queuedAt, 'p': payload};

  static QueueEntry? fromJson(Object? j) {
    if (j is! Map) return null;
    final k = j['k'];
    final q = j['q'];
    final p = j['p'];
    if (k is! String || q is! int || p is! Map) return null;
    return QueueEntry(k, q, p.cast<String, dynamic>());
  }
}

/// A small offline queue in shared preferences: at most 50 entries and 200 KB,
/// entries older than 7 days are dropped (oldest go first when full).
class ErrorQueue {
  ErrorQueue(this._p, this.prefKey, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final SharedPreferences _p;
  final String prefKey;
  final DateTime Function() _clock;
  static final _rng = Random();

  /// Other isolates (the assistant overlay) write the same store.
  Future<void> reload() => _p.reload();

  List<QueueEntry> read() {
    final raw = _p.getString(prefKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      final cutoff = _clock()
          .subtract(ErrorsConfig.queueMaxAge)
          .millisecondsSinceEpoch;
      return [
        for (final e in list.map(QueueEntry.fromJson).nonNulls)
          if (e.queuedAt >= cutoff) e,
      ];
    } catch (_) {
      return const [];
    }
  }

  int get length => read().length;

  Future<void> add(Map<String, dynamic> payload) async {
    final entries = read().toList()
      ..add(
        QueueEntry(
          '${_clock().microsecondsSinceEpoch}-${_rng.nextInt(1 << 32)}',
          _clock().millisecondsSinceEpoch,
          payload,
        ),
      );
    while (entries.length > ErrorsConfig.queueMaxEntries ||
        (entries.length > 1 && _size(entries) > ErrorsConfig.queueMaxBytes)) {
      entries.removeAt(0);
    }
    await _write(entries);
  }

  /// Removes the entries with these keys (what was just sent or refused).
  Future<void> remove(Iterable<String> keys) async {
    final gone = keys.toSet();
    await _write([
      for (final e in read())
        if (!gone.contains(e.key)) e,
    ]);
  }

  Future<void> clear() => _p.remove(prefKey);

  static int _size(List<QueueEntry> entries) =>
      utf8.encode(jsonEncode([for (final e in entries) e.toJson()])).length;

  Future<void> _write(List<QueueEntry> entries) async {
    if (entries.isEmpty) {
      await _p.remove(prefKey);
    } else {
      await _p.setString(
        prefKey,
        jsonEncode([for (final e in entries) e.toJson()]),
      );
    }
  }
}
