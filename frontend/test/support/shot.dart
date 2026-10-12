import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Where review screenshots go (outside the repo).
const shotDir = String.fromEnvironment(
  'SHOT_DIR',
  defaultValue:
      '/private/tmp/claude-501/-Users-nick-Agent-worker/d774ec7c-e537-46af-94a0-f20e69182929/scratchpad/shots',
);

/// Loads the real app fonts so screenshots show true metrics.
Future<void> loadAppFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final bytes = File('assets/fonts/$f').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  await load('SpaceGrotesk', ['SpaceGrotesk.ttf']);
  await load('SpaceMono', ['SpaceMono-Regular.ttf', 'SpaceMono-Bold.ttf']);
  await load('Doto', ['Doto.ttf']);
}

/// Writes the current frame to `$shotDir/<name>.png` at 2x.
Future<void> shot(WidgetTester tester, String name) async {
  final view = tester.binding.renderViews.first;
  final layer = view.debugLayer! as OffsetLayer;
  await tester.runAsync(() async {
    final image = await layer.toImage(Offset.zero & view.size, pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(shotDir).createSync(recursive: true);
    File('$shotDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

bool _fontsLoaded = false;

/// Review screenshot named after the running test. Runs only with
/// `flutter test --dart-define=SHOTS=true`, so the normal suite stays fast.
Future<void> autoShot(WidgetTester tester, [String suffix = '']) async {
  if (!const bool.fromEnvironment('SHOTS')) return;
  if (!_fontsLoaded) {
    await tester.runAsync(loadAppFonts);
    _fontsLoaded = true;
    await tester.pump();
  }
  final name = tester.testDescription.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
  await shot(tester, 'auto_$name$suffix');
}
