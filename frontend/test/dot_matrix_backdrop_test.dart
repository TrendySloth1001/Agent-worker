import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:app/core/motion/spring_field.dart';
import 'package:app/core/motion/spring_in.dart';
import 'package:app/core/motion/springs.dart';
import 'package:app/core/theme/app_palette.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/core/widgets/dot_matrix_backdrop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

/// One theme instance: a new one each pump would animate the theme.
final _light = AppTheme.light;
final _dark = AppTheme.dark;

Widget _app({
  required bool still,
  DotMatrixMode mode = DotMatrixMode.idle,
  bool dark = false,
  ValueGetter<double>? level,
}) => MaterialApp(
  theme: dark ? _dark : _light,
  debugShowCheckedModeBanner: false,
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: still),
    child: Builder(
      builder: (context) => ColoredBox(
        color: context.palette.surface,
        child: DotMatrixBackdrop(mode: mode, level: level),
      ),
    ),
  ),
);

bool _ticking(WidgetTester tester) =>
    SchedulerBinding.instance.transientCallbackCount > 0 ||
    tester.binding.hasScheduledFrame;

/// Goldens render below the phone's 2.6 so the PNGs stay small.
const _dpr = 1.5;

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(412, 915) * _dpr;
  tester.view.devicePixelRatio = _dpr;
  addTearDown(tester.view.reset);
}

/// Steps the clock in 60 fps frames (the physics is frame-stepped).
Future<void> _run(WidgetTester tester, Duration d) async {
  const frame = Duration(microseconds: 16667);
  for (var t = Duration.zero; t < d; t += frame) {
    await tester.pump(frame);
  }
}

Future<void> _shot(WidgetTester tester, String name) => expectLater(
  find.byType(MaterialApp),
  matchesGoldenFile('goldens/dot_matrix_$name.png'),
);

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

    // Touches do nothing either.
    await tester.tapAt(const Offset(200, 500));
    await tester.pump();
    expect(SchedulerBinding.instance.transientCallbackCount, 0);

    // Turning animations back on resumes it.
    await tester.pumpWidget(_app(still: false));
    await tester.pump(const Duration(milliseconds: 16));
    expect(_ticking(tester), isTrue);
  });

  test('reduced motion: the still frame is settled and vibrant', () {
    final frame = DotMatrixFrame()
      ..setTargets(DotMatrixMode.idle)
      ..settle();
    final painter = DotMatrixPainter(frame: frame, palette: AppPalette.dark);
    final rec = ui.PictureRecorder();
    painter.paint(Canvas(rec), const Size(412, 915));
    rec.endRecording().dispose();
    final h = frame.field.h;
    final peak = h.reduce(math.max);
    expect(peak, greaterThan(0.5), reason: 'a visible red glow');
    expect(frame.field.kinetic, 0, reason: 'nothing moves');
    expect(frame.waveStart, isNull);
  });

  testWidgets('hidden (TickerMode off): no frames', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: _light,
        home: const TickerMode(enabled: false, child: DotMatrixBackdrop()),
      ),
    );
    await tester.pump();
    expect(SchedulerBinding.instance.transientCallbackCount, 0);
  });

  testWidgets('touches pass through to the gesture behind', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: _light,
        home: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => taps++,
          child: const DotMatrixBackdrop(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));
    await tester.tapAt(const Offset(200, 300));
    await tester.pump(const Duration(milliseconds: 16));
    expect(taps, 1);
  });

  group('spring field', () {
    SpringField field() => SpringField(
      spring: AppSprings.spring(period: 1.6, damping: 0.2),
      coupling: 400,
      timestep: 1 / 120,
      maxSubsteps: 4,
      limit: 2,
    )..resize(21, 21);

    test('a kick spreads as a ring, overshoots and settles', () {
      final f = field()..kickRadial(10, 10, 20, 1.2);
      var ringSeen = false, overshoot = false;
      for (var i = 0; i < 60; i++) {
        f.advance(1 / 60);
        if (f.h[10 * 21 + 16] > 0.05) ringSeen = true;
        if (f.h[10 * 21 + 10] < -0.02) overshoot = true;
      }
      expect(ringSeen, isTrue, reason: 'energy travelled 6 cells');
      expect(overshoot, isTrue, reason: 'the centre swung past rest');
      for (var i = 0; i < 300; i++) {
        f.advance(1 / 60);
      }
      expect(f.h.map((e) => e.abs()).reduce(math.max), lessThan(0.01));
    });

    test('long frame gaps are capped, not simulated', () {
      final f = field();
      expect(f.advance(5), 4);
    });
  });

  test('SpringCurve overshoots and lands on 1', () {
    final curve = SpringCurve(AppSprings.pop);
    expect(curve.transform(0), 0);
    expect(curve.transform(1), 1);
    final peak = [
      for (var i = 1; i < 100; i++) curve.transform(i / 100),
    ].reduce(math.max);
    expect(peak, greaterThan(1.02));
    expect(
      AppSprings.settleTime(AppSprings.snappy).inMilliseconds,
      lessThan(600),
    );
    expect(
      AppSprings.pop.damping,
      closeTo(AppSprings.dampingFor(AppSprings.pop.stiffness, 0.68), 1e-9),
    );
  });

  group('SpringIn', () {
    double opacity(WidgetTester tester) =>
        tester.widget<Opacity>(find.byType(Opacity)).opacity;
    double scale(WidgetTester tester) => tester
        .widget<Transform>(find.byType(Transform).last)
        .transform
        .getMaxScaleOnAxis();

    testWidgets('springs in with an overshoot, then rests', (tester) async {
      await tester.pumpWidget(
        const Center(child: SpringIn(child: SizedBox(width: 50, height: 50))),
      );
      expect(opacity(tester), 0);
      var peak = 0.0;
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        peak = math.max(peak, scale(tester));
      }
      expect(peak, greaterThan(1.0), reason: 'overshoot');
      await tester.pumpAndSettle();
      expect(opacity(tester), 1);
      expect(scale(tester), closeTo(1, 1e-3));
    });

    testWidgets('reduced motion: just appears', (tester) async {
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Center(child: SpringIn(child: SizedBox(width: 50))),
        ),
      );
      expect(opacity(tester), 1);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });

  // CPU cost of one frame (412x915): the physics step plus recording the
  // paint. Worst cases: the open wave (every row live), listening with
  // turbulence, thinking waves. Printed for the report.
  test('frame benchmark (physics + paint)', () {
    const size = Size(412, 915);
    for (final (name, mode, wave) in [
      ('idle', DotMatrixMode.idle, false),
      ('thinking', DotMatrixMode.thinking, false),
      ('listening', DotMatrixMode.listening, false),
      ('open wave', DotMatrixMode.idle, true),
    ]) {
      final frame = DotMatrixFrame()..setTargets(mode);
      final painter = DotMatrixPainter(frame: frame, palette: AppPalette.dark);
      painter.paint(Canvas(ui.PictureRecorder()), size); // lay out
      const frames = 600;
      final watch = Stopwatch();
      for (var i = 0; i < frames + 120; i++) {
        final t = i / 60;
        if (wave && i % 30 == 0) frame.startWave(t);
        if (i % 20 == 0) frame.touch(Offset(100 + i % 200, 400));
        if (i == 120) watch.start(); // warm-up first
        frame.advance(t, 1 / 60, 0.6);
        final rec = ui.PictureRecorder();
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

  for (final dark in [false, true]) {
    final theme = dark ? 'dark' : 'light';

    group('goldens ($theme)', () {
      testWidgets('open wave', (tester) async {
        _phone(tester);
        await tester.pumpWidget(_app(still: false, dark: dark));
        for (final (ms, at) in [(150, 150), (330, 180)]) {
          await _run(tester, Duration(milliseconds: at));
          await _shot(tester, 'open_${ms}_$theme');
        }
      });

      testWidgets('idle', (tester) async {
        _phone(tester);
        await tester.pumpWidget(_app(still: false, dark: dark));
        await _run(tester, const Duration(milliseconds: 3000));
        await _shot(tester, 'idle_$theme');
      });

      testWidgets('touch ripple', (tester) async {
        _phone(tester);
        await tester.pumpWidget(_app(still: false, dark: dark));
        await _run(tester, const Duration(milliseconds: 1500));
        final g = await tester.startGesture(const Offset(206, 560));
        await _run(tester, const Duration(milliseconds: 120));
        await g.up();
        await _run(tester, const Duration(milliseconds: 180));
        await _shot(tester, 'ripple_300_$theme');
      });

      testWidgets('listening', (tester) async {
        _phone(tester);
        var n = 0;
        await tester.pumpWidget(
          _app(
            still: false,
            dark: dark,
            mode: DotMatrixMode.listening,
            level: () => 0.55 + 0.4 * math.sin(n++ * 0.21),
          ),
        );
        await _run(tester, const Duration(milliseconds: 2200));
        await _shot(tester, 'listening_$theme');
      });

      testWidgets('thinking', (tester) async {
        _phone(tester);
        await tester.pumpWidget(
          _app(still: false, dark: dark, mode: DotMatrixMode.thinking),
        );
        await _run(tester, const Duration(milliseconds: 2000));
        await _shot(tester, 'thinking_a_$theme');
      });

      testWidgets('reduced motion', (tester) async {
        _phone(tester);
        await tester.pumpWidget(_app(still: true, dark: dark));
        await tester.pump();
        await _shot(tester, 'still_$theme');
      });
    });
  }
}
