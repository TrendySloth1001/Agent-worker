import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../core/constants/app_config.dart';
import '../core/constants/error_copy.dart';
import '../core/constants/app_files.dart';
import 'chat_api.dart';
import 'file_insight.dart';
import 'api_client.dart';
import 'connect_api.dart';
import 'drive_ref.dart';

enum FileKind { image, document, video, audio }

enum FileStatus { processing, ready, failed }

/// A file known to the server. Saved chats keep it without signed URLs.
class FileInfo {
  const FileInfo({
    required this.id,
    required this.name,
    this.mime = '',
    this.size = 0,
    this.kind = FileKind.document,
    this.status = FileStatus.processing,
    this.error,
    this.url,
    this.thumbUrl,
    this.meta = const {},
    this.localPath,
    this.deleted = false,
    this.createdAt,
    this.conversationId,
    this.conversationTitle,
  });

  final String id;
  final String name;
  final String mime;
  final int size;
  final FileKind kind;
  final FileStatus status;
  final String? error;
  final String? url;
  final String? thumbUrl;
  final Map<String, dynamic> meta;

  /// Picked file on this phone; never sent or saved. Shows a preview before
  /// the server URLs are fetched.
  final String? localPath;

  /// Removed from storage (Storage screen or another device). Saved chats
  /// keep the entry as a "file deleted" placeholder.
  final bool deleted;

  final DateTime? createdAt;

  /// The chat the file is attached in (GET /files only).
  final String? conversationId;
  final String? conversationTitle;

  int? get pages => _int(meta['pages']);
  int? get width => _int(meta['width']);
  int? get height => _int(meta['height']);
  double? get durationS {
    final v = meta['durationS'];
    return v is num && v > 0 ? v.toDouble() : null;
  }

  static int? _int(Object? v) => v is num && v > 0 ? v.round() : null;

  static FileKind _kind(Object? v) => FileKind.values.firstWhere(
    (k) => k.name == v,
    orElse: () => FileKind.document,
  );

  static FileStatus _status(Object? v) => FileStatus.values.firstWhere(
    (s) => s.name == v,
    orElse: () => FileStatus.processing,
  );

  /// Only the API's signed links (`/files/blob/…`) serve readable bytes:
  /// stored objects are encrypted, so a storage link saved by an older
  /// version is dropped and a fresh one is fetched by id.
  static String? _apiLink(Object? v) =>
      v is String && v.contains(AppFiles.blobPath) ? v : null;

  factory FileInfo.fromJson(Map<String, dynamic> j) {
    final conv = j['conversation'];
    return FileInfo(
      id: j['id']?.toString() ?? '',
      name: j['name'] as String? ?? '',
      mime: j['mime'] as String? ?? '',
      size: (j['size'] as num?)?.toInt() ?? 0,
      kind: _kind(j['kind']),
      status: _status(j['status']),
      // Kept non-null on failure; raw server text is never shown.
      error: switch (j['error']) {
        final String e => safeOr(e, ErrorCopy.fileFailed),
        _ => null,
      },
      url: _apiLink(j['url']),
      thumbUrl: _apiLink(j['thumbUrl']),
      meta: j['meta'] is Map<String, dynamic>
          ? j['meta'] as Map<String, dynamic>
          : const {},
      deleted: j['deleted'] == true || j['status'] == AppFiles.deletedStatus,
      createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '')?.toLocal(),
      conversationId: conv is Map ? conv['id']?.toString() : null,
      conversationTitle: conv is Map ? conv['title'] as String? : null,
    );
  }

  /// Saved form: no signed URLs, they expire.
  Map<String, dynamic> toStorageJson() => {
    'id': id,
    'name': name,
    'mime': mime,
    'size': size,
    'kind': kind.name,
    'status': status.name,
    'error': error,
    'meta': meta,
    if (deleted) 'deleted': true,
  };

  FileInfo withFresh(FileInfo fresh) => FileInfo(
    id: id,
    name: fresh.name.isEmpty ? name : fresh.name,
    mime: fresh.mime.isEmpty ? mime : fresh.mime,
    size: fresh.size == 0 ? size : fresh.size,
    kind: fresh.kind,
    status: fresh.status,
    error: fresh.error,
    url: fresh.url,
    thumbUrl: fresh.thumbUrl,
    meta: fresh.meta.isEmpty ? meta : fresh.meta,
    localPath: localPath,
    deleted: fresh.deleted,
    createdAt: fresh.createdAt ?? createdAt,
    conversationId: fresh.conversationId ?? conversationId,
    conversationTitle: fresh.conversationTitle ?? conversationTitle,
  );

  /// The placeholder kept once the file is gone from storage.
  FileInfo asDeleted() => FileInfo(
    id: id,
    name: name,
    mime: mime,
    size: size,
    kind: kind,
    status: status,
    meta: meta,
    deleted: true,
    createdAt: createdAt,
  );

  FileInfo renamed(String newName) => FileInfo(
    id: id,
    name: newName,
    mime: mime,
    size: size,
    kind: kind,
    status: status,
    error: error,
    url: url,
    thumbUrl: thumbUrl,
    meta: meta,
    localPath: localPath,
    deleted: deleted,
    createdAt: createdAt,
    conversationId: conversationId,
    conversationTitle: conversationTitle,
  );

  FileInfo withLocalPath(String? path) => FileInfo(
    id: id,
    name: name,
    mime: mime,
    size: size,
    kind: kind,
    status: status,
    error: error,
    url: url,
    thumbUrl: thumbUrl,
    meta: meta,
    localPath: path,
    deleted: deleted,
    createdAt: createdAt,
    conversationId: conversationId,
    conversationTitle: conversationTitle,
  );
}

/// Best guess at the type from the file name.
String mimeFor(String name) {
  final dot = name.lastIndexOf('.');
  final ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  return AppFiles.mimeByExtension[ext] ?? AppFiles.fallbackMime;
}

String extensionOf(String name) {
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
}

FileKind guessKind(String name) {
  final ext = extensionOf(name);
  if (AppFiles.imageExtensions.contains(ext)) return FileKind.image;
  if (AppFiles.videoExtensions.contains(ext)) return FileKind.video;
  if (AppFiles.audioExtensions.contains(ext)) return FileKind.audio;
  return FileKind.document;
}

int maxBytesFor(FileKind kind) => switch (kind) {
  FileKind.image => AppFiles.imageMax,
  FileKind.document => AppFiles.documentMax,
  FileKind.video => AppFiles.videoMax,
  FileKind.audio => AppFiles.audioMax,
};

/// Text of a file as returned by GET /files/:id/text.
class FileText {
  const FileText({
    required this.text,
    required this.truncated,
    required this.chars,
    this.offset = 0,
  });
  final String text;

  /// More text follows this page.
  final bool truncated;

  /// Characters in the whole text.
  final int chars;

  /// Where this page starts, in characters.
  final int offset;
}

/// Stops an upload in flight.
class UploadCancel {
  http.Client? _client;
  bool cancelled = false;
  void cancel() {
    cancelled = true;
    _client?.close();
  }
}

class FilesApi {
  FilesApi._();
  static final instance = FilesApi._();

  final _client = AuthClient();
  final _cache = <String, (DateTime, FileInfo)>{};

  /// Bumped after files are deleted or renamed, so open chats refresh
  /// their attachment tiles.
  final changes = ValueNotifier<int>(0);
  final _inflight = <String, Future<FileInfo>>{};

  Uri _uri(String path) => Uri.parse('${AppConfig.apiBaseUrl}$path');

  /// Forgets signed URLs; called on sign-out so no user sees another's files.
  void clearCache() {
    _cache.clear();
    _inflight.clear();
  }

  /// Multipart upload with byte progress (0..1).
  Future<FileInfo> upload(
    String path, {
    required String name,
    String? conversationId,
    void Function(double progress)? onProgress,
    UploadCancel? cancel,
  }) async {
    final file = File(path);
    final length = await file.length();
    final mp = http.MultipartRequest('POST', _uri('/files'))
      ..headers.addAll(apiHeaders())
      ..fields.addAll({'conversationId': ?conversationId})
      ..files.add(
        http.MultipartFile(
          'file',
          file.openRead(),
          length,
          filename: name,
          contentType: MediaType.parse(mimeFor(name)),
        ),
      );
    final body = mp.finalize();
    final total = mp.contentLength;
    final request = http.StreamedRequest('POST', mp.url)
      ..headers.addAll(mp.headers)
      ..contentLength = total;
    var sent = 0;
    // Note: no asFuture() here, it would replace the onDone handler.
    body.listen(
      (chunk) {
        request.sink.add(chunk);
        sent += chunk.length;
        onProgress?.call(total == 0 ? 0 : sent / total);
      },
      onError: request.sink.addError,
      onDone: request.sink.close,
      cancelOnError: true,
    );

    final client = AuthClient();
    cancel?._client = client;
    try {
      final streamed = await client
          .send(request)
          .timeout(AppFiles.uploadTimeout);
      final text = await streamed.stream.bytesToString();
      if (streamed.statusCode >= 400) {
        throw ApiException.fromResponse(text, streamed.statusCode);
      }
      final info = _parse(text);
      _cache[info.id] = (DateTime.now(), info);
      onProgress?.call(1);
      return info;
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException(ErrorCopy.uploadFailed);
    } finally {
      client.close();
    }
  }

  FileInfo _parse(String body) {
    final json = jsonDecode(body);
    final f = json is Map<String, dynamic> ? json['file'] : null;
    if (f is! Map<String, dynamic>) throw const ApiException(ErrorCopy.generic);
    return FileInfo.fromJson(f);
  }

  /// Fresh signed URLs; cached for most of an hour.
  Future<FileInfo> get(String id, {bool force = false}) {
    if (DriveRef.isDrive(id)) {
      // A Drive item is built by the Drive screens; its link is Google's.
      final known = DriveRef.known(id);
      return known == null
          ? Future.error(const ApiException(ErrorCopy.generic, status: 404))
          : Future.value(known);
    }
    final hit = _cache[id];
    // A file still processing gets its poster and duration later: refetch.
    if (!force &&
        hit != null &&
        DateTime.now().difference(hit.$1) < AppFiles.urlTtl &&
        hit.$2.url != null &&
        hit.$2.status != FileStatus.processing) {
      return Future.value(hit.$2);
    }
    return _inflight[id] ??= _fetch(id).whenComplete(() {
      _inflight.remove(id);
    });
  }

  Future<FileInfo> _fetch(String id) async {
    final response = await _client
        .get(_uri('/files/$id'), headers: apiHeaders())
        .timeout(AppFiles.requestTimeout);
    if (response.statusCode >= 400) {
      throw ApiException.fromResponse(response.body, response.statusCode);
    }
    final info = _parse(response.body);
    _cache[id] = (DateTime.now(), info);
    return info;
  }

  /// Extracted text (or transcript). Throws [ApiException] with status 404
  /// while the server has no text yet.
  Future<FileText> text(
    String id, {
    int limit = AppFiles.textPreviewLimit,
    int offset = 0,
  }) async {
    if (DriveRef.isDrive(id)) {
      return ConnectApi.instance.driveText(
        DriveRef.fileIdOf(id),
        offset: offset,
        limit: limit,
      );
    }
    final response = await _client
        .get(
          _uri('/files/$id/text?limit=$limit&offset=$offset'),
          headers: apiHeaders(),
        )
        .timeout(AppFiles.requestTimeout);
    if (response.statusCode >= 400) {
      throw ApiException.fromResponse(response.body, response.statusCode);
    }
    final j = jsonDecode(response.body);
    if (j is! Map<String, dynamic>) throw const ApiException(ErrorCopy.generic);
    return FileText(
      text: j['text'] as String? ?? '',
      truncated: j['truncated'] == true,
      chars: (j['chars'] as num?)?.toInt() ?? 0,
      offset: (j['offset'] as num?)?.toInt() ?? offset,
    );
  }

  /// What sparky understands about a file as stored (no model is called).
  Future<InsightData> insight(String id) async {
    if (DriveRef.isDrive(id)) {
      return ConnectApi.instance.driveInsight(DriveRef.fileIdOf(id));
    }
    final r = await _client
        .get(_uri('/files/$id/insight'), headers: apiHeaders())
        .timeout(AppFiles.requestTimeout);
    if (r.statusCode >= 400) _fail(r);
    return InsightData.fromJson(_object(r.body));
  }

  /// Has sparky read the file (summary, caption, frame descriptions) and
  /// keeps the result. Slow: a model is called.
  Future<InsightData> generateInsight(String id, {bool force = false}) async {
    if (DriveRef.isDrive(id)) {
      return ConnectApi.instance.driveGenerateInsight(
        DriveRef.fileIdOf(id),
        force: force,
      );
    }
    final r = await _client
        .post(
          _uri('/files/$id/insight'),
          headers: apiHeaders(json: true),
          body: jsonEncode({if (force) 'force': true}),
        )
        .timeout(AppFiles.insightTimeout);
    if (r.statusCode >= 400) _fail(r);
    return InsightData.fromJson(_object(r.body));
  }

  Map<String, dynamic> _object(String body) {
    final j = jsonDecode(body);
    if (j is! Map<String, dynamic>) throw const ApiException(ErrorCopy.generic);
    return j;
  }

  Never _fail(http.Response r) =>
      throw ApiException.fromResponse(r.body, r.statusCode);

  /// One page of the user's files (Storage screen).
  Future<FilePage> list({
    FileKind? kind,
    String query = '',
    StorageSort sort = StorageSort.newest,
    String? cursor,
  }) async {
    final uri = _uri('/files').replace(
      queryParameters: {
        'kind': ?kind?.name,
        if (query.trim().isNotEmpty) 'q': query.trim(),
        'sort': sort.name,
        'cursor': ?cursor,
        'limit': '${AppFiles.listPageSize}',
      },
    );
    final r = await _client
        .get(uri, headers: apiHeaders())
        .timeout(AppFiles.requestTimeout);
    if (r.statusCode >= 400) _fail(r);
    final j = jsonDecode(r.body);
    if (j is! Map<String, dynamic>) throw const ApiException(ErrorCopy.generic);
    final files = [
      for (final f in j['files'] as List? ?? const [])
        if (f is Map<String, dynamic>) FileInfo.fromJson(f),
    ];
    final now = DateTime.now();
    for (final f in files) {
      _cache[f.id] = (now, f);
    }
    return FilePage(files: files, nextCursor: j['nextCursor'] as String?);
  }

  /// Stored bytes per kind against the account limit (GET /files/usage).
  Future<StorageUsage> usage() async {
    final r = await _client
        .get(_uri('/files/usage'), headers: apiHeaders())
        .timeout(AppFiles.requestTimeout);
    if (r.statusCode >= 400) _fail(r);
    final j = jsonDecode(r.body);
    if (j is! Map<String, dynamic>) throw const ApiException(ErrorCopy.generic);
    return StorageUsage.fromJson(j);
  }

  /// Deletes several files; returns how many the server removed.
  Future<int> bulkDelete(List<String> ids) async {
    for (final id in ids) {
      _cache.remove(id);
    }
    final r = await _client
        .post(
          _uri('/files/bulk-delete'),
          headers: apiHeaders(json: true),
          body: jsonEncode({'ids': ids}),
        )
        .timeout(AppFiles.requestTimeout);
    if (r.statusCode >= 400) _fail(r);
    changes.value++;
    final j = jsonDecode(r.body);
    return j is Map<String, dynamic> ? (j['deleted'] as num?)?.toInt() ?? 0 : 0;
  }

  /// Renames a file (the server keeps its extension). Returns the new info.
  Future<FileInfo> rename(String id, String name) async {
    final r = await _client
        .patch(
          _uri('/files/$id'),
          headers: apiHeaders(json: true),
          body: jsonEncode({'name': name}),
        )
        .timeout(AppFiles.requestTimeout);
    if (r.statusCode >= 400) _fail(r);
    final info = _parse(r.body);
    _cache[id] = (DateTime.now(), info);
    changes.value++;
    return info;
  }

  /// Downloads the original into [dir] (fresh signed URL; no app token is
  /// sent to the storage host). Returns the written file.
  Future<File> download(FileInfo f, Directory dir) async {
    final local = f.localPath;
    final target = File(
      '${dir.path}${Platform.pathSeparator}${safeFileName(f.name)}',
    );
    if (local != null && File(local).existsSync()) {
      return File(local).copy(target.path);
    }
    final url = (await get(f.id)).url;
    if (url == null) throw const ApiException(ErrorCopy.downloadFailed);
    final client = http.Client();
    try {
      final r = await client
          .send(http.Request('GET', Uri.parse(url)))
          .timeout(AppFiles.requestTimeout);
      if (r.statusCode >= 400) {
        throw ApiException(ErrorCopy.downloadFailed, status: r.statusCode);
      }
      final sink = target.openWrite();
      await r.stream.pipe(sink);
      return target;
    } finally {
      client.close();
    }
  }

  Future<void> delete(String id) async {
    _cache.remove(id);
    final response = await _client
        .delete(_uri('/files/$id'), headers: apiHeaders())
        .timeout(AppFiles.requestTimeout);
    if (response.statusCode >= 400 && response.statusCode != 404) {
      throw ApiException.fromResponse(response.body, response.statusCode);
    }
    changes.value++;
  }
}

/// Sort orders of GET /files (names match the server).
enum StorageSort { newest, largest, name }

class FilePage {
  const FilePage({required this.files, this.nextCursor});
  final List<FileInfo> files;
  final String? nextCursor;
}

/// GET /files/usage. [limitBytes] / [uploadsPerDay] are null when unlimited.
class StorageUsage {
  const StorageUsage({
    required this.totalBytes,
    required this.count,
    required this.byKind,
    this.limitBytes,
    this.uploadsPerDay,
    this.uploadsToday = 0,
    this.bytesToday = 0,
  });

  final int totalBytes;
  final int count;
  final Map<FileKind, ({int count, int bytes})> byKind;
  final int? limitBytes;
  final int? uploadsPerDay;
  final int uploadsToday;
  final int bytesToday;

  double get fraction {
    final l = limitBytes;
    return l == null || l <= 0 ? 0 : (totalBytes / l).clamp(0.0, 1.0);
  }

  bool get full => limitBytes != null && totalBytes >= limitBytes!;

  static int _n(Object? v) => (v as num?)?.toInt() ?? 0;

  factory StorageUsage.fromJson(Map<String, dynamic> j) {
    final kinds = j['byKind'] is Map ? j['byKind'] as Map : const {};
    final limits = j['limits'] is Map ? j['limits'] as Map : const {};
    final today = j['today'] is Map ? j['today'] as Map : const {};
    return StorageUsage(
      totalBytes: _n(j['totalBytes']),
      count: _n(j['count']),
      byKind: {
        for (final k in FileKind.values)
          k: (
            count: _n((kinds[k.name] as Map?)?['count']),
            bytes: _n((kinds[k.name] as Map?)?['bytes']),
          ),
      },
      limitBytes: (limits['storageBytes'] as num?)?.toInt(),
      uploadsPerDay: (limits['uploadsPerDay'] as num?)?.toInt(),
      uploadsToday: _n(today['uploads']),
      bytesToday: _n(today['bytes']),
    );
  }
}

/// A file name safe to write on the phone (no path parts or reserved marks).
String safeFileName(String name) {
  final cleaned = name
      .split(RegExp(r'[\\/]'))
      .last
      .replaceAll(RegExp(r'[\x00-\x1f<>:"|?*]'), '_')
      .trim();
  return cleaned.isEmpty || cleaned == '.' || cleaned == '..'
      ? AppFiles.fallbackName
      : cleaned;
}
