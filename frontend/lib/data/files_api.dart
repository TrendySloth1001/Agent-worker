import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../core/constants/app_config.dart';
import '../core/constants/app_files.dart';
import 'chat_api.dart';
import 'api_client.dart';

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

  factory FileInfo.fromJson(Map<String, dynamic> j) => FileInfo(
    id: j['id']?.toString() ?? '',
    name: j['name'] as String? ?? '',
    mime: j['mime'] as String? ?? '',
    size: (j['size'] as num?)?.toInt() ?? 0,
    kind: _kind(j['kind']),
    status: _status(j['status']),
    error: j['error'] as String?,
    url: j['url'] as String?,
    thumbUrl: j['thumbUrl'] as String?,
    meta: j['meta'] is Map<String, dynamic>
        ? j['meta'] as Map<String, dynamic>
        : const {},
  );

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
  });
  final String text;
  final bool truncated;
  final int chars;
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
        final message = errorMessage(text, streamed.statusCode);
        throw ApiException(
          streamed.statusCode == 429 && errorCode(text) == 'daily_limit'
              ? dailyLimitMessage(message)
              : message,
          status: streamed.statusCode,
        );
      }
      final info = _parse(text);
      _cache[info.id] = (DateTime.now(), info);
      onProgress?.call(1);
      return info;
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException('Upload failed');
    } finally {
      client.close();
    }
  }

  FileInfo _parse(String body) {
    final json = jsonDecode(body);
    final f = json is Map<String, dynamic> ? json['file'] : null;
    if (f is! Map<String, dynamic>) throw const ApiException('Bad response');
    return FileInfo.fromJson(f);
  }

  /// Fresh signed URLs; cached for most of an hour.
  Future<FileInfo> get(String id, {bool force = false}) {
    final hit = _cache[id];
    if (!force &&
        hit != null &&
        DateTime.now().difference(hit.$1) < AppFiles.urlTtl &&
        hit.$2.url != null) {
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
      throw ApiException(
        errorMessage(response.body, response.statusCode),
        status: response.statusCode,
      );
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
  }) async {
    final response = await _client
        .get(_uri('/files/$id/text?limit=$limit'), headers: apiHeaders())
        .timeout(AppFiles.requestTimeout);
    if (response.statusCode >= 400) {
      throw ApiException(
        errorMessage(response.body, response.statusCode),
        status: response.statusCode,
      );
    }
    final j = jsonDecode(response.body);
    if (j is! Map<String, dynamic>) throw const ApiException('Bad response');
    return FileText(
      text: j['text'] as String? ?? '',
      truncated: j['truncated'] == true,
      chars: (j['chars'] as num?)?.toInt() ?? 0,
    );
  }

  Future<void> delete(String id) async {
    _cache.remove(id);
    final response = await _client
        .delete(_uri('/files/$id'), headers: apiHeaders())
        .timeout(AppFiles.requestTimeout);
    if (response.statusCode >= 400 && response.statusCode != 404) {
      throw ApiException(
        errorMessage(response.body, response.statusCode),
        status: response.statusCode,
      );
    }
  }
}
