import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:app/core/update/update_downloader.dart';
import 'package:app/core/update/update_models.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _MemStore implements PartialStore {
  PartialState? state;

  @override
  Future<PartialState?> load() async => state;

  @override
  Future<void> save(PartialState? s) async => state = s;
}

/// A scripted object store: serves [body] with Range / If-Range semantics
/// like S3, with hooks to break it.
class _Server {
  _Server(this.body);

  Uint8List body;
  String etag = '"v1"';
  final requests = <http.BaseRequest>[];

  /// Called per request; return a response to override the default.
  http.StreamedResponse? Function(http.BaseRequest req, int n)? script;

  /// Break the stream after this many bytes of the n-th response.
  final cutAfter = <int, int>{};

  http.StreamedResponse _ok(Stream<List<int>> s, int code, Map<String, String> h) =>
      http.StreamedResponse(s, code, headers: h);

  Future<http.StreamedResponse> handle(http.BaseRequest req) async {
    requests.add(req);
    final n = requests.length;
    final custom = script?.call(req, n);
    if (custom != null) return custom;
    final range = req.headers['Range'];
    final ifRange = req.headers['If-Range'];
    var start = 0;
    var code = 200;
    final headers = {'etag': etag};
    if (range != null && (ifRange == null || ifRange == etag)) {
      start = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
      if (start >= body.length) {
        return _ok(const Stream.empty(), 416, {'etag': etag});
      }
      code = 206;
      headers['content-range'] = 'bytes $start-${body.length - 1}/${body.length}';
    }
    final data = body.sublist(start);
    final cut = cutAfter[n];
    Stream<List<int>> stream;
    if (cut != null) {
      stream = () async* {
        yield data.sublist(0, cut);
        throw const SocketException('connection reset');
      }();
    } else {
      stream = Stream.value(data);
    }
    return _ok(stream, code, headers);
  }
}

Uint8List _bytes(int n) => Uint8List.fromList([for (var i = 0; i < n; i++) (i * 7 + 3) % 251]);

UpdateRelease _release(Uint8List b, {String url = 'https://files.example/a.apk'}) => UpdateRelease(
  version: '1.0.0',
  build: 7,
  kind: UpdateKind.patch,
  size: b.length,
  sha256: sha256.convert(b).toString(),
  url: url,
);

void main() {
  late Directory tmp;
  late _MemStore store;
  late List<Duration> waits;
  late DateTime now;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('dl_test');
    store = _MemStore();
    waits = [];
    now = DateTime(2026, 10, 14, 12);
  });
  tearDown(() async => tmp.delete(recursive: true));

  UpdateDownloader make(_Server s) => UpdateDownloader(
    client: MockClient.streaming((req, _) => s.handle(req)),
    dir: () async => tmp,
    store: store,
    clock: () => now,
    delay: (d) async => waits.add(d),
  );

  Future<String> run(UpdateDownloader d, UpdateRelease r, {Future<String?> Function()? refresh, void Function(int)? onResume}) =>
      d.download(r, onProgress: (_) {}, refreshUrl: refresh, onResume: onResume);

  test('a clean download is verified and renamed, no Range sent', () async {
    final b = _bytes(5000);
    final s = _Server(b);
    final path = await run(make(s), _release(b));
    expect(File(path).readAsBytesSync(), b);
    expect(File('$path.part').existsSync(), isFalse);
    expect(s.requests.single.headers.containsKey('Range'), isFalse);
    expect(store.state, isNull);
  });

  test('a dropped connection resumes with Range + If-Range and finishes', () async {
    final b = _bytes(6000);
    final s = _Server(b)..cutAfter[1] = 2500;
    int? resumedAt;
    final path = await run(make(s), _release(b), onResume: (o) => resumedAt = o);
    expect(File(path).readAsBytesSync(), b);
    expect(s.requests, hasLength(2));
    expect(s.requests[1].headers['Range'], 'bytes=2500-');
    expect(s.requests[1].headers['If-Range'], '"v1"');
    expect(waits, [const Duration(seconds: 2)]);
    expect(resumedAt, 2500);
  });

  test('the partial survives a failure and a new downloader resumes it', () async {
    final b = _bytes(6000);
    final s = _Server(b)..cutAfter[1] = 4000;
    // Every retry is cut off too: give up after the backoff list.
    for (var i = 2; i <= 7; i++) {
      s.cutAfter[i] = 0;
    }
    await expectLater(run(make(s), _release(b)), throwsA(isA<SocketException>()));
    expect(waits, [2, 4, 8, 16, 32].map((x) => Duration(seconds: x)).toList());
    final part = File('${tmp.path}/sparky-1.0.0-7.apk.part');
    expect(part.lengthSync(), 4000, reason: 'kept, not deleted');
    expect(store.state?.etag, '"v1"');

    // "App restart": a fresh downloader and a healthy server.
    final s2 = _Server(b);
    int? resumedAt;
    final path = await run(make(s2), _release(b), onResume: (o) => resumedAt = o);
    expect(resumedAt, 4000);
    expect(s2.requests.single.headers['Range'], 'bytes=4000-');
    expect(File(path).readAsBytesSync(), b);
  });

  test('the file changed (ETag differs): server answers 200, download restarts cleanly', () async {
    final b = _bytes(4000);
    final s = _Server(b)..cutAfter[1] = 1500;
    final d = make(s);
    // After the cut, the object is replaced by a different file with the same hash target.
    s.script = (req, n) {
      if (n == 2) s.etag = '"v2"'; // If-Range no longer matches -> plain 200
      return null;
    };
    final path = await run(d, _release(b));
    expect(File(path).readAsBytesSync(), b);
    expect(s.requests[1].headers['Range'], 'bytes=1500-');
    expect(s.requests[1].headers['If-Range'], '"v1"');
    expect(store.state, isNull);
  });

  test('416 on resume wipes the partial and starts over', () async {
    final b = _bytes(3000);
    final s = _Server(b)..cutAfter[1] = 1000;
    s.script = (req, n) => n == 2 ? http.StreamedResponse(const Stream.empty(), 416) : null;
    final path = await run(make(s), _release(b));
    expect(File(path).readAsBytesSync(), b);
    expect(s.requests, hasLength(3));
    expect(s.requests[2].headers.containsKey('Range'), isFalse);
  });

  test('a 206 whose Content-Range starts elsewhere is not appended', () async {
    final b = _bytes(3000);
    final s = _Server(b)..cutAfter[1] = 1000;
    s.script = (req, n) => n == 2
        ? http.StreamedResponse(Stream.value(b.sublist(0)), 206, headers: {'etag': '"v1"', 'content-range': 'bytes 0-2999/3000'})
        : null;
    final path = await run(make(s), _release(b));
    expect(File(path).readAsBytesSync(), b);
    expect(s.requests, hasLength(3));
  });

  test('403 asks for a fresh link and continues with it', () async {
    final b = _bytes(3000);
    final s = _Server(b)..cutAfter[1] = 1200;
    s.script = (req, n) {
      if (n == 2) {
        expect(req.url.toString(), 'https://files.example/a.apk');
        return http.StreamedResponse(const Stream.empty(), 403);
      }
      return null;
    };
    var asked = 0;
    final path = await run(
      make(s),
      _release(b),
      refresh: () async {
        asked++;
        return 'https://files.example/fresh.apk';
      },
    );
    expect(asked, 1);
    expect(s.requests[2].url.toString(), 'https://files.example/fresh.apk');
    expect(s.requests[2].headers['Range'], 'bytes=1200-');
    expect(File(path).readAsBytesSync(), b);
  });

  test('403 with no way to refresh fails but keeps the partial', () async {
    final b = _bytes(3000);
    final s = _Server(b)..cutAfter[1] = 1200;
    s.script = (req, n) => n == 2 ? http.StreamedResponse(const Stream.empty(), 403) : null;
    await expectLater(run(make(s), _release(b)), throwsA(isA<HttpException>()));
    expect(File('${tmp.path}/sparky-1.0.0-7.apk.part').lengthSync(), 1200);
  });

  test('a link older than 50 minutes is refreshed before the request', () async {
    final b = _bytes(2000);
    final s = _Server(b);
    final d = make(s);
    final r = _release(b);
    // Saved state says the link was issued an hour ago.
    store.state = PartialState(
      build: r.build,
      sha256: r.sha256,
      etag: '"v1"',
      url: r.url,
      urlAt: now.subtract(const Duration(minutes: 51)),
    );
    final path = await run(d, r, refresh: () async => 'https://files.example/new.apk');
    expect(s.requests.single.url.toString(), 'https://files.example/new.apk');
    expect(File(path).readAsBytesSync(), b);
  });

  test('a link younger than 50 minutes is kept', () async {
    final b = _bytes(2000);
    final s = _Server(b);
    final r = _release(b);
    store.state = PartialState(build: r.build, sha256: r.sha256, etag: null, url: r.url, urlAt: now.subtract(const Duration(minutes: 40)));
    var asked = 0;
    await run(make(s), r, refresh: () async {
      asked++;
      return 'x';
    });
    expect(asked, 0);
  });

  test('a corrupt kept prefix is caught by the final hash and discarded', () async {
    final b = _bytes(3000);
    final r = _release(b);
    // A partial that is the right length but wrong bytes, with a valid-looking validator.
    final bad = Uint8List.fromList(b.sublist(0, 1000))..[10] ^= 0xff;
    File('${tmp.path}/sparky-1.0.0-7.apk.part').writeAsBytesSync(bad);
    store.state = PartialState(build: r.build, sha256: r.sha256, etag: '"v1"', url: r.url, urlAt: now);
    final s = _Server(b);
    final d = make(s);
    await expectLater(run(d, r), throwsA(isA<UpdateVerifyException>()));
    expect(File('${tmp.path}/sparky-1.0.0-7.apk.part').existsSync(), isFalse);
    // The next attempt starts from zero and succeeds.
    final path = await run(d, r);
    expect(File(path).readAsBytesSync(), b);
  });

  test('a partial for another build is thrown away', () async {
    final b = _bytes(2000);
    final r = _release(b);
    File('${tmp.path}/sparky-1.0.0-7.apk.part').writeAsBytesSync([1, 2, 3]);
    store.state = PartialState(build: 99, sha256: 'other', etag: '"x"', url: r.url, urlAt: now);
    final s = _Server(b);
    final path = await run(make(s), r);
    expect(s.requests.single.headers.containsKey('Range'), isFalse);
    expect(File(path).readAsBytesSync(), b);
  });

  test('a complete but unrenamed partial is verified without a request', () async {
    final b = _bytes(2000);
    final r = _release(b);
    File('${tmp.path}/sparky-1.0.0-7.apk.part').writeAsBytesSync(b);
    store.state = PartialState(build: r.build, sha256: r.sha256, etag: '"v1"', url: r.url, urlAt: now);
    final s = _Server(b);
    final path = await run(make(s), r);
    expect(s.requests, isEmpty);
    expect(File(path).readAsBytesSync(), b);
  });

  test('a 500 is retried with backoff, a 404 is not', () async {
    final b = _bytes(1000);
    final s = _Server(b);
    s.script = (req, n) => n == 1 ? http.StreamedResponse(const Stream.empty(), 503) : null;
    final path = await run(make(s), _release(b));
    expect(File(path).readAsBytesSync(), b);
    expect(waits, [const Duration(seconds: 2)]);

    final s404 = _Server(b)..script = (req, n) => http.StreamedResponse(const Stream.empty(), 404);
    await expectLater(run(make(s404), _release(b, url: 'https://files.example/b.apk')), throwsA(isA<HttpException>()));
    expect(s404.requests, hasLength(1));
  });
}
