import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:app/data/kb_source.dart';
import 'package:app/data/knowledge_api.dart';
import 'package:app/features/knowledge/knowledge_controller.dart';
import 'package:app/features/knowledge/knowledge_screen.dart';
import 'package:app/features/knowledge/widgets/source_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/render.dart';
import 'support/shot.dart';

class _FakeKb implements KnowledgeApi {
  _FakeKb(this.items);

  final List<KbSource> items;

  @override
  Future<List<KbSource>> list() async => items;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

KbSource _src(
  String id,
  String type,
  String title, {
  String? iconUrl,
  String? uri,
}) => KbSource(
  id: id,
  type: type,
  uri: uri ?? 'https://example.com/$id',
  title: title,
  status: 'ready',
  progressDone: null,
  progressTotal: null,
  docCount: 4,
  chunkCount: 120,
  error: null,
  lastIngestedAt: null,
  iconUrl: iconUrl,
);

/// A solid-colour square PNG standing in for a fetched icon.
Future<Uint8List> _png(Color c) async {
  final rec = ui.PictureRecorder();
  Canvas(rec).drawRect(const Rect.fromLTWH(0, 0, 64, 64), Paint()..color = c);
  final img = await rec.endRecording().toImage(64, 64);
  return (await img.toByteData(
    format: ui.ImageByteFormat.png,
  ))!.buffer.asUint8List();
}

/// An image provider that always fails, like a dead icon URL.
class _Broken extends ImageProvider<_Broken> {
  @override
  Future<_Broken> obtainKey(ImageConfiguration c) => Future.value(this);

  @override
  ImageStreamCompleter loadImage(_Broken key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(Future.error(StateError('dead icon')));
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('a stored icon url renders as an image in a 40dp tile', (
    tester,
  ) async {
    final bytes = (await tester.runAsync(() => _png(Colors.teal)))!;
    await pumpScreen(
      tester,
      Scaffold(
        body: Center(
          child: SourceIcon(
            source: _src('a', 'web', 'Flutter', iconUrl: 'https://x/i.png'),
            imageFor: (_) => MemoryImage(bytes),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);
    expect(find.byKey(const ValueKey('source-monogram')), findsNothing);
    expect(tester.getSize(find.byType(SourceIcon)), const Size(40, 40));
  });

  testWidgets('missing or broken icons fall back to a monogram', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      Scaffold(
        body: Column(
          children: [
            SourceIcon(source: _src('a', 'web', 'flutter docs')),
            SourceIcon(
              source: _src('b', 'github', 'vercel/next.js', iconUrl: 'x'),
              imageFor: (_) => _Broken(),
            ),
          ],
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('F'), findsOneWidget);
    expect(find.text('V'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('notes, docs and files show type icons, not monograms', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      Scaffold(
        body: Column(
          children: [
            SourceIcon(source: _src('n', 'note', 'Meeting')),
            SourceIcon(source: _src('d', 'doc', 'HTTPS')),
            SourceIcon(source: _src('f', 'file', 'spec.pdf')),
          ],
        ),
      ),
    );
    expect(find.byKey(const ValueKey('source-monogram')), findsNothing);
  });

  for (final (name, theme, scale) in renderCases.take(2)) {
    testWidgets('knowledge list with stored icons ($name)', (tester) async {
      final colors = [Colors.indigo, Colors.orange, Colors.black87];
      final imgs = (await tester.runAsync(
        () => Future.wait(colors.map(_png)),
      ))!;
      final c = KnowledgeController(
        _FakeKb([
          _src('1', 'web', 'Flutter documentation', iconUrl: 'https://a/0.png'),
          _src('2', 'web', 'Stripe API reference', iconUrl: 'https://a/1.png'),
          _src('3', 'web', 'Obscure blog', iconUrl: 'https://a/broken'),
          _src(
            '4',
            'github',
            'vercel/next.js',
            iconUrl: 'https://a/2.png',
            uri: 'vercel/next.js',
          ),
          _src('5', 'file', 'Quarterly report.pdf', uri: 'file:1'),
          _src('6', 'file', 'notes.md', uri: 'file:2'),
          _src('7', 'doc', 'Understanding HTTPS and TLS 1.3', uri: 'doc:1'),
          _src('8', 'note', 'Meeting notes', uri: 'note:1'),
        ]),
      );
      await pumpScreen(
        tester,
        KnowledgeScreen(
          controller: c,
          imageFor: (u) => u.endsWith('broken')
              ? _Broken()
              : MemoryImage(imgs[int.parse(u.split('/').last[0])]),
        ),
        theme: theme,
        textScale: scale,
        height: 1500,
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await shot(tester, 'kb_icons_${name.replaceAll(' ', '_')}');
      expect(find.byType(Image), findsNWidgets(4));
      expect(tester.takeException(), isNull);
    });
  }
}
