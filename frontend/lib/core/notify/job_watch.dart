import 'dart:async';

import '../../data/files_api.dart';
import '../../data/kb_source.dart';
import '../constants/app_config.dart';
import '../constants/notify_copy.dart';
import '../../data/knowledge_api.dart';
import 'notification_center.dart';
import 'notify_kind.dart';
import 'notify_target.dart';

/// Watches long server jobs (video transcode, audio transcription, document
/// and source ingest) for as long as the app lives, wherever the user is in
/// it, and notifies when one finishes or fails. The screens keep their own
/// polling for what they show; this one only exists to tell the user.
class JobWatch {
  JobWatch({
    NotificationCenter? center,
    Future<FileInfo> Function(String id)? fetchFile,
    Future<List<KbSource>> Function()? fetchSources,
    DateTime Function()? clock,
    bool Function()? enabled,
  }) : _center = center ?? NotificationCenter.instance,
       _fetchFile =
           fetchFile ?? ((id) => FilesApi.instance.get(id, force: true)),
       _fetchSources =
           fetchSources ?? (() => KnowledgeApi(AppConfig.apiBaseUrl).list()),
       _clock = clock ?? DateTime.now,
       _enabled =
           enabled ?? (() => (center ?? NotificationCenter.instance).ready);

  static final instance = JobWatch();

  final NotificationCenter _center;
  final Future<FileInfo> Function(String id) _fetchFile;
  final Future<List<KbSource>> Function() _fetchSources;
  final DateTime Function() _clock;
  final bool Function() _enabled;

  final _files = <String, _Job>{};
  final _sources = <String, _Job>{};
  Timer? _timer;
  bool _busy = false;

  int get pending => _files.length + _sources.length;

  /// Starts watching [file] if the server is still processing it.
  void watchFile(FileInfo file) {
    if (!_enabled()) return;
    if (file.status != FileStatus.processing || file.id.isEmpty) return;
    if (_files.containsKey(file.id)) return;
    final long = file.kind == FileKind.video || file.kind == FileKind.audio;
    _files[file.id] = _Job(file.name, _clock(), long: long);
    _begin(long: long);
  }

  /// Starts watching a knowledge source that was queued or is running.
  void watchSource(KbSource source) {
    if (!_enabled()) return;
    if (!source.isActive || _sources.containsKey(source.id)) return;
    final name = (source.title ?? '').trim().isEmpty
        ? source.uri
        : source.title!;
    _sources[source.id] = _Job(name, _clock());
    _begin(long: false);
  }

  void _begin({required bool long}) {
    _timer ??= Timer.periodic(NotifyConfig.watchInterval, (_) => tick());
    // A video takes minutes: keep the process alive at once. Quick jobs
    // only get the service when they run past a few seconds.
    if (long) {
      _keepAlive();
    } else {
      Timer(NotifyConfig.watchServiceAfter, () {
        if (pending > 0 && !_center.background.value) _keepAlive();
      });
    }
  }

  void _keepAlive() {
    if (pending == 0 || !_center.prefs.master) return;
    unawaited(
      _center.keepAlive(
        NotifyKind.file,
        title: NotifyCopy.fileProgressTitle,
        body: NotifyCopy.fileProgressBody(pending),
      ),
    );
  }

  /// One round of checks. Public so tests can drive it.
  Future<void> tick() async {
    if (_busy) return;
    _busy = true;
    try {
      await _checkFiles();
      await _checkSources();
    } finally {
      _busy = false;
      _settle();
    }
  }

  Future<void> _checkFiles() async {
    for (final id in _files.keys.toList()) {
      final job = _files[id]!;
      if (_expired(job)) {
        _files.remove(id);
        continue;
      }
      try {
        final fresh = await _fetchFile(id);
        if (fresh.status == FileStatus.processing) continue;
        _files.remove(id);
        final name = fresh.name.isEmpty ? job.name : fresh.name;
        final failed = fresh.status == FileStatus.failed;
        await _center.post(
          NotifyKind.file,
          key: id,
          title: failed
              ? NotifyCopy.fileFailedTitle
              : NotifyCopy.fileReadyTitle,
          body: failed
              ? '$name${fresh.error == null ? '' : ': ${fresh.error}'}'
              : NotifyCopy.fileReadyBody(name),
          target: FileTarget(id),
        );
      } catch (_) {
        // Offline or a hiccup: the next round tries again until it expires.
      }
    }
  }

  Future<void> _checkSources() async {
    if (_sources.isEmpty) return;
    final List<KbSource> list;
    try {
      list = await _fetchSources();
    } catch (_) {
      return;
    }
    for (final id in _sources.keys.toList()) {
      final job = _sources[id]!;
      final s = list.where((e) => e.id == id).firstOrNull;
      // Deleted meanwhile, or too old to be worth waiting for.
      if (s == null || _expired(job)) {
        _sources.remove(id);
        continue;
      }
      if (s.isActive) continue;
      _sources.remove(id);
      final failed = s.status == 'failed' || s.error != null;
      final name = (s.title ?? '').trim().isEmpty ? job.name : s.title!;
      await _center.post(
        NotifyKind.source,
        key: id,
        title: failed
            ? NotifyCopy.sourceFailedTitle
            : NotifyCopy.sourceReadyTitle,
        body: failed
            ? '$name${s.error == null ? '' : ': ${s.error}'}'
            : NotifyCopy.sourceReadyBody(name, s.docCount),
        target: const SettingsTarget('knowledge'),
      );
    }
  }

  bool _expired(_Job j) =>
      _clock().difference(j.since) > NotifyConfig.watchMaxAge;

  /// Stops the timer and the service when nothing is left to watch.
  void _settle() {
    if (pending > 0) {
      // Quick jobs in the foreground need no notification at all.
      if (!_center.isAlive(NotifyKind.file)) return;
      unawaited(
        _center.progress(
          NotifyKind.file,
          title: NotifyCopy.fileProgressTitle,
          body: NotifyCopy.fileProgressBody(pending),
        ),
      );
      return;
    }
    _timer?.cancel();
    _timer = null;
    unawaited(_center.finishProgress(NotifyKind.file));
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}

class _Job {
  _Job(this.name, this.since, {this.long = false});
  final String name;
  final DateTime since;
  final bool long;
}
