import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../constants/update.dart';
import 'update_models.dart';

/// The download did not match the checksum the server announced.
class UpdateVerifyException implements Exception {
  const UpdateVerifyException();
}

/// Streams an APK into the cache folder and checks its SHA-256.
class UpdateDownloader {
  UpdateDownloader({http.Client? client, Future<Directory> Function()? dir})
    : _client = client ?? http.Client(),
      _dir = dir ?? _cacheDir;

  final http.Client _client;
  final Future<Directory> Function() _dir;

  static Future<Directory> _cacheDir() async {
    final base = await getTemporaryDirectory();
    return Directory('${base.path}/${UpdateConfig.dirName}');
  }

  /// Path the APK of [r] is stored at.
  Future<String> pathFor(UpdateRelease r) async {
    final dir = await _dir();
    return '${dir.path}/sparky-${r.version}-${r.build}.apk';
  }

  /// True when the file at [path] is a complete download of [r].
  Future<bool> isComplete(UpdateRelease r, String path) async {
    final f = File(path);
    return await f.exists() && (r.size <= 0 || await f.length() == r.size);
  }

  /// Downloads [r] and verifies it. Throws [UpdateVerifyException] when the
  /// checksum differs (the file is deleted), anything else on network errors.
  Future<String> download(
    UpdateRelease r, {
    required void Function(double progress) onProgress,
  }) async {
    final dir = await _dir();
    await dir.create(recursive: true);
    final target = await pathFor(r);
    await _clean(dir, keep: target);
    final part = File('$target.part');
    final response = await _client.send(
      http.Request('GET', Uri.parse(r.url)),
    );
    if (response.statusCode != 200) {
      await response.stream.drain<void>().catchError((_) {});
      throw HttpException('download failed: ${response.statusCode}');
    }
    final total = r.size > 0 ? r.size : (response.contentLength ?? 0);
    final out = _DigestSink();
    final hash = sha256.startChunkedConversion(out);
    final sink = part.openWrite();
    var got = 0;
    var last = 0.0;
    try {
      await for (final chunk in response.stream.timeout(
        UpdateConfig.downloadStall,
      )) {
        sink.add(chunk);
        hash.add(chunk);
        got += chunk.length;
        if (total > 0) {
          final p = (got / total).clamp(0.0, 1.0);
          if (p - last >= UpdateConfig.progressStep || p == 1.0) {
            last = p;
            onProgress(p);
          }
        }
      }
      await sink.flush();
      await sink.close();
      hash.close();
    } catch (_) {
      await sink.close().catchError((_) {});
      await _delete(part);
      rethrow;
    }
    final digest = out.value.toString();
    if (r.sha256.isNotEmpty && digest != r.sha256.toLowerCase()) {
      await _delete(part);
      throw const UpdateVerifyException();
    }
    await part.rename(target);
    onProgress(1);
    return target;
  }

  /// Removes every APK in the folder except [keep].
  Future<void> _clean(Directory dir, {String? keep}) async {
    try {
      await for (final e in dir.list()) {
        if (e is File && e.path != keep) await _delete(e);
      }
    } catch (_) {
      // Best effort: stale files only cost disk space.
    }
  }

  /// Drops every downloaded APK (after a successful update, or on demand).
  Future<void> clear() async => _clean(await _dir());

  Future<void> _delete(File f) async {
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}

/// Receives the one digest a chunked hash produces.
class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
