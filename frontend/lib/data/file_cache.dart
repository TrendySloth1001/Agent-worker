import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../core/constants/app_files.dart';
import '../core/constants/error_copy.dart';
import '../core/constants/preview.dart';
import 'chat_api.dart';
import 'files_api.dart';

/// Which stored copy of a file: the original or the small poster.
enum FileVariant { original, thumb }

/// Downloads of files kept in the app cache directory, keyed by file id and
/// variant, so a preview reopens instantly. Signed links last an hour: a
/// download that is refused gets one retry with a freshly signed link.
class FileCache {
  FileCache({
    Future<Directory> Function()? root,
    Future<FileInfo> Function(String id, {bool force})? info,
    http.Client Function()? client,
  }) : _root = root ?? _defaultRoot,
       _info =
           info ??
           ((id, {force = false}) => FilesApi.instance.get(id, force: force)),
       _client = client ?? http.Client.new;

  static FileCache instance = FileCache();

  final Future<Directory> Function() _root;
  final Future<FileInfo> Function(String id, {bool force}) _info;
  final http.Client Function() _client;
  final _inflight = <String, Future<File>>{};

  static Future<Directory> _defaultRoot() async {
    final tmp = await getTemporaryDirectory();
    return Directory(
      '${tmp.path}${Platform.pathSeparator}${PreviewConfig.cacheFolder}',
    );
  }

  Future<Directory> _dir(String id, FileVariant v) async {
    final root = await _root();
    return Directory(
      '${root.path}${Platform.pathSeparator}$id${Platform.pathSeparator}${v.name}',
    );
  }

  /// The cached file when it is already on disk.
  Future<File?> cached(
    FileInfo f, {
    FileVariant variant = FileVariant.original,
  }) async {
    final local = f.localPath;
    if (local != null && File(local).existsSync()) return File(local);
    if (f.id.isEmpty) return null;
    final dir = await _dir(f.id, variant);
    final file = File(
      '${dir.path}${Platform.pathSeparator}${safeFileName(f.name)}',
    );
    return file.existsSync() && file.lengthSync() > 0 ? file : null;
  }

  /// The file's bytes on disk: the picked local file, the cache, or a
  /// download (streamed to disk, never held in memory). [onProgress] is 0..1.
  Future<File> fetch(
    FileInfo f, {
    FileVariant variant = FileVariant.original,
    void Function(double progress)? onProgress,
  }) async {
    final hit = await cached(f, variant: variant);
    if (hit != null) {
      hit.setLastModifiedSync(DateTime.now());
      return hit;
    }
    if (f.id.isEmpty || f.deleted) {
      throw const ApiException(ErrorCopy.downloadFailed);
    }
    final key = '${f.id}/${variant.name}';
    return _inflight[key] ??= _download(f, variant, onProgress).whenComplete(
      () {
        _inflight.remove(key);
      },
    );
  }

  Future<File> _download(
    FileInfo f,
    FileVariant variant,
    void Function(double)? onProgress,
  ) async {
    final dir = await _dir(f.id, variant);
    await dir.create(recursive: true);
    final target = File(
      '${dir.path}${Platform.pathSeparator}${safeFileName(f.name)}',
    );
    Object? last;
    for (final force in const [false, true]) {
      final info = await _info(f.id, force: force);
      final url = variant == FileVariant.thumb ? info.thumbUrl : info.url;
      if (url == null) throw const ApiException(ErrorCopy.downloadFailed);
      try {
        await _write(url, target, onProgress);
        unawaited(_trim());
        return target;
      } on _Refused catch (e) {
        last = e;
      }
    }
    throw ApiException(
      ErrorCopy.downloadFailed,
      status: last is _Refused ? last.status : null,
    );
  }

  Future<void> _write(
    String url,
    File target,
    void Function(double)? onProgress,
  ) async {
    final part = File('${target.path}.part');
    final client = _client();
    try {
      final r = await client
          .send(http.Request('GET', Uri.parse(url)))
          .timeout(AppFiles.requestTimeout);
      if (r.statusCode >= 400) throw _Refused(r.statusCode);
      final total = r.contentLength ?? 0;
      var got = 0;
      final sink = part.openWrite();
      try {
        await for (final chunk in r.stream) {
          sink.add(chunk);
          got += chunk.length;
          if (total > 0) onProgress?.call((got / total).clamp(0.0, 1.0));
        }
      } finally {
        await sink.close();
      }
      await part.rename(target.path);
      onProgress?.call(1);
    } catch (_) {
      if (part.existsSync()) part.deleteSync();
      rethrow;
    } finally {
      client.close();
    }
  }

  /// [file] inside the previews folder, copying it there when it lives
  /// elsewhere (a picked file): only that folder is shared with other apps.
  Future<File> staged(FileInfo f, File file) async {
    final root = (await _root()).absolute.path;
    if (file.absolute.path.startsWith('$root${Platform.pathSeparator}')) {
      return file;
    }
    final dir = Directory(
      '$root${Platform.pathSeparator}open${Platform.pathSeparator}${DateTime.now().microsecondsSinceEpoch}',
    );
    await dir.create(recursive: true);
    return file.copy(
      '${dir.path}${Platform.pathSeparator}${safeFileName(f.name)}',
    );
  }

  /// Forgets what is cached for one file (after it was deleted or renamed).
  Future<void> evict(String id) async {
    final root = await _root();
    final dir = Directory('${root.path}${Platform.pathSeparator}$id');
    if (dir.existsSync()) await dir.delete(recursive: true);
  }

  /// Deletes the least recently used files until the cache fits.
  Future<void> _trim() async {
    try {
      final root = await _root();
      if (!root.existsSync()) return;
      final files = [
        for (final e in root.listSync(recursive: true))
          if (e is File && !e.path.endsWith('.part')) e,
      ];
      var total = files.fold<int>(0, (n, f) => n + f.lengthSync());
      if (total <= PreviewConfig.cacheMaxBytes) return;
      files.sort(
        (a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()),
      );
      for (final f in files) {
        if (total <= PreviewConfig.cacheMaxBytes) break;
        total -= f.lengthSync();
        f.deleteSync();
      }
    } catch (_) {
      /* a cache that cannot trim is still a cache */
    }
  }
}

class _Refused implements Exception {
  const _Refused(this.status);
  final int status;
}
