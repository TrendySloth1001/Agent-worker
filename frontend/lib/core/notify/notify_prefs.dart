import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/notify_copy.dart';
import 'notify_kind.dart';
import 'notify_policy.dart' show QuietHours;

/// The user's notification choices: master switch, one switch per kind and
/// quiet hours. Persisted; works (in memory) without storage.
class NotifyPrefs extends ChangeNotifier {
  NotifyPrefs(this._prefs) {
    final p = _prefs;
    master = p?.getBool(NotifyConfig.masterKey) ?? true;
    quietOn = p?.getBool(NotifyConfig.quietOnKey) ?? false;
    quietStart =
        p?.getInt(NotifyConfig.quietStartKey) ?? NotifyConfig.defaultQuietStart;
    quietEnd =
        p?.getInt(NotifyConfig.quietEndKey) ?? NotifyConfig.defaultQuietEnd;
    for (final k in NotifyKind.values) {
      _kinds[k] = p?.getBool(k.prefKey) ?? k.defaultOn;
    }
  }

  final SharedPreferences? _prefs;
  final _kinds = <NotifyKind, bool>{};

  /// The system dialog was shown before (it may not appear again).
  bool get asked => _prefs?.getBool(NotifyConfig.askedKey) ?? false;

  void markAsked() => _prefs?.setBool(NotifyConfig.askedKey, true);

  late bool master;
  late bool quietOn;
  late int quietStart, quietEnd;

  bool isOn(NotifyKind k) => _kinds[k] ?? k.defaultOn;

  /// Master and kind switch together.
  bool allows(NotifyKind k) => master && isOn(k);

  QuietHours get quiet => QuietHours(
    enabled: quietOn,
    startMinute: quietStart,
    endMinute: quietEnd,
  );

  void setMaster(bool v) {
    master = v;
    _prefs?.setBool(NotifyConfig.masterKey, v);
    notifyListeners();
  }

  void setKind(NotifyKind k, bool v) {
    _kinds[k] = v;
    _prefs?.setBool(k.prefKey, v);
    notifyListeners();
  }

  void setQuietOn(bool v) {
    quietOn = v;
    _prefs?.setBool(NotifyConfig.quietOnKey, v);
    notifyListeners();
  }

  void setQuietStart(int minute) {
    quietStart = minute;
    _prefs?.setInt(NotifyConfig.quietStartKey, minute);
    notifyListeners();
  }

  void setQuietEnd(int minute) {
    quietEnd = minute;
    _prefs?.setInt(NotifyConfig.quietEndKey, minute);
    notifyListeners();
  }

  /// When [k] was last posted (repeating alerts back off).
  DateTime? lastPosted(NotifyKind k) {
    final ms = _prefs?.getInt(NotifyConfig.lastKey(k.key));
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  final _memoryLast = <NotifyKind, DateTime>{};

  DateTime? lastSeen(NotifyKind k) => _memoryLast[k] ?? lastPosted(k);

  void markPosted(NotifyKind k, DateTime at) {
    _memoryLast[k] = at;
    _prefs?.setInt(NotifyConfig.lastKey(k.key), at.millisecondsSinceEpoch);
  }

  /// Back to defaults (Settings "reset").
  void reset() {
    master = true;
    quietOn = false;
    quietStart = NotifyConfig.defaultQuietStart;
    quietEnd = NotifyConfig.defaultQuietEnd;
    final p = _prefs;
    p?.remove(NotifyConfig.masterKey);
    p?.remove(NotifyConfig.quietOnKey);
    p?.remove(NotifyConfig.quietStartKey);
    p?.remove(NotifyConfig.quietEndKey);
    for (final k in NotifyKind.values) {
      _kinds[k] = k.defaultOn;
      p?.remove(k.prefKey);
    }
    notifyListeners();
  }
}
