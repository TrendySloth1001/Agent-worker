import 'package:app/core/app_scope.dart';
import 'package:app/core/constants/chat_cleanup.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/chat_api.dart';
import 'package:app/data/conversation_events.dart';
import 'package:app/data/conversations_api.dart';
import 'package:app/data/usage_api.dart';
import 'package:app/features/settings/settings_controller.dart';
import 'package:app/features/settings/settings_pages.dart';
import 'package:app/features/settings/usage_controller.dart';
import 'package:app/features/settings/widgets/delete_chats.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Api extends ConversationsApi {
  _Api() : super('http://localhost:1');

  final calls = <(bool, bool)>[];
  bool fail = false;

  @override
  Future<int> deleteAll({
    bool includeArchived = true,
    bool includePinned = true,
    bool archivedOnly = false,
  }) async {
    calls.add((includeArchived, includePinned));
    if (fail) throw const ApiException('boom');
    return 42;
  }
}

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

Future<void> _pump(WidgetTester tester, ThemeData theme) async {
  await _fonts();
  tester.view.physicalSize = const Size(412, 915) * 2.6;
  tester.view.devicePixelRatio = 2.6;
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
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: const SettingsCategoryPage(category: SettingsCategory.privacy),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

BuildContext _ctx(WidgetTester tester) =>
    tester.element(find.text(ChatCleanupStrings.deleteAll));

void main() {
  testWidgets('Privacy lists Delete all chats', (tester) async {
    await _pump(tester, AppTheme.light);
    expect(find.text(ChatCleanupStrings.deleteAll), findsOneWidget);
    expect(find.text(ChatCleanupStrings.section), findsOneWidget);
  });

  testWidgets('delete needs the typed word, sends the options, reports', (
    tester,
  ) async {
    await _pump(tester, AppTheme.light);
    final api = _Api();
    ChatsWiped? event;
    void listen() => event = ConversationEvents.instance.lastWipe;
    ConversationEvents.instance.addListener(listen);
    addTearDown(() => ConversationEvents.instance.removeListener(listen));

    final done = showDeleteAllChats(_ctx(tester), api: api);
    await tester.pumpAndSettle();
    final delete = find.widgetWithText(TextButton, ChatCleanupStrings.delete);
    expect(tester.widget<TextButton>(delete).onPressed, isNull);

    await tester.tap(find.text(ChatCleanupStrings.keepPinned));
    await tester.tap(find.text(ChatCleanupStrings.includeArchived));
    await tester.enterText(find.byType(TextField), 'delete');
    await tester.pump();
    expect(tester.widget<TextButton>(delete).onPressed, isNotNull);
    await tester.tap(delete);
    await tester.pumpAndSettle();

    expect(api.calls, [(false, false)]);
    expect(await done, 42);
    expect(event?.deleted, 42);
    expect(event?.includePinned, isFalse);
    expect(find.text(ChatCleanupStrings.deletedAll(42)), findsOneWidget);
  });

  testWidgets('a failure stays in the dialog with an error', (tester) async {
    await _pump(tester, AppTheme.light);
    final api = _Api()..fail = true;
    showDeleteAllChats(_ctx(tester), api: api);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'DELETE');
    await tester.pump();
    await tester.tap(
      find.widgetWithText(TextButton, ChatCleanupStrings.delete),
    );
    await tester.pumpAndSettle();
    expect(find.text(ChatCleanupStrings.deleteAllFailed), findsOneWidget);
    expect(find.byType(DeleteAllChatsDialog), findsOneWidget);
  });

  for (final (name, theme) in [
    ('light', AppTheme.light),
    ('dark', AppTheme.dark),
  ]) {
    testWidgets('golden: privacy page with Delete all chats ($name)', (
      tester,
    ) async {
      await _pump(tester, theme);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/settings_delete_chats_$name.png'),
      );
    });

    testWidgets('golden: delete all chats dialog ($name)', (tester) async {
      await _pump(tester, theme);
      showDeleteAllChats(_ctx(tester), api: _Api());
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'DELETE');
      await tester.pump();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/settings_delete_chats_dialog_$name.png'),
      );
    });
  }
}
