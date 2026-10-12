import 'dart:io';

import 'package:app/core/app_scope.dart';
import 'package:app/core/constants/app_icons.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/chat_api.dart';
import 'package:app/data/files_api.dart';
import 'package:app/data/usage_api.dart';
import 'package:app/features/auth/login_screen.dart';
import 'package:app/features/auth/register_screen.dart';
import 'package:app/features/chat/preview/preview_actions.dart';
import 'package:app/features/chat/preview/text_preview.dart';
import 'package:app/features/chat/share/share_sheet.dart';
import 'package:app/features/settings/settings_controller.dart';
import 'package:app/features/settings/usage_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/shot.dart';

/// Renders [home] at 360dp wide in a theme and text scale, and fails on any
/// framework exception (overflow included).
Future<void> _render(
  WidgetTester tester,
  Widget home, {
  required ThemeData theme,
  double scale = 1,
}) async {
  tester.view.physicalSize = const Size(360, 780);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final settings = await SettingsController.load();
  await tester.pumpWidget(
    AppScope(
      settings: settings,
      usage: UsageController(UsageApi('http://localhost:1')),
      api: ChatApi(),
      baseUrl: 'http://localhost:1',
      child: MaterialApp(
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: home,
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
  await autoShot(tester);
  expect(tester.takeException(), isNull);
}

final _variants = <(String, ThemeData, double)>[
  ('light', AppTheme.light, 1),
  ('dark', AppTheme.dark, 1),
  ('light 1.3x', AppTheme.light, 1.3),
  ('dark 1.3x', AppTheme.dark, 1.3),
];

void main() {
  for (final (name, theme, scale) in _variants) {
    testWidgets('login renders at 360dp, $name', (tester) async {
      await _render(tester, const LoginScreen(), theme: theme, scale: scale);
      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.byType(FilledButton), findsOneWidget);
    });

    testWidgets('register renders at 360dp, $name', (tester) async {
      await _render(tester, const RegisterScreen(), theme: theme, scale: scale);
      expect(find.byType(TextField), findsNWidgets(4));
      expect(find.byType(FilledButton), findsOneWidget);
    });

    testWidgets('preview message renders at 360dp, $name', (tester) async {
      await _render(
        tester,
        Scaffold(
          body: PreviewMessage(
            title: 'Could not load this file',
            hint: 'It may still be processing.',
            error: true,
            onRetry: () {},
          ),
        ),
        theme: theme,
        scale: scale,
      );
      expect(find.byType(FilledButton), findsOneWidget);
    });

    testWidgets('text preview renders a local file, $name', (tester) async {
      final dir = Directory.systemTemp.createTempSync('m3_preview');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/notes.txt')
        ..writeAsStringSync('Hello preview\nsecond line');
      await _render(
        tester,
        TextPreviewScreen(
          file: FileInfo(
            id: '',
            name: 'notes.txt',
            mime: 'text/plain',
            localPath: file.path,
          ),
        ),
        theme: theme,
        scale: scale,
      );
      for (var i = 0; i < 20; i++) {
        if (find
            .textContaining('Hello preview', findRichText: true)
            .evaluate()
            .isNotEmpty) {
          break;
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('Hello preview', findRichText: true),
        findsOneWidget,
      );
    });
  }

  testWidgets('share sheet is an M3 sheet that returns the pick', (
    tester,
  ) async {
    String? picked;
    await _render(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () async => picked = await showShareSheet<String>(
            context,
            title: 'SHARE AS',
            options: [
              ('a', AppIcons.copy, 'IMAGE'),
              ('b', AppIcons.copy, 'PDF'),
            ],
          ),
          child: const Text('open'),
        ),
      ),
      theme: AppTheme.dark,
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await autoShot(tester);
    expect(find.text('Share as'), findsOneWidget);
    await tester.tap(find.text('Pdf'));
    await tester.pumpAndSettle();
    expect(picked, 'b');
  });
}
