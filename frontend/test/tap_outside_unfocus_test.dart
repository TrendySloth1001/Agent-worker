import 'package:app/core/widgets/tap_outside_unfocus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<({FocusNode focus, TextEditingController text, List<String> sent})>
_pump(WidgetTester tester) async {
  final focus = FocusNode();
  final text = TextEditingController();
  final sent = <String>[];
  addTearDown(focus.dispose);
  addTearDown(text.dispose);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => TapOutsideUnfocus(child: child!),
      home: Scaffold(
        body: Column(
          children: [
            const Expanded(child: Center(child: Text('empty space'))),
            TextField(
              key: const ValueKey('field'),
              controller: text,
              focusNode: focus,
            ),
            IconButton(
              key: const ValueKey('send'),
              icon: const Icon(Icons.send),
              onPressed: () => sent.add(text.text),
            ),
          ],
        ),
      ),
    ),
  );
  return (focus: focus, text: text, sent: sent);
}

void main() {
  testWidgets('tapping outside the field unfocuses it', (tester) async {
    final t = await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('field')));
    await tester.pump();
    expect(t.focus.hasFocus, isTrue);

    await tester.tap(find.text('empty space'));
    await tester.pump();
    expect(t.focus.hasFocus, isFalse);
  });

  testWidgets('tapping the field keeps the focus', (tester) async {
    final t = await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('field')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('field')));
    await tester.pump();
    expect(t.focus.hasFocus, isTrue);
  });

  testWidgets('the send button still works and keeps the text', (tester) async {
    final t = await _pump(tester);
    await tester.enterText(find.byKey(const ValueKey('field')), 'hello');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('send')));
    await tester.pump();
    expect(t.sent, ['hello']);
    expect(t.text.text, 'hello');
  });

  testWidgets('scrolling a list is not affected', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => TapOutsideUnfocus(child: child!),
        home: Scaffold(
          body: ListView(
            controller: controller,
            children: [
              for (var i = 0; i < 40; i++)
                SizedBox(height: 80, child: Text('row $i')),
            ],
          ),
        ),
      ),
    );
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pump();
    expect(controller.offset, greaterThan(0));
  });
}
