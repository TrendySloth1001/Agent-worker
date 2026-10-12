import 'dart:ui' as ui;

import 'package:app/core/theme/app_palette.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/core/widgets/dot_matrix_backdrop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

/// One theme instance: a new one each pump would animate the theme.
final _theme = AppTheme.light;

Widget _app({required bool still, DotMatrixMode mode = DotMatrixMode.idle}) =>
    MaterialApp(
      theme: _theme,
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: still),
        child: DotMatrixBackdrop(mode: mode),
      ),
    );

bool _ticking(WidgetTester tester) =>
    SchedulerBinding.instance.transientCallbackCount > 0 ||
    tester.binding.hasScheduledFrame;

void main() {
  testWidgets('animates: frames keep coming', (tester) async {
    await tester.pumpWidget(_app(still: false));
    await tester.pump(const Duration(milliseconds: 16));
    expect(_ticking(tester), isTrue);
  });

  testWidgets('reduced motion: the ticker stops, one still frame', (
    tester,
  ) async {
    await tester.pumpWidget(_app(still: true));
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(SchedulerBinding.instance.transientCallbackCount, 0);

    // Changing the mode does not start it again.
    await tester.pumpWidget(_app(still: true, mode: DotMatrixMode.thinking));
    await tester.pump();
    expect(SchedulerBinding.instance.transientCallbackCount, 0);

    // Turning animations back on resumes it.
    await tester.pumpWidget(_app(still: false));
    await tester.pump(const Duration(milliseconds: 16));
    expect(_ticking(tester), isTrue);
  });

  testWidgets('hidden (TickerMode off): no frames', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: _theme,
        home: const TickerMode(enabled: false, child: DotMatrixBackdrop()),
      ),
    );
    await tester.pump();
    expect(SchedulerBinding.instance.transientCallbackCount, 0);
  });

  // Recording cost of one frame on the CPU (412x915, worst case: the open
  // wave covers every row). Printed for the report; the bound is loose so it
  // never flakes on a busy CI box.
  test('paint benchmark', () {
    const size = Size(412, 915);
    for (final (name, mode, wave) in [
      ('idle', DotMatrixMode.idle, false),
      ('thinking', DotMatrixMode.thinking, false),
      ('listening', DotMatrixMode.listening, false),
      ('open wave', DotMatrixMode.idle, true),
    ]) {
      final frame = DotMatrixFrame()..setTargets(mode);
      final painter = DotMatrixPainter(frame: frame, palette: AppPalette.dark);
      const frames = 600;
      final watch = Stopwatch();
      for (var i = 0; i < frames + 60; i++) {
        final t = i / 60;
        frame
          ..waveStart = wave ? t - 0.2 : null
          ..advance(t, 1 / 60, 0.6);
        final rec = ui.PictureRecorder();
        if (i == 60) watch.start(); // warm-up first
        painter.paint(Canvas(rec), size);
        rec.endRecording().dispose();
      }
      watch.stop();
      final perFrame = watch.elapsedMicroseconds / frames / 1000;
      // ignore: avoid_print
      print('dot matrix $name: ${perFrame.toStringAsFixed(3)} ms/frame');
      expect(perFrame, lessThan(2.0));
    }
  });
}
