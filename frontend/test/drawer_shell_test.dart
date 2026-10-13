import 'package:app/core/theme/app_theme.dart';
import 'package:app/features/chat/widgets/drawer_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _size = Size(400, 800);
const _panelWidth = 340.0; // 400 * 0.85 = 340, the drawer's maximum

final _shell = GlobalKey<DrawerShellState>();

Future<void> _pump(WidgetTester tester, {bool reduceMotion = false}) async {
  tester.view.physicalSize = _size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: child!,
      ),
      home: Scaffold(
        body: DrawerShell(
          key: _shell,
          drawer: const Material(child: Center(child: Text('panel'))),
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (var i = 0; i < 20; i++)
                SizedBox(width: 200, child: Center(child: Text('cell $i'))),
            ],
          ),
        ),
      ),
    ),
  );
}

double get _panelLeft =>
    _topLeft(DrawerShellState.panelKey, _shell.currentContext!).dx;

Offset _topLeft(Key key, BuildContext context) {
  final box = find.byKey(key).evaluate().single.renderObject! as RenderBox;
  return box.localToGlobal(Offset.zero);
}

double get _contentLeft =>
    _topLeft(DrawerShellState.contentKey, _shell.currentContext!).dx;

double get _contentScale {
  final box = find
      .descendant(
        of: find.byKey(DrawerShellState.contentKey),
        matching: find.byType(ClipRRect),
      )
      .evaluate()
      .single
      .renderObject!;
  return box.getTransformTo(null).entry(0, 0);
}

/// Counts haptic calls on the platform channel.
List<String> _recordHaptics(WidgetTester tester) {
  final calls = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'HapticFeedback.vibrate')
        calls.add('${call.arguments}');
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return calls;
}

void main() {
  testWidgets('opening from a button adds no second haptic', (tester) async {
    await _pump(tester);
    final calls = _recordHaptics(tester);
    _shell.currentState!.open();
    await tester.pumpAndSettle();
    expect(_shell.currentState!.value, 1);
    expect(calls, isEmpty); // The button gives the one tap itself.
  });

  testWidgets('a swipe that settles open ticks once', (tester) async {
    await _pump(tester);
    final calls = _recordHaptics(tester);
    // A no-op open first must not silence the next swipe.
    _shell.currentState!.close();
    await tester.dragFrom(const Offset(2, 400), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(_shell.currentState!.value, 1);
    expect(calls.length, 1);
  });

  testWidgets('drag from the edge moves panel and chat 1:1', (tester) async {
    await _pump(tester);
    expect(_shell.currentState!.value, 0);

    final gesture = await tester.startGesture(const Offset(6, 400));
    await gesture.moveBy(const Offset(100, 0));
    await tester.pump();
    // Panel and chat follow the finger exactly.
    expect(_shell.currentState!.value, closeTo(100 / _panelWidth, 0.001));
    expect(_panelLeft, closeTo(-_panelWidth + 100, 0.5));
    expect(_contentLeft, closeTo(100, 0.5));

    await gesture.moveBy(const Offset(100, 0));
    await tester.pump();
    final t = 200 / _panelWidth;
    expect(_panelLeft, closeTo(-_panelWidth + 200, 0.5));
    expect(_contentLeft, closeTo(200, 0.5));
    // The chat also shrinks while it is pushed.
    expect(_contentScale, closeTo(1 - (1 - 0.92) * t, 0.005));
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('slow release settles by position', (tester) async {
    await _pump(tester);
    var g = await tester.startGesture(const Offset(6, 400));
    await g.moveBy(const Offset(220, 0));
    await tester.pump(const Duration(seconds: 1)); // no velocity left
    await g.up();
    await tester.pumpAndSettle();
    expect(_shell.currentState!.value, 1);
    expect(_panelLeft, 0);

    // Drag the pushed chat back, short of half: it springs open again.
    g = await tester.startGesture(const Offset(370, 400));
    await g.moveBy(const Offset(-60, 0));
    await tester.pump(const Duration(seconds: 1));
    await g.up();
    await tester.pumpAndSettle();
    expect(_shell.currentState!.value, 1);

    // Past half: closes.
    g = await tester.startGesture(const Offset(370, 400));
    await g.moveBy(const Offset(-250, 0));
    await tester.pump(const Duration(seconds: 1));
    await g.up();
    await tester.pumpAndSettle();
    expect(_shell.currentState!.value, 0);
    expect(_contentLeft, 0);
  });

  testWidgets('a short fling opens, a short fling closes', (tester) async {
    await _pump(tester);
    await tester.flingFrom(const Offset(6, 400), const Offset(60, 0), 1500);
    await tester.pumpAndSettle();
    expect(_shell.currentState!.value, 1);

    await tester.flingFrom(const Offset(370, 400), const Offset(-60, 0), 1500);
    await tester.pumpAndSettle();
    expect(_shell.currentState!.value, 0);
  });

  testWidgets('horizontal scrolling inside the chat is not taken over', (
    tester,
  ) async {
    await _pump(tester);
    await tester.drag(find.text('cell 1'), const Offset(-150, 0));
    await tester.pumpAndSettle();
    expect(_shell.currentState!.value, 0);
    await tester.drag(find.text('cell 2'), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(_shell.currentState!.value, 0);
  });

  testWidgets('back closes it; the scrim tap closes it', (tester) async {
    await _pump(tester);
    _shell.currentState!.open();
    await tester.pumpAndSettle();
    expect(_shell.currentState!.isOpen, isTrue);

    await tester.tapAt(const Offset(380, 400));
    await tester.pumpAndSettle();
    expect(_shell.currentState!.value, 0);

    _shell.currentState!.open();
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_shell.currentState!.value, 0);
  });

  testWidgets('reduced motion settles at once', (tester) async {
    await _pump(tester, reduceMotion: true);
    _shell.currentState!.open();
    await tester.pump();
    expect(_shell.currentState!.value, 1);
    _shell.currentState!.close();
    await tester.pump();
    expect(_shell.currentState!.value, 0);
  });

  testWidgets('predictive back follows progress, commit closes, cancel keeps', (
    tester,
  ) async {
    await _pump(tester);
    _shell.currentState!.open();
    await tester.pumpAndSettle();

    final state = _shell.currentState!;
    PredictiveBackEvent at(double p) => PredictiveBackEvent.fromMap({
      'progress': p,
      'swipeEdge': SwipeEdge.left.index,
    });
    expect(state.handleStartBackGesture(at(0)), isTrue);
    state.handleUpdateBackGestureProgress(at(0.5));
    await tester.pump();
    expect(state.value, closeTo(0.5, 0.001));
    state.handleCancelBackGesture();
    await tester.pumpAndSettle();
    expect(state.value, 1);

    expect(state.handleStartBackGesture(at(0)), isTrue);
    state.handleUpdateBackGestureProgress(at(0.3));
    state.handleCommitBackGesture();
    await tester.pumpAndSettle();
    expect(state.value, 0);
    // Nothing to handle once closed: the system gets the back.
    expect(state.handleStartBackGesture(at(0)), isFalse);
  });
}
