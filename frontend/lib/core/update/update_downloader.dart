import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/update.dart';
import 'update_models.dart';

/// The download did not match the checksum the server announced.
class UpdateVerifyException implements Exception {
  const UpdateVerifyException();
}

/// What is remembered about the `.part` file between attempts and launches.
class PartialState {
  const PartialState({
    required this.build,
    required this.sha256,
    required this.etag,
    required this.url,
    required this.urlAt,
  });

  final int build;
  final String sha256;

  /// Validator for `If-Range`; null until a response named one.
  final String? etag;

  /// The presigned link in use and when it was issued.
  final String url;
  final DateTime urlAt;

  PartialState copyWith({String? etag, String? url, DateTime? urlAt}) =>
      PartialState(
        build: build,
        sha256: sha256,
        etag: etag ?? this.etag,
        url: url ?? this.url,
        urlAt: urlAt ?? this.urlAt,
      );

  String encode() => jsonEncode({
    'build': build,
    'sha256': sha256,
    'etag': etag,
    'url': url,
    'urlAt': urlAt.millisecondsSinceEpoch,
  });

  static PartialState? decode(String? raw) {
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return PartialState(
        build: (j['build'] as num).toInt(),
        sha256: j['sha256'] as String,
        etag: j['etag'] as String?,
        url: j['url'] as String,
        urlAt: DateTime.fromMillisecondsSinceEpoch((j['urlAt'] as num).toInt()),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Where [PartialState] lives (preferences in the app, memory in tests).
abstract class PartialStore {
  Future<PartialState?> load();
  Future<void> save(PartialState? state);
}

class PrefsPartialStore implements PartialStore {
  @override
  Future<PartialState?> load() async => PartialState.decode(
    (await SharedPreferences.getInstance()).getString(UpdatePrefs.partial),
  );

  @override
  Future<void> save(PartialState? state) async {
    final p = await SharedPreferences.getInstance();
    if (state == null) {
      await p.remove(UpdatePrefs.partial);
    } else {
      await p.setString(UpdatePrefs.partial, state.encode());
    }
  }
}

/// Streams an APK into the cache folder and checks its SHA-256.
///
/// Downloads resume: the `.part` file is kept across network errors, app
/// restarts and expired links. A resume sends `Range` with `If-Range: <etag>`;
/// only a `206` whose `Content-Range` starts where the file ends is appended
/// to, anything else starts over. The kept prefix is hashed again, so the
/// final SHA-256 always covers every byte on disk.
class UpdateDownloader {
  UpdateDownloader({
    http.Client? client,
    Future<Directory> Function()? dir,
    PartialStore? store,
    DateTime Function()? clock,
    Future<void> Function(Duration)? delay,
    List<Duration>? backoff,
  }) : _client = client ?? http.Client(),
       _dir = dir ?? _cacheDir,
       _store = store ?? PrefsPartialStore(),
       _clock = clock ?? DateTime.now,
       _delay = delay ?? Future<void>.delayed,
       _backoff = backoff ?? UpdateConfig.retryBackoff;

  final http.Client _client;
  final Future<Directory> Function() _dir;
  final PartialStore _store;
  final DateTime Function() _clock;
  final Future<void> Function(Duration) _delay;
  final List<Duration> _backoff;

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
  /// checksum differs (the file is deleted), anything else when the network
  /// keeps failing (the partial file is kept for the next try).
  ///
  /// [refreshUrl] returns a fresh link for the same build (or null); it is
  /// asked when the link is older than [UpdateConfig.urlMaxAge] or the
  /// storage answers 403. [onResume] is told the byte offset when an earlier
  /// partial download is continued.
  Future<String> download(
    UpdateRelease r, {
    required void Function(double progress) onProgress,
    Future<String?> Function()? refreshUrl,
    void Function(int offset)? onResume,
  }) async {
    final dir = await _dir();
    await dir.create(recursive: true);
    final target = await pathFor(r);
    final part = File('$target.part');
    await _clean(dir, keep: {target, part.path});

    var state = await _store.load();
    if (state == null || state.build != r.build || state.sha256 != r.sha256) {
      state = null;
      await _delete(part);
    }
    var url = r.url;
    var urlAt = state != null && state.url == r.url ? state.urlAt : _clock();
    String? etag = state?.etag;

    var retries = 0;
    var restarts = 0;
    var refreshedFor403 = false;
    var reported = false;
    while (true) {
      if (refreshUrl != null &&
          _clock().difference(urlAt) > UpdateConfig.urlMaxAge) {
        final fresh = await _refresh(refreshUrl);
        if (fresh != null) {
          url = fresh;
          urlAt = _clock();
        }
      }
      var offset = await part.exists() ? await part.length() : 0;
      if (offset > 0 && (etag == null || (r.size > 0 && offset > r.size))) {
        await _delete(part);
        offset = 0;
        etag = null;
      }
      if (offset > 0 && !reported) {
        reported = true;
        onResume?.call(offset);
      }
      try {
        final fetched = r.size > 0 && offset == r.size
            ? (digest: await _hashFile(part), etag: etag)
            : await _fetch(
                r,
                url: url,
                part: part,
                offset: offset,
                etag: etag,
                onProgress: onProgress,
                onEtag: (e) async {
                  etag = e;
                  await _store.save(
                    PartialState(
                      build: r.build,
                      sha256: r.sha256,
                      etag: e,
                      url: url,
                      urlAt: urlAt,
                    ),
                  );
                },
              );
        etag = fetched.etag ?? etag;
        if (r.sha256.isNotEmpty && fetched.digest != r.sha256.toLowerCase()) {
          await _delete(part);
          await _store.save(null);
          throw const UpdateVerifyException();
        }
        await part.rename(target);
        await _store.save(null);
        onProgress(1);
        return target;
      } on _Restart {
        // The partial cannot be continued (range refused, validator changed).
        await _delete(part);
        etag = null;
        if (++restarts > 3) {
          throw const HttpException('download keeps restarting');
        }
      } on _Forbidden {
        final fresh = refreshedFor403 || refreshUrl == null
            ? null
            : await _refresh(refreshUrl);
        refreshedFor403 = true;
        if (fresh == null) {
          throw const HttpException('download link refused (403)');
        }
        url = fresh;
        urlAt = _clock();
        refreshedFor403 = false;
        if (++restarts > 3) {
          throw const HttpException('download link keeps expiring');
        }
      } on _Fatal catch (e) {
        await _delete(part);
        await _store.save(null);
        throw HttpException(e.message);
      } on UpdateVerifyException {
        rethrow;
      } catch (_) {
        // Network trouble: keep the partial file and try again after a pause.
        if (retries >= _backoff.length) rethrow;
        await _delay(_backoff[retries++]);
      }
    }
  }

  Future<String?> _refresh(Future<String?> Function() refresh) async {
    try {
      final u = await refresh();
      return u != null && u.isNotEmpty ? u : null;
    } catch (_) {
      return null;
    }
  }

  /// One request. Appends to [part] (or rewrites it on a plain 200) and
  /// returns the SHA-256 of the whole file plus the validator seen.
  Future<({String digest, String? etag})> _fetch(
    UpdateRelease r, {
    required String url,
    required File part,
    required int offset,
    required String? etag,
    required void Function(double) onProgress,
    required Future<void> Function(String?) onEtag,
  }) async {
    final req = http.Request('GET', Uri.parse(url));
    if (offset > 0) {
      req.headers['Range'] = 'bytes=$offset-';
      req.headers['If-Range'] = etag!;
    }
    final response = await _client.send(req);
    final code = response.statusCode;
    if (code == 416) {
      await response.stream.drain<void>().catchError((_) {});
      throw _Restart();
    }
    if (code == 403) {
      await response.stream.drain<void>().catchError((_) {});
      throw _Forbidden();
    }
    if (code != 200 && code != 206) {
      await response.stream.drain<void>().catchError((_) {});
      if (code >= 500 || code == 408 || code == 429) {
        throw HttpException('download failed: $code');
      }
      throw _Fatal('download failed: $code');
    }
    var start = offset;
    if (code == 206) {
      if (offset == 0 ||
          !_rangeOk(response.headers['content-range'], offset, r.size)) {
        await response.stream.drain<void>().catchError((_) {});
        throw _Restart();
      }
    } else {
      // 200: no range honoured (or the file changed): a fresh full body.
      start = 0;
    }
    final newEtag = response.headers['etag'] ?? etag;
    if (newEtag != etag || start == 0) await onEtag(newEtag);

    final out = _DigestSink();
    final hash = sha256.startChunkedConversion(out);
    if (start > 0) {
      await for (final chunk in part.openRead(0, start)) {
        hash.add(chunk);
      }
    }
    final total = r.size > 0 ? r.size : start + (response.contentLength ?? 0);
    final sink = part.openWrite(
      mode: start > 0 ? FileMode.append : FileMode.write,
    );
    var got = start;
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
    } finally {
      await sink.close().catchError((_) {});
    }
    if (r.size > 0 && got != r.size) {
      throw HttpException('download ended early ($got of ${r.size} bytes)');
    }
    hash.close();
    return (digest: out.value.toString(), etag: newEtag);
  }

  Future<String> _hashFile(File f) async =>
      (await sha256.bind(f.openRead()).first).toString();

  /// `bytes <start>-<end>/<total>` must start at [offset] (and match [size]).
  static bool _rangeOk(String? header, int offset, int size) {
    if (header == null) return false;
    final m = RegExp(r'^bytes (\d+)-(\d+)/(\d+|\*)$').firstMatch(header.trim());
    if (m == null) return false;
    if (int.parse(m.group(1)!) != offset) return false;
    final total = m.group(3)!;
    if (size > 0 && total != '*' && int.parse(total) != size) return false;
    return true;
  }

  /// Removes every file in the folder except those in [keep].
  Future<void> _clean(Directory dir, {Set<String> keep = const {}}) async {
    try {
      await for (final e in dir.list()) {
        if (e is File && !keep.contains(e.path)) await _delete(e);
      }
    } catch (_) {
      // Best effort: stale files only cost disk space.
    }
  }

  /// Drops every downloaded APK (after a successful update, or on demand).
  Future<void> clear() async {
    await _clean(await _dir());
    await _store.save(null);
  }

  Future<void> _delete(File f) async {
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}

/// The partial file cannot be continued: start over from byte 0.
class _Restart implements Exception {}

/// The presigned link was refused (expired).
class _Forbidden implements Exception {}

/// A response that retrying will not fix.
class _Fatal implements Exception {
  _Fatal(this.message);
  final String message;
}

/// Receives the one digest a chunked hash produces.
class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
