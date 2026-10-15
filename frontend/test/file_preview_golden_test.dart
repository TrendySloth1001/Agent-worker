import 'dart:io';

import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/file_cache.dart';
import 'package:app/data/files_api.dart';
import 'package:app/features/chat/preview/image_preview.dart';
import 'package:app/features/chat/preview/info_preview.dart';
import 'package:app/features/chat/preview/text_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Future<void> _fonts() async {
  for (final (family, files) in [
    ('SpaceGrotesk', ['SpaceGrotesk.ttf']),
    ('SpaceMono', ['SpaceMono-Regular.ttf', 'SpaceMono-Bold.ttf']),
  ]) {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(rootBundle.load('assets/fonts/$f'));
    }
    await loader.load();
  }
}

late Directory _dir;

FileInfo _local(String name, List<int> bytes) {
  final f = File('${_dir.path}/$name')..writeAsBytesSync(bytes);
  return FileInfo(
    id: '',
    name: name,
    mime: mimeFor(name),
    size: bytes.length,
    kind: guessKind(name),
    localPath: f.path,
  );
}

Uint8List _png() {
  final image = img.Image(width: 160, height: 100);
  for (final p in image) {
    p.setRgb(40 + p.x, 80 + p.y * 2, 200 - p.x);
  }
  return Uint8List.fromList(img.encodePng(image));
}

Future<void> _show(WidgetTester tester, Widget home, bool dark) async {
  tester.view.physicalSize = const Size(412, 915) * 2.6;
  tester.view.devicePixelRatio = 2.6;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: dark ? AppTheme.dark : AppTheme.light,
      home: home,
    ),
  );
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(_fonts);
  setUp(() {
    _dir = Directory.systemTemp.createTempSync('preview_golden');
    FileCache.instance = FileCache(
      root: () async => Directory('${_dir.path}/cache'),
    );
  });
  tearDown(() => _dir.deleteSync(recursive: true));

  for (final (name, dark) in const [('light', false), ('dark', true)]) {
    testWidgets('code preview ($name)', (tester) async {
      final f = _local(
        'main.dart',
        '''import 'dart:io';

/// Prints a greeting.
void main(List<String> args) {
  final name = args.isEmpty ? 'world' : args.first;
  print("Hello, \$name! \${42 + 1}");
}
'''
            .codeUnits,
      );
      await _show(tester, TextPreviewScreen(file: f), dark);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/preview_code_$name.png'),
      );
    });

    testWidgets('markdown preview ($name)', (tester) async {
      final f = _local(
        'README.md',
        '''# Trip plan

Three things to book:

- **Flights** to Lisbon
- A hotel near the river
- `tram 28` tickets

> Leave early, the queues are long.
'''
            .codeUnits,
      );
      await _show(tester, TextPreviewScreen(file: f), dark);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/preview_markdown_$name.png'),
      );
    });

    testWidgets('csv preview ($name)', (tester) async {
      final f = _local(
        'sales.csv',
        '''item,region,units,price
Notebook,North,120,3.50
Pen,South,860,0.80
"Desk lamp, LED",East,35,24.00
Stapler,West,60,6.25
'''
            .codeUnits,
      );
      await _show(tester, TextPreviewScreen(file: f), dark);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/preview_csv_$name.png'),
      );
    });

    testWidgets('unknown type info card ($name)', (tester) async {
      final f = FileInfo(
        id: 'z',
        name: 'backup-2026.zip',
        mime: 'application/zip',
        size: 18 * 1024 * 1024,
        createdAt: DateTime(2026, 10, 11, 18, 32),
      );
      await _show(tester, InfoPreviewScreen(file: f), dark);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/preview_info_$name.png'),
      );
    });

    testWidgets('image viewer ($name)', (tester) async {
      final f = _local('photo.png', _png());
      await _show(tester, FileImageViewer(files: [f], initial: 0), dark);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/preview_image_$name.png'),
      );
    });
  }
}
