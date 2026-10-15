import 'dart:io';
import 'dart:typed_data';

import 'package:app/core/constants/preview.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/file_cache.dart';
import 'package:app/data/files_api.dart';
import 'package:app/data/kb_source.dart';
import 'package:app/features/chat/attachments_controller.dart';
import 'package:app/features/chat/chat_launch.dart';
import 'package:app/features/chat/preview/csv_parse.dart';
import 'package:app/features/chat/preview/file_preview.dart';
import 'package:app/features/chat/preview/image_preview.dart';
import 'package:app/features/chat/preview/info_preview.dart';
import 'package:app/features/chat/preview/pdf_preview.dart';
import 'package:app/features/chat/preview/preview_type.dart';
import 'package:app/features/chat/preview/text_preview.dart';
import 'package:app/features/chat/widgets/attachment_bar.dart';
import 'package:app/features/chat/widgets/attachment_views.dart';
import 'package:app/features/knowledge/knowledge_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;

late Directory _dir;

File _write(String name, List<int> bytes) =>
    File('${_dir.path}/$name')..writeAsBytesSync(bytes);

File _text(String name, String text) => _write(name, text.codeUnits);

FileInfo _local(File f, {String? mime, int id = 0}) => FileInfo(
  id: '',
  name: f.uri.pathSegments.last,
  mime: mime ?? mimeFor(f.path),
  size: f.lengthSync(),
  kind: guessKind(f.path),
  localPath: f.path,
);

Future<void> _app(WidgetTester tester, Widget home, {bool dark = false}) async {
  tester.view.physicalSize = const Size(360, 780);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(theme: dark ? AppTheme.dark : AppTheme.light, home: home),
  );
  await tester.pump();
}

/// Real async work (file reads, image decoding) needs the real event loop.
Future<void> _until(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 40; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Finder _rich(String s) => find.textContaining(s, findRichText: true);

Uint8List _png(int seed) {
  final image = img.Image(width: 48, height: 32);
  for (final p in image) {
    p.setRgb((p.x * 5 + seed * 60) % 256, p.y * 7, 128);
  }
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  setUp(() {
    _dir = Directory.systemTemp.createTempSync('file_preview');
    FileCache.instance = FileCache(
      root: () async => Directory('${_dir.path}/cache'),
    );
    ChatLaunch.instance.prompt.value = null;
    ChatLaunch.instance.files = const [];
  });
  tearDown(() => _dir.deleteSync(recursive: true));

  group('previewTypeOf', () {
    FileInfo f(String name, {String mime = '', FileKind? kind}) => FileInfo(
      id: 'a',
      name: name,
      mime: mime,
      kind: kind ?? guessKind(name),
    );

    test('maps names and mime types to viewers', () {
      expect(previewTypeOf(f('a.png')), PreviewType.image);
      expect(previewTypeOf(f('a.mp4')), PreviewType.video);
      expect(previewTypeOf(f('a.mp3')), PreviewType.audio);
      expect(previewTypeOf(f('a.pdf')), PreviewType.pdf);
      expect(previewTypeOf(f('x', mime: 'application/pdf')), PreviewType.pdf);
      expect(previewTypeOf(f('a.md')), PreviewType.markdown);
      expect(previewTypeOf(f('a.csv')), PreviewType.csv);
      expect(previewTypeOf(f('a.json')), PreviewType.json);
      expect(previewTypeOf(f('a.dart')), PreviewType.code);
      expect(previewTypeOf(f('a.txt')), PreviewType.text);
      expect(previewTypeOf(f('a.docx')), PreviewType.office);
      expect(previewTypeOf(f('a.pptx')), PreviewType.office);
      expect(previewTypeOf(f('a.zip')), PreviewType.unknown);
    });
  });

  group('parseCsv', () {
    test('quotes, doubled quotes, line breaks and delimiters', () {
      final rows = parseCsv('a,b\n"x, y","say ""hi"""\r\n"l1\nl2",z\n');
      expect(rows, [
        ['a', 'b'],
        ['x, y', 'say "hi"'],
        ['l1\nl2', 'z'],
      ]);
      expect(parseCsv('a;b\n1;2'), [
        ['a', 'b'],
        ['1', '2'],
      ]);
      expect(parseCsv('a\tb\n1\t2')[1], ['1', '2']);
    });
  });

  group('FileCache', () {
    const info = FileInfo(
      id: 'f1',
      name: 'a.txt',
      url: 'https://x/a',
      kind: FileKind.document,
    );

    test('downloads once, then serves from disk', () async {
      var gets = 0;
      final cache = FileCache(
        root: () async => Directory('${_dir.path}/c1'),
        info: (id, {force = false}) async => info,
        client: () => MockClient.streaming((req, _) async {
          gets++;
          return http.StreamedResponse(
            Stream.value('hello'.codeUnits),
            200,
            contentLength: 5,
          );
        }),
      );
      final a = await cache.fetch(info);
      final b = await cache.fetch(info);
      expect(a.readAsStringSync(), 'hello');
      expect(b.path, a.path);
      expect(gets, 1);
      await cache.evict('f1');
      expect(await cache.cached(info), isNull);
    });

    test('an expired link gets one retry with a fresh signature', () async {
      final forced = <bool>[];
      final cache = FileCache(
        root: () async => Directory('${_dir.path}/c2'),
        info: (id, {force = false}) async {
          forced.add(force);
          return FileInfo(
            id: 'f1',
            name: 'a.txt',
            url: force ? 'https://x/fresh' : 'https://x/old',
          );
        },
        client: () => MockClient.streaming((req, _) async {
          final ok = req.url.path == '/fresh';
          return http.StreamedResponse(
            Stream.value(ok ? 'ok'.codeUnits : <int>[]),
            ok ? 200 : 404,
          );
        }),
      );
      final f = await cache.fetch(info);
      expect(f.readAsStringSync(), 'ok');
      expect(forced, [false, true]);
    });

    test('a local file is used as it is', () async {
      final f = _text('local.txt', 'abc');
      final got = await FileCache.instance.fetch(_local(f));
      expect(got.path, f.path);
    });
  });

  group('text previews', () {
    testWidgets('markdown renders, SOURCE shows the raw text', (tester) async {
      final f = _text('notes.md', '# Big title\n\nSome **bold** words');
      await _app(tester, TextPreviewScreen(file: _local(f)));
      await _until(tester, _rich('Big title'));
      expect(_rich('Big title'), findsOneWidget);
      expect(_rich('# Big title'), findsNothing);
      await tester.tap(find.byTooltip(PreviewStrings.viewToggle));
      await tester.pump();
      expect(_rich('# Big title'), findsOneWidget);
    });

    testWidgets('code is shown with highlighting spans', (tester) async {
      final f = _text('main.dart', 'void main() {\n  print("hi");\n}\n');
      await _app(tester, TextPreviewScreen(file: _local(f)));
      await _until(tester, _rich('print'));
      final rich = tester
          .widgetList<RichText>(find.byType(RichText))
          .where((r) => r.text.toPlainText().contains('print'))
          .first;
      // Keywords, strings and the like carry the palette's syntax colors.
      final colored = 'color:'.allMatches(rich.text.toStringDeep()).length;
      expect(colored, greaterThan(2));
    });

    testWidgets('JSON is pretty printed', (tester) async {
      final f = _text('data.json', '{"a":1,"b":[true,null]}');
      await _app(tester, TextPreviewScreen(file: _local(f)));
      await _until(tester, _rich('"a": 1'));
      expect(_rich('"a": 1'), findsOneWidget);
    });

    testWidgets('CSV shows a table with its header and rows', (tester) async {
      final f = _text('t.csv', 'name,qty\napple,3\n"pear, green",5\n');
      await _app(tester, TextPreviewScreen(file: _local(f)));
      await _until(tester, find.text('apple'));
      expect(find.text('name'), findsOneWidget);
      expect(find.text('qty'), findsOneWidget);
      expect(find.text('pear, green'), findsOneWidget);
      expect(find.text(PreviewStrings.rows(3, 3)), findsOneWidget);
    });

    testWidgets('a long text pages with LOAD MORE', (tester) async {
      final lines = [for (var i = 0; i < 4000; i++) 'line number $i'];
      final f = _text('big.txt', lines.join('\n'));
      await _app(tester, TextPreviewScreen(file: _local(f)));
      await _until(tester, _rich('line number 0'));
      expect(_rich('line number 3999'), findsNothing);
      final more = find.text(PreviewStrings.loadMore);
      await tester.scrollUntilVisible(
        more,
        800,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(more);
      await tester.pump();
      await tester.scrollUntilVisible(
        _rich('line number 1500'),
        800,
        scrollable: find.byType(Scrollable).first,
      );
      expect(_rich('line number 1500'), findsOneWidget);
    });

    testWidgets('an empty file says so', (tester) async {
      final f = _text('empty.txt', '');
      await _app(tester, TextPreviewScreen(file: _local(f)));
      await _until(tester, find.text('THIS FILE IS EMPTY'));
      expect(find.text(PreviewStrings.emptyFile), findsOneWidget);
    });

    testWidgets('an Office file without text yet shows the info card', (
      tester,
    ) async {
      const doc = FileInfo(id: '', name: 'report.docx', size: 2048);
      await _app(tester, const TextPreviewScreen(file: doc));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('report.docx'), findsWidgets);
      expect(find.text(PreviewStrings.openWith), findsOneWidget);
      expect(find.text(PreviewStrings.share), findsOneWidget);
      expect(find.text(PreviewStrings.download), findsOneWidget);
    });
  });

  group('info and pdf', () {
    testWidgets('an unknown type shows the info card with actions', (
      tester,
    ) async {
      final f = FileInfo(
        id: 'u1',
        name: 'archive.zip',
        mime: 'application/zip',
        size: 3 * 1024 * 1024,
        createdAt: DateTime(2026, 10, 11, 18, 32),
      );
      await _app(tester, InfoPreviewScreen(file: f));
      expect(find.text(PreviewStrings.unknownTitle), findsOneWidget);
      expect(find.text('application/zip'), findsOneWidget);
      expect(find.text('3.0 MB'), findsOneWidget);
      expect(find.text('2026-10-11 18:32'), findsOneWidget);
      expect(find.text(PreviewStrings.openWith), findsOneWidget);
    });

    testWidgets('pdf shows progress, then a retry when the file is missing', (
      tester,
    ) async {
      FileCache.instance = FileCache(
        root: () async => Directory('${_dir.path}/p'),
        info: (id, {force = false}) async => throw StateError('offline'),
      );
      const f = FileInfo(id: 'p1', name: 'doc.pdf', mime: 'application/pdf');
      await _app(tester, const PdfPreviewScreen(file: f));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await _until(tester, find.text('RETRY'));
      expect(tester.takeException(), isNull);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('image viewer', () {
    testWidgets('swipes between the images of a message', (tester) async {
      final a = _write('a.png', _png(1));
      final b = _write('b.png', _png(2));
      final files = [_local(a), _local(b)];
      await _app(tester, FileImageViewer(files: files, initial: 0));
      expect(find.text('1 / 2'), findsOneWidget);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.drag(find.byType(PageView), const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(find.text('2 / 2'), findsOneWidget);
      expect(find.text('b.png'), findsOneWidget);
    });

    testWidgets('double tap zooms in and back out', (tester) async {
      final a = _write('a.png', _png(1));
      await _app(tester, FileImageViewer(files: [_local(a)], initial: 0));
      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      final c = viewer.transformationController!;
      expect(c.value.getMaxScaleOnAxis(), 1);
      final at = tester.getCenter(find.byType(InteractiveViewer));
      Future<void> doubleTap() async {
        await tester.tapAt(at);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tapAt(at);
        await tester.pump(const Duration(milliseconds: 400));
      }

      await doubleTap();
      expect(c.value.getMaxScaleOnAxis(), greaterThan(1.5));
      await doubleTap();
      expect(c.value.getMaxScaleOnAxis(), 1);
    });
  });

  group('actions', () {
    testWidgets('the menu lists share, download, open with, info, delete', (
      tester,
    ) async {
      const f = FileInfo(id: 'a1', name: 'notes.txt', size: 4);
      await _app(tester, const InfoPreviewScreen(file: f));
      await tester.tap(find.byTooltip(PreviewStrings.more));
      await tester.pumpAndSettle();
      for (final s in [
        PreviewStrings.share,
        PreviewStrings.download,
        PreviewStrings.openWith,
        PreviewStrings.info,
        PreviewStrings.delete,
      ]) {
        expect(find.text(s), findsWidgets, reason: s);
      }
      await tester.tap(find.text(PreviewStrings.info));
      await tester.pumpAndSettle();
      expect(find.text(PreviewStrings.infoSize), findsWidgets);
    });

    testWidgets('a local-only file has no ask or delete', (tester) async {
      final f = _text('x.txt', 'x');
      await _app(tester, InfoPreviewScreen(file: _local(f)));
      expect(find.byTooltip(PreviewStrings.ask), findsNothing);
      await tester.tap(find.byTooltip(PreviewStrings.more));
      await tester.pumpAndSettle();
      expect(find.text(PreviewStrings.delete), findsNothing);
    });

    testWidgets('ASK SPARKY starts a chat with the file attached', (
      tester,
    ) async {
      const f = FileInfo(id: 'a1', name: 'notes.txt');
      await _app(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const InfoPreviewScreen(file: f),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(PreviewStrings.ask));
      await tester.pumpAndSettle();
      expect(ChatLaunch.instance.prompt.value, contains('notes.txt'));
      expect(ChatLaunch.instance.files.single.id, 'a1');
      expect(find.byType(InfoPreviewScreen), findsNothing);
    });
  });

  group('entry points', () {
    testWidgets('tapping a document attachment opens the preview', (
      tester,
    ) async {
      final f = _text('notes.txt', 'attached words');
      await _app(
        tester,
        Scaffold(body: MessageAttachments(files: [_local(f)])),
      );
      await tester.tap(find.text('notes.txt'));
      await tester.pump(const Duration(milliseconds: 400));
      await _until(tester, _rich('attached words'));
      expect(find.byType(TextPreviewScreen), findsOneWidget);
      expect(_rich('attached words'), findsOneWidget);
    });

    testWidgets('tapping an image attachment opens the image viewer', (
      tester,
    ) async {
      final a = _write('pic.png', _png(3));
      await _app(
        tester,
        Scaffold(body: MessageAttachments(files: [_local(a)])),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byType(Hero).first);
      await tester.pumpAndSettle();
      expect(find.byType(FileImageViewer), findsOneWidget);
      expect(find.text('1 / 1'), findsOneWidget);
    });

    testWidgets('a composer chip opens the preview before sending', (
      tester,
    ) async {
      final f = _text('draft.md', '# Draft heading');
      final controller = AttachmentsController();
      controller.items.add(
        PendingAttachment(localPath: f.path, name: 'draft.md', size: 15),
      );
      await _app(tester, Scaffold(body: AttachmentBar(controller: controller)));
      await tester.tap(find.text('draft.md'));
      await tester.pump(const Duration(milliseconds: 400));
      await _until(tester, _rich('Draft heading'));
      expect(find.byType(TextPreviewScreen), findsOneWidget);
      controller.items.clear();
    });

    testWidgets('openFilePreview routes an unknown type to the info card', (
      tester,
    ) async {
      const f = FileInfo(id: 'z1', name: 'blob.bin', mime: 'application/zip');
      await _app(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => openFilePreview(context, [f], f),
            child: const Text('go'),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.byType(InfoPreviewScreen), findsOneWidget);
    });

    test('an uploaded knowledge document maps to its stored file', () {
      KbSource source(String type, String uri) => KbSource(
        id: 's',
        type: type,
        uri: uri,
        title: 'Plan.pdf',
        status: 'ready',
        progressDone: null,
        progressTotal: null,
        docCount: 1,
        chunkCount: 3,
        error: null,
        lastIngestedAt: null,
      );
      final file = knowledgeFileOf(source('file', 'file:abc'))!;
      expect(file.id, 'abc');
      expect(file.name, 'Plan.pdf');
      expect(previewTypeOf(file), PreviewType.pdf);
      expect(knowledgeFileOf(source('web', 'https://x')), isNull);
      expect(knowledgeFileOf(source('doc', 'doc:abc')), isNull);
    });
  });
}
