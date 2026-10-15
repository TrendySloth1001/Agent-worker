import 'dart:io';
import 'dart:typed_data';

import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/file_cache.dart';
import 'package:app/data/files_api.dart';
import 'package:app/features/chat/preview/image_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// A fake of the API's file links, as the real server answers them:
/// `/files/blob/<id>/original` serves the decrypted bytes with the same
/// headers as routes/blob.ts; `/s3/<id>` is a storage link, which now holds
/// ciphertext (`SPKYENC1` header); `/expired/...` is a refused signature.
class _Server {
  _Server._(this.http, this.files);

  final HttpServer http;
  final Map<String, ({String mime, Uint8List bytes})> files;
  final hits = <String>[];

  static Future<_Server> start(
    Map<String, ({String mime, Uint8List bytes})> files,
  ) async {
    final http = await HttpServer.bind('127.0.0.1', 0);
    final s = _Server._(http, files);
    http.listen(s._handle);
    return s;
  }

  String get base => 'http://127.0.0.1:${http.port}';
  String blob(String id) => '$base/files/blob/$id/original?exp=9&sig=ab';
  String s3(String id) => '$base/s3/$id?X-Amz-Signature=abc';
  String expired(String id) => '$base/expired/$id';

  void _handle(HttpRequest req) {
    hits.add(req.uri.path);
    final parts = req.uri.pathSegments;
    final res = req.response;
    if (parts.first == 'expired') {
      res.statusCode = 404;
      res.close();
      return;
    }
    final id = parts.first == 'files' ? parts[2] : parts[1];
    final file = files[id];
    if (file == null) {
      res.statusCode = 404;
      res.close();
      return;
    }
    Uint8List body = file.bytes;
    if (parts.first == 's3') {
      body = Uint8List.fromList([
        ...'SPKYENC1'.codeUnits,
        ...List.filled(64, 7),
      ]);
    }
    res.headers
      ..set('Content-Type', file.mime)
      ..set('Accept-Ranges', 'bytes')
      ..set('Cache-Control', 'private, max-age=300')
      ..set('X-Content-Type-Options', 'nosniff')
      ..set('Content-Security-Policy', "default-src 'none'; sandbox")
      ..set('Content-Disposition', "inline; filename*=UTF-8''${file.mime}")
      ..set('Content-Length', '${body.length}');
    res.add(body);
    res.close();
  }

  Future<void> close() => http.close(force: true);
}

Uint8List _png() {
  final image = img.Image(width: 64, height: 40);
  for (final p in image) {
    p.setRgb(p.x * 4, p.y * 6, 120);
  }
  return Uint8List.fromList(img.encodePng(image));
}

final _pdf = Uint8List.fromList(
  '%PDF-1.4\n1 0 obj<</Type/Catalog>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF'
      .codeUnits,
);
final _doc = Uint8List.fromList(
  'Quarterly notes\n\nRevenue grew 12%.'.codeUnits,
);

late Directory _dir;
late _Server _server;

FileCache _cache(FileInfo Function(String id, bool force) info) => FileCache(
  root: () async => Directory('${_dir.path}/cache'),
  info: (id, {force = false}) async => info(id, force),
);

void main() {
  setUp(() async {
    // The test binding blocks real HTTP; these tests talk to a local server.
    HttpOverrides.global = null;
    _dir = Directory.systemTemp.createTempSync('preview_server');
    _server = await _Server.start({
      'img': (mime: 'image/png', bytes: _png()),
      'pdf': (mime: 'application/pdf', bytes: _pdf),
      'doc': (mime: 'text/plain', bytes: _doc),
    });
  });
  tearDown(() async {
    await _server.close();
    _dir.deleteSync(recursive: true);
  });

  group('FileCache against the API file links', () {
    for (final (id, name, kind, bytes) in [
      ('img', 'photo.png', FileKind.image, _png()),
      ('pdf', 'plan.pdf', FileKind.document, _pdf),
      ('doc', 'notes.txt', FileKind.document, _doc),
    ]) {
      test('$name downloads whole and byte for byte', () async {
        final file = FileInfo(id: id, name: name, kind: kind);
        final cache = _cache(
          (i, force) =>
              FileInfo(id: i, name: name, kind: kind, url: _server.blob(i)),
        );
        final got = await cache.fetch(file);
        expect(got.readAsBytesSync(), bytes);
        // Opening it again does not touch the network.
        _server.hits.clear();
        await cache.fetch(file);
        expect(_server.hits, isEmpty);
      });
    }

    test('an expired link is refreshed once with a new signature', () async {
      final forced = <bool>[];
      final cache = _cache((i, force) {
        forced.add(force);
        return FileInfo(
          id: i,
          name: 'photo.png',
          url: force ? _server.blob(i) : _server.expired(i),
        );
      });
      final got = await cache.fetch(
        const FileInfo(id: 'img', name: 'photo.png'),
      );
      expect(got.lengthSync(), _png().length);
      expect(forced, [false, true]);
    });

    test('a link that stays refused fails with a download error', () async {
      final cache = _cache(
        (i, force) =>
            FileInfo(id: i, name: 'photo.png', url: _server.expired(i)),
      );
      await expectLater(
        cache.fetch(const FileInfo(id: 'img', name: 'photo.png')),
        throwsA(isA<Object>()),
      );
      expect(
        File('${_dir.path}/cache/img/original/photo.png.part').existsSync(),
        isFalse,
      );
    });
  });

  group('old stored links (regression: previews opened ciphertext)', () {
    test('a storage link saved in a chat is dropped when it is read', () {
      final f = FileInfo.fromJson({
        'id': 'img',
        'name': 'photo.png',
        'kind': 'image',
        'url': _server.s3('img'),
        'thumbUrl': _server.s3('img'),
      });
      expect(f.url, isNull);
      expect(f.thumbUrl, isNull);
      final fresh = FileInfo.fromJson({
        'id': 'img',
        'name': 'photo.png',
        'kind': 'image',
        'url': _server.blob('img'),
      });
      expect(fresh.url, _server.blob('img'));
    });

    test('ciphertext from a storage link is never kept as the file', () async {
      final cache = _cache(
        (i, force) => FileInfo(id: i, name: 'photo.png', url: _server.s3(i)),
      );
      await expectLater(
        cache.fetch(const FileInfo(id: 'img', name: 'photo.png')),
        throwsA(isA<Object>()),
      );
      expect(
        await cache.cached(const FileInfo(id: 'img', name: 'photo.png')),
        isNull,
      );
    });

    test(
      'a cached copy that is ciphertext is thrown away and fetched again',
      () async {
        final poisoned = File('${_dir.path}/cache/img/original/photo.png')
          ..createSync(recursive: true)
          ..writeAsBytesSync([...'SPKYENC1'.codeUnits, ...List.filled(40, 1)]);
        expect(poisoned.existsSync(), isTrue);
        final cache = _cache(
          (i, force) =>
              FileInfo(id: i, name: 'photo.png', url: _server.blob(i)),
        );
        final got = await cache.fetch(
          const FileInfo(id: 'img', name: 'photo.png'),
        );
        expect(got.readAsBytesSync(), _png());
      },
    );
  });

  testWidgets('the image viewer shows a picture downloaded from the API link', (
    tester,
  ) async {
    FileCache.instance = _cache(
      (i, force) => FileInfo(
        id: i,
        name: 'photo.png',
        kind: FileKind.image,
        url: _server.blob(i),
      ),
    );
    const f = FileInfo(id: 'img', name: 'photo.png', kind: FileKind.image);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const FileImageViewer(files: [f], initial: 0),
      ),
    );
    for (var i = 0; i < 40 && find.byType(Image).evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(Image), findsOneWidget);
    final cached = await tester.runAsync(() => FileCache.instance.cached(f));
    expect(cached!.lengthSync(), _png().length);
  });
}
