import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../constants/update.dart';

/// Steps of an update attempt the server hears about (names match the API).
enum InstallStage {
  downloadStart('download_start'),
  downloadOk('download_ok'),
  downloadFail('download_fail'),
  verifyFail('verify_fail'),
  signatureMismatch('signature_mismatch'),
  installStart('install_start'),
  installOk('install_ok'),
  installFail('install_fail'),
  cancelled('cancelled'),
  firstLaunchOk('first_launch_ok');

  const InstallStage(this.wire);
  final String wire;
}

/// How the bytes arrived.
enum InstallVia { full, resume }

/// One queued event.
class InstallEvent {
  const InstallEvent({
    required this.at,
    required this.build,
    required this.toBuild,
    required this.stage,
    this.code,
    this.bytes,
    this.via = InstallVia.full,
  });

  /// Epoch milliseconds on the device.
  final int at;
  final int build;
  final int toBuild;
  final InstallStage stage;
  final String? code;
  final int? bytes;
  final InstallVia via;

  Map<String, dynamic> toJson() => {
    'at': at,
    'build': build,
    'toBuild': toBuild,
    'stage': stage.wire,
    'code': ?code,
    'bytes': ?bytes,
    'via': via.name,
  };

  static InstallEvent? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final stage = InstallStage.values
        .where((s) => s.wire == raw['stage'])
        .firstOrNull;
    final at = raw['at'];
    final build = raw['build'];
    final toBuild = raw['toBuild'];
    if (stage == null || at is! int || build is! int || toBuild is! int) {
      return null;
    }
    return InstallEvent(
      at: at,
      build: build,
      toBuild: toBuild,
      stage: stage,
      code: raw['code'] as String?,
      bytes: raw['bytes'] as int?,
      via: raw['via'] == 'resume' ? InstallVia.resume : InstallVia.full,
    );
  }
}

/// Sends a batch; throws when it could not be delivered.
typedef EventSender =
    Future<void> Function(String deviceId, List<Map<String, dynamic>> events);

/// An offline-tolerant queue of [InstallEvent]s.
///
/// Events are kept in preferences, bounded to [UpdateConfig.eventQueueMax]
/// (oldest dropped) and [UpdateConfig.eventMaxAge]. [flush] sends them in
/// batches and removes only what the server accepted, so a failed send (offline,
/// signed out, rate limited) loses nothing. Never throws.
class UpdateEventReporter {
  UpdateEventReporter({
    required EventSender send,
    Future<SharedPreferences> Function()? prefs,
    DateTime Function()? clock,
  }) : _send = send,
       _prefs = prefs ?? SharedPreferences.getInstance,
       _clock = clock ?? DateTime.now;

  final EventSender _send;
  final Future<SharedPreferences> Function() _prefs;
  final DateTime Function() _clock;
  Future<void>? _inFlight;

  /// Queues an event (and trims the queue).
  Future<void> record({
    required int build,
    required int toBuild,
    required InstallStage stage,
    String? code,
    int? bytes,
    InstallVia via = InstallVia.full,
  }) async {
    try {
      final p = await _prefs();
      final list = _load(p)
        ..add(
          InstallEvent(
            at: _clock().millisecondsSinceEpoch,
            build: build,
            toBuild: toBuild,
            stage: stage,
            code: code,
            bytes: bytes,
            via: via,
          ),
        );
      await _save(p, _trim(list));
    } catch (_) {}
  }

  /// How many events are waiting.
  Future<int> pending() async => _load(await _prefs()).length;

  /// Sends everything queued, [UpdateConfig.eventBatch] at a time.
  Future<void> flush() =>
      _inFlight ??= _flush().whenComplete(() => _inFlight = null);

  Future<void> _flush() async {
    try {
      final p = await _prefs();
      final deviceId = _deviceId(p);
      while (true) {
        final list = _trim(_load(p));
        await _save(p, list);
        if (list.isEmpty) return;
        final batch = list.take(UpdateConfig.eventBatch).toList();
        await _send(deviceId, [for (final e in batch) e.toJson()]);
        // Re-read: events recorded while the request was in flight stay.
        final now = _load(p);
        final sent = batch.length;
        await _save(p, now.length >= sent ? now.sublist(sent) : const []);
      }
    } catch (_) {
      // Offline or refused: the queue stays for the next flush.
    }
  }

  List<InstallEvent> _trim(List<InstallEvent> list) {
    final cutoff = _clock()
        .subtract(UpdateConfig.eventMaxAge)
        .millisecondsSinceEpoch;
    final fresh = list.where((e) => e.at >= cutoff).toList();
    final over = fresh.length - UpdateConfig.eventQueueMax;
    return over > 0 ? fresh.sublist(over) : fresh;
  }

  List<InstallEvent> _load(SharedPreferences p) {
    final raw = p.getString(UpdatePrefs.events);
    if (raw == null) return [];
    try {
      return [
        for (final e in jsonDecode(raw) as List) ?InstallEvent.fromJson(e),
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> _save(SharedPreferences p, List<InstallEvent> list) =>
      list.isEmpty
      ? p.remove(UpdatePrefs.events)
      : p.setString(
          UpdatePrefs.events,
          jsonEncode([for (final e in list) e.toJson()]),
        );

  /// A random id for this install (not tied to the hardware).
  static String _deviceId(SharedPreferences p) {
    final have = p.getString(UpdatePrefs.deviceId);
    if (have != null && have.isNotEmpty) return have;
    final r = Random.secure();
    final id = List.generate(
      16,
      (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    p.setString(UpdatePrefs.deviceId, id);
    return id;
  }

  /// The id sent with events (created on first use).
  Future<String> deviceId() async => _deviceId(await _prefs());
}

/// Did the app start for the first time after an update?
abstract final class FirstLaunch {
  /// [previous] is the build recorded at the last launch (null on the very
  /// first run), [current] the running one.
  static bool afterUpdate(int? previous, int current) =>
      previous != null && current > previous;
}
