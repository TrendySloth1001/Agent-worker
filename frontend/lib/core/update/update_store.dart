import 'package:shared_preferences/shared_preferences.dart';

import '../constants/update.dart';
import 'update_policy.dart';

/// A finished download: `<build>|<path>|<sha256>` in `ota.downloaded`.
class DownloadRecord {
  const DownloadRecord(this.build, this.path, this.sha256);

  final int build;
  final String path;
  final String sha256;

  String get encoded => '$build|$path|$sha256';

  static DownloadRecord? parse(String? raw) {
    if (raw == null) return null;
    final parts = raw.split('|');
    if (parts.length != 3) return null;
    final build = int.tryParse(parts[0]);
    if (build == null || parts[1].isEmpty) return null;
    return DownloadRecord(build, parts[1], parts[2]);
  }
}

/// An install handed to the system: running build -> target build.
class PendingInstall {
  const PendingInstall(this.from, this.to);

  final int from;
  final int to;

  String get encoded => '$from|$to';

  static PendingInstall? parse(String? raw) {
    final parts = raw?.split('|');
    if (parts == null || parts.length != 2) return null;
    final from = int.tryParse(parts[0]);
    final to = int.tryParse(parts[1]);
    return from == null || to == null ? null : PendingInstall(from, to);
  }
}

/// The `ota.*` preferences.
class UpdateStore {
  UpdateStore(this._p);

  final SharedPreferences _p;

  static Future<UpdateStore> open() async =>
      UpdateStore(await SharedPreferences.getInstance());

  DateTime? get lastCheckAt => _time(UpdatePrefs.lastCheckAt);
  Future<void> setLastCheckAt(DateTime t) =>
      _p.setInt(UpdatePrefs.lastCheckAt, t.millisecondsSinceEpoch);

  PromptState get prompt => PromptState(
    promptedBuild: _p.getInt(UpdatePrefs.promptedBuild),
    promptCount: _p.getInt(UpdatePrefs.promptCount) ?? 0,
    nextPromptAt: _time(UpdatePrefs.nextPromptAt),
  );

  Future<void> setPrompt(PromptState s) async {
    if (s.promptedBuild != null) {
      await _p.setInt(UpdatePrefs.promptedBuild, s.promptedBuild!);
    }
    await _p.setInt(UpdatePrefs.promptCount, s.promptCount);
    if (s.nextPromptAt == null) {
      await _p.remove(UpdatePrefs.nextPromptAt);
    } else {
      await _p.setInt(
        UpdatePrefs.nextPromptAt,
        s.nextPromptAt!.millisecondsSinceEpoch,
      );
    }
  }

  int? get notifiedBuild => _p.getInt(UpdatePrefs.notifiedBuild);
  Future<void> setNotifiedBuild(int b) =>
      _p.setInt(UpdatePrefs.notifiedBuild, b);

  bool get wifiOnly => _p.getBool(UpdatePrefs.wifiOnly) ?? true;
  Future<void> setWifiOnly(bool v) => _p.setBool(UpdatePrefs.wifiOnly, v);

  DownloadRecord? get downloaded =>
      DownloadRecord.parse(_p.getString(UpdatePrefs.downloaded));
  Future<void> setDownloaded(DownloadRecord? r) => r == null
      ? _p.remove(UpdatePrefs.downloaded)
      : _p.setString(UpdatePrefs.downloaded, r.encoded);

  int? get lastBuild => _p.getInt(UpdatePrefs.lastBuild);
  Future<void> setLastBuild(int b) => _p.setInt(UpdatePrefs.lastBuild, b);

  PendingInstall? get pending =>
      PendingInstall.parse(_p.getString(UpdatePrefs.pending));
  Future<void> setPending(PendingInstall? p) => p == null
      ? _p.remove(UpdatePrefs.pending)
      : _p.setString(UpdatePrefs.pending, p.encoded);

  DateTime? _time(String key) {
    final ms = _p.getInt(key);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }
}
