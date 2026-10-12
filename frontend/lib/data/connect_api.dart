import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/constants/app_config.dart';
import '../core/constants/connectors.dart';
import 'api_client.dart';
import 'chat_api.dart';
import 'connections_api.dart';

/// A failed `/connect` call with the backend's error code.
class ConnectException extends ApiException {
  const ConnectException(
    super.message, {
    super.status,
    this.code,
    this.offline = false,
  });
  final String? code;

  /// No answer at all (no network, timeout).
  final bool offline;

  bool get notConfigured => code == ConnectorCodes.notConfigured;
  bool get notConnected => code == ConnectorCodes.notConnected;
  bool get needsReauth => code == ConnectorCodes.reauth;
  bool get rateLimited =>
      status == 429 ||
      code == ConnectorCodes.rateLimited ||
      code == ConnectorCodes.rateLimitedApp;
}

String _s(Object? v) => v is String ? v : '';
String? _sn(Object? v) => v is String && v.isNotEmpty ? v : null;
DateTime? _date(Object? v) =>
    v is String ? DateTime.tryParse(v)?.toLocal() : null;

/// A Drive file sparky can see (picked, or created by sparky).
class DriveFile {
  DriveFile(Map<String, dynamic> j)
    : id = _s(j['id']),
      name = _s(j['name']),
      mimeType = _s(j['mimeType']),
      modified = _date(j['modifiedTime']),
      size = (j['size'] as num?)?.toInt(),
      webViewLink = _sn(j['webViewLink']),
      owner = _sn(j['owner']),
      kind = _s(j['kind']);

  final String id, name, mimeType, kind;
  final DateTime? modified;
  final int? size;
  final String? webViewLink, owner;

  /// Readable as text (Docs, Sheets, PDFs, Office, plain text).
  bool get readable => kind.isNotEmpty && kind != 'none';
}

/// `GET /connect/google_drive/files/:id`.
class DriveContent {
  DriveContent(Map<String, dynamic> j)
    : file = DriveFile(j['file'] as Map<String, dynamic>? ?? const {}),
      format = _s(j['format']),
      text = _s(j['text']),
      truncated = j['truncated'] == true;

  final DriveFile file;

  /// markdown | csv | text | metadata
  final String format, text;
  final bool truncated;
}

/// A page or database shared with sparky in Notion.
class NotionItem {
  NotionItem(Map<String, dynamic> j)
    : id = _s(j['id']),
      object = _s(j['object']),
      title = _s(j['title']),
      url = _s(j['url']),
      icon = _sn(j['icon']),
      lastEdited = _date(j['lastEdited']);

  final String id, object, title, url;

  /// Emoji or an https image URL.
  final String? icon;
  final DateTime? lastEdited;

  bool get isDatabase => object == 'database';
  bool get iconIsImage => icon?.startsWith('https://') ?? false;
}

class NotionPage extends NotionItem {
  NotionPage(super.j)
    : markdown = _s(j['markdown']),
      truncated = j['truncated'] == true;

  final String markdown;
  final bool truncated;
}

/// `POST /connect/:provider/start` and the Drive picker.
class ConnectStart {
  ConnectStart(Map<String, dynamic> j)
    : url = _s(j['authorizeUrl'] ?? j['url']),
      state = _s(j['state']);
  final String url, state;
}

/// Google Drive and Notion over the backend (`/connect`). Tokens stay there.
class ConnectApi {
  ConnectApi();

  /// Swapped in tests.
  static ConnectApi instance = ConnectApi();

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, Object?>? body,
    Map<String, String>? query,
  }) async {
    final uri = Uri.parse(
      '${AppConfig.apiBaseUrl}/connect$path',
    ).replace(queryParameters: query == null || query.isEmpty ? null : query);
    final request = http.Request(method, uri)
      ..headers.addAll(apiHeaders(json: body != null));
    if (body != null) request.body = jsonEncode(body);
    final http.Response res;
    try {
      res = await http.Response.fromStream(
        await apiHttp.send(request).timeout(ConnectorDurations.request),
      );
    } on SocketException {
      throw const ConnectException(ConnectorStrings.offline, offline: true);
    } on TimeoutException {
      throw const ConnectException(ConnectorStrings.offline, offline: true);
    } on http.ClientException {
      throw const ConnectException(ConnectorStrings.offline, offline: true);
    }
    if (res.statusCode >= 400) {
      throw ConnectException(
        errorMessage(res.body, res.statusCode),
        status: res.statusCode,
        code: errorCode(res.body),
      );
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ---- connecting ----------------------------------------------------------

  Future<ConnectStart> start(String provider) async =>
      ConnectStart(await _send('POST', '/$provider/start', body: const {}));

  Future<Connection?> redeem(String provider, String ticket) async {
    final j = await _send(
      'POST',
      '/$provider/redeem',
      body: {'ticket': ticket},
    );
    final c = j['connection'];
    return c is Map<String, dynamic> ? Connection(c) : null;
  }

  Future<void> disconnect(String provider) => _send('DELETE', '/$provider');

  // ---- Google Drive ----------------------------------------------------------

  Future<ConnectStart> startPicker() async =>
      ConnectStart(await _send('POST', '/google_drive/picker', body: const {}));

  Future<List<DriveFile>> driveFiles({String query = ''}) async {
    final j = await _send(
      'GET',
      '/google_drive/files',
      query: {if (query.trim().isNotEmpty) 'q': query.trim()},
    );
    return [
      for (final f in (j['files'] as List? ?? const []))
        if (f is Map<String, dynamic>) DriveFile(f),
    ];
  }

  Future<DriveContent> driveRead(String id) async => DriveContent(
    await _send('GET', '/google_drive/files/${Uri.encodeComponent(id)}'),
  );

  Future<void> driveToKnowledge(String id) => _send(
    'POST',
    '/google_drive/files/${Uri.encodeComponent(id)}/knowledge',
    body: const {},
  );

  /// Saves a sparky doc ([docId]) or Markdown ([title] + [markdown]).
  Future<DriveFile> saveToDrive({
    String? docId,
    String? title,
    String? markdown,
  }) async {
    final j = await _send(
      'POST',
      '/google_drive/upload',
      body: docId != null
          ? {'docId': docId}
          : {'title': title, 'markdown': markdown},
    );
    return DriveFile(j['file'] as Map<String, dynamic>? ?? const {});
  }

  // ---- Notion ----------------------------------------------------------------

  Future<List<NotionItem>> notionSearch({
    String query = '',
    String? kind,
  }) async {
    final j = await _send(
      'GET',
      '/notion/search',
      query: {if (query.trim().isNotEmpty) 'q': query.trim(), 'kind': ?kind},
    );
    return [
      for (final i in (j['items'] as List? ?? const []))
        if (i is Map<String, dynamic>) NotionItem(i),
    ];
  }

  Future<NotionPage> notionRead(String id) async => NotionPage(
    await _send('GET', '/notion/pages/${Uri.encodeComponent(id)}'),
  );

  Future<void> notionToKnowledge(String id) => _send(
    'POST',
    '/notion/pages/${Uri.encodeComponent(id)}/knowledge',
    body: const {},
  );

  Future<NotionItem> saveToNotion({
    required String parentId,
    String? docId,
    String? title,
    String? markdown,
  }) async {
    final j = await _send(
      'POST',
      '/notion/pages',
      body: {
        'parentId': parentId,
        if (docId != null)
          'docId': docId
        else ...{
          'title': title,
          'markdown': markdown,
        },
      },
    );
    return NotionItem(j['page'] as Map<String, dynamic>? ?? const {});
  }
}
