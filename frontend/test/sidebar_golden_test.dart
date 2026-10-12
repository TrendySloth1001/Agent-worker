import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/auth_models.dart';
import 'package:app/data/chat_api.dart';
import 'package:app/data/conversation.dart';
import 'package:app/data/conversations_api.dart';
import 'package:app/features/auth/auth_controller.dart';
import 'package:app/features/chat/chat_controller.dart';
import 'package:app/features/chat/widgets/app_drawer.dart';
import 'package:app/features/chat/widgets/drawer_shell.dart';
import 'package:app/features/history/history_controller.dart';
import 'package:app/features/settings/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Api extends ConversationsApi {
  _Api(this.chats) : super('http://localhost:1');
  final List<ConversationSummary> chats;

  @override
  Future<List<ConversationSummary>> list({
    String query = '',
    bool archived = false,
    int? limit,
    DateTime? before,
  }) async => chats;
}

ConversationSummary _c(
  String id,
  String title, {
  Duration ago = Duration.zero,
  bool pinned = false,
  String? origin,
}) => ConversationSummary(
  id: id,
  title: title,
  preview: 'last words of $title',
  messageCount: 4,
  updatedAt: DateTime.now().subtract(ago),
  pinned: pinned,
  origin: origin,
);

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

void main() {
  for (final (name, theme) in [
    ('light', AppTheme.light),
    ('dark', AppTheme.dark),
  ]) {
    testWidgets('sidebar open ($name)', (tester) async {
      await _fonts();
      tester.view.physicalSize = const Size(412, 915) * 2.6;
      tester.view.devicePixelRatio = 2.6;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      AuthController.instance.user = const AuthUser(
        id: 'u',
        email: 'nick@cloudnsofts.com',
        name: 'Nick Rivera',
        role: 'owner',
      );
      addTearDown(() => AuthController.instance.user = null);
      final settings = await SettingsController.load();
      final api = _Api([
        _c(
          'p',
          'Trip to Oslo, packing list',
          pinned: true,
          ago: const Duration(days: 3),
        ),
        _c(
          'p2',
          'Quarterly budget model',
          pinned: true,
          ago: const Duration(days: 9),
        ),
        _c(
          'a',
          'Refactor the billing webhook',
          ago: const Duration(minutes: 12),
        ),
        _c(
          'b',
          'Explain pgvector indexes',
          ago: const Duration(hours: 3),
          origin: 'fork',
        ),
        _c('c', 'Dinner ideas for six', ago: const Duration(days: 1, hours: 2)),
        _c('d', 'Landing page copy review', ago: const Duration(days: 3)),
        _c('e', 'Flutter drawer motion notes', ago: const Duration(days: 12)),
      ]);
      final history = HistoryController(api);
      addTearDown(history.dispose);
      final chat = ChatController(ChatApi(), settings, api)
        ..conversationId = 'a';
      addTearDown(chat.dispose);
      final shell = GlobalKey<DrawerShellState>();
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme,
          home: Scaffold(
            body: DrawerShell(
              key: shell,
              drawer: AppDrawer(chat: chat, history: history),
              child: Builder(
                builder: (context) => ColoredBox(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: const Center(
                    child: Text('Refactor the billing webhook'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      shell.currentState!.open();
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/sidebar_open_$name.png'),
      );
    });
  }
}
