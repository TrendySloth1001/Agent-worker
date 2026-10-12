import 'package:app/core/constants/app_strings.dart';
import 'package:app/core/constants/history.dart';
import 'package:app/core/constants/m3_copy.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/core/widgets/m3_kit_extras.dart';
import 'package:app/data/doc_models.dart';
import 'package:app/data/docs_api.dart';
import 'package:app/features/chat/widgets/chat_input.dart';
import 'package:app/features/chat/widgets/message_sheet.dart';
import 'package:app/features/history/widgets/docs_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/render.dart';

class _FakeDocs implements DocsApi {
  @override
  Future<List<Doc>> list({String? conversationId}) async => [
    Doc(id: 'a', title: 'Sodium and health', createdAt: DateTime(2026, 10, 1)),
    Doc(id: 'b', title: '', status: DocStatus.writing),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A page with one button that runs [open] with its context.
Widget _host(Future<void> Function(BuildContext) open) => Builder(
  builder: (context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () => open(context),
        child: const Text('open'),
      ),
    ),
  ),
);

bool _handle(WidgetTester tester) =>
    tester.widget<BottomSheet>(find.byType(BottomSheet)).showDragHandle ??
    false;

void main() {
  for (final (name, theme, scale) in renderCases) {
    testWidgets('docs sheet is an M3 sheet with a handle ($name)', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        _host((c) => showDocsSheet(c, api: _FakeDocs())),
        theme: theme,
        textScale: scale,
      );
      await tester.tap(find.text('open'));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));
      expect(_handle(tester), isTrue);
      expect(find.text(DocsCopy.title), findsOneWidget);
      expect(find.text('Sodium and health'), findsOneWidget);
      expect(find.text(HistoryStrings.docUntitled), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('attach sheet lists grouped rows with sentence-case labels', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      _host((c) async => showAttachSheet(c)),
      theme: AppTheme.dark,
    );
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    expect(_handle(tester), isTrue);
    expect(find.text(sentenceCase(AppStrings.attachDocument)), findsOneWidget);
    expect(find.text(sentenceCase(AppStrings.attachMedia)), findsOneWidget);
  });

  testWidgets('message actions sheet copies and closes', (tester) async {
    await pumpScreen(
      tester,
      _host((c) => showReplyActions(c, text: 'hello')),
      textScale: 1.3,
    );
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    expect(_handle(tester), isTrue);
    await tester.tap(find.text(sentenceCase(AppStrings.copy)));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('sentenceCase only touches all-caps strings', () {
    expect(sentenceCase('FORK FROM HERE'), 'Fork from here');
    expect(sentenceCase('Already fine'), 'Already fine');
    expect(sentenceCase(''), '');
  });
}
