import 'package:app/core/constants/chat_cleanup.dart';
import 'package:app/core/constants/history.dart';
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

  List<ConversationSummary> chats;
  final deletes = <List<String>>[];
  final archives = <(String, bool)>[];
  final pins = <(String, bool)>[];
  final befores = <DateTime?>[];

  /// Page size the fake serves (pages by updatedAt like the server).
  int page = 1000;

  @override
  Future<List<ConversationSummary>> list({
    String query = '',
    bool archived = false,
    int? limit,
    DateTime? before,
  }) async {
    befores.add(before);
    final q = query.toLowerCase();
    final all = [
      for (final c in chats)
        if ((q.isEmpty || (c.title ?? '').toLowerCase().contains(q)) &&
            (before == null || c.updatedAt.isBefore(before)))
          c,
    ];
    final n = limit == null ? page : (limit < page ? limit : page);
    return all.take(n).toList();
  }

  @override
  Future<int> deleteMany(List<String> ids) async {
    deletes.add(ids);
    chats = [
      for (final c in chats)
        if (!ids.contains(c.id)) c,
    ];
    return ids.length;
  }

  @override
  Future<ConversationSummary> setArchived(String id, bool archived) async {
    archives.add((id, archived));
    return chats.firstWhere((c) => c.id == id);
  }

  @override
  Future<ConversationSummary> setPinned(String id, bool pinned) async {
    pins.add((id, pinned));
    return chats.firstWhere((c) => c.id == id);
  }
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

/// Times that land in the same sidebar groups whatever the clock says:
/// "today" never crosses midnight; older ones sit mid-day.
DateTime _today(Duration ago) {
  final now = DateTime.now();
  final midnight = DateTime(now.year, now.month, now.day);
  final at = now.subtract(ago);
  return at.isBefore(midnight) ? midnight : at;
}

DateTime _daysBack(int days) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day - days, 12);
}

ConversationSummary _at(
  String id,
  String title,
  DateTime at, {
  String? origin,
}) => ConversationSummary(
  id: id,
  title: title,
  preview: 'last words of $title',
  messageCount: 4,
  updatedAt: at,
  origin: origin,
);

List<ConversationSummary> _sample() => [
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
    ago: const Duration(days: 5),
  ),
  _at('a', 'Refactor the billing webhook', _today(const Duration(minutes: 12))),
  _at(
    'b',
    'Explain pgvector indexes',
    _today(const Duration(minutes: 30)),
    origin: 'fork',
  ),
  _at('c', 'Dinner ideas for six', _daysBack(1)),
  _at('d', 'Landing page copy review', _daysBack(3)),
  _at('e', 'Flutter drawer motion notes', _daysBack(12)),
];

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

class _Rig {
  _Rig(this.api, this.history, this.chat, this.shell);
  final _Api api;
  final HistoryController history;
  final ChatController chat;
  final GlobalKey<DrawerShellState> shell;
}

Future<_Rig> _pump(
  WidgetTester tester, {
  ThemeData? theme,
  List<ConversationSummary>? chats,
  int pageSize = 50,
  bool golden = false,
}) async {
  if (golden) await _fonts();
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
  final api = _Api(chats ?? _sample());
  final history = HistoryController(api, pageSize: pageSize);
  addTearDown(history.dispose);
  final chat = ChatController(ChatApi(), settings, api)..conversationId = 'a';
  addTearDown(chat.dispose);
  final shell = GlobalKey<DrawerShellState>();
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme ?? AppTheme.light,
      home: Scaffold(
        body: DrawerShell(
          key: shell,
          drawer: AppDrawer(chat: chat, history: history),
          child: Builder(
            builder: (context) => ColoredBox(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: const Center(child: Text('Refactor the billing webhook')),
            ),
          ),
        ),
      ),
    ),
  );
  shell.currentState!.open();
  await tester.pumpAndSettle();
  return _Rig(api, history, chat, shell);
}

Finder _row(String title) => find.text(title);

void main() {
  testWidgets('long press enters selection; taps toggle; close exits', (
    tester,
  ) async {
    final r = await _pump(tester);
    await tester.longPress(_row('Dinner ideas for six'));
    await tester.pumpAndSettle();
    expect(r.history.selecting, isTrue);
    expect(r.history.selected, {'c'});
    expect(find.text(ChatCleanupStrings.selected(1)), findsOneWidget);

    await tester.tap(_row('Landing page copy review'));
    await tester.pumpAndSettle();
    expect(r.history.selected, {'c', 'd'});
    expect(find.text(ChatCleanupStrings.selected(2)), findsOneWidget);
    // Tapping in selection mode does not open the chat.
    expect(r.chat.conversationId, 'a');

    await tester.tap(_row('Dinner ideas for six'));
    await tester.pumpAndSettle();
    expect(r.history.selected, {'d'});

    await tester.tap(find.bySemanticsLabel(ChatCleanupStrings.exitSelection));
    await tester.pumpAndSettle();
    expect(r.history.selecting, isFalse);
    expect(r.history.selected, isEmpty);
    expect(find.text(HistoryStrings.searchHint), findsOneWidget);
  });

  testWidgets('back leaves selection mode before closing the panel', (
    tester,
  ) async {
    final r = await _pump(tester);
    await tester.longPress(_row('Dinner ideas for six'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(r.history.selecting, isFalse);
    expect(r.shell.currentState!.isOpen, isTrue);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(r.shell.currentState!.isOpen, isFalse);
  });

  testWidgets('select all loads every page, then select none', (tester) async {
    final many = [
      for (var i = 0; i < 12; i++)
        _c('x$i', 'Chat number $i', ago: Duration(hours: i)),
    ];
    final r = await _pump(tester, chats: many, pageSize: 5);
    r.api.page = 5;
    expect(r.history.items.length, 5);
    await tester.longPress(_row('Chat number 0'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ChatCleanupStrings.selectAll));
    await tester.pumpAndSettle();
    expect(r.history.selected.length, 12);
    expect(r.history.allSelected, isTrue);
    expect(find.text(ChatCleanupStrings.selected(12)), findsOneWidget);
    await tester.tap(find.text(ChatCleanupStrings.selectNone));
    await tester.pumpAndSettle();
    expect(r.history.selected, isEmpty);
    expect(r.history.selecting, isTrue);
  });

  testWidgets('selection survives search filtering', (tester) async {
    final r = await _pump(tester);
    await tester.longPress(_row('Dinner ideas for six'));
    await tester.pumpAndSettle();
    r.history.search('flutter');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(_row('Flutter drawer motion notes'));
    await tester.pumpAndSettle();
    expect(r.history.selected, {'c', 'e'});
  });

  testWidgets('delete confirms, calls the API and leaves the open chat', (
    tester,
  ) async {
    final r = await _pump(tester);
    await tester.longPress(_row('Refactor the billing webhook').first);
    await tester.pumpAndSettle();
    await tester.tap(_row('Dinner ideas for six'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ChatCleanupStrings.delete));
    await tester.pumpAndSettle();
    expect(find.text(ChatCleanupStrings.deleteTitle(2)), findsOneWidget);
    expect(find.text(ChatCleanupStrings.deleteBody), findsOneWidget);
    // The dialog's red confirm button.
    await tester.tap(find.widgetWithText(FilledButton, 'Delete').last);
    await tester.pumpAndSettle();
    expect(r.api.deletes.single.toSet(), {'a', 'c'});
    expect(r.history.items.map((c) => c.id), isNot(contains('a')));
    expect(r.history.selecting, isFalse);
    expect(r.chat.conversationId, isNull); // the open chat was deleted
    expect(find.text(ChatCleanupStrings.deleted(2)), findsOneWidget);
  });

  testWidgets('cancel keeps the chats; archive moves them out', (tester) async {
    final r = await _pump(tester);
    await tester.longPress(_row('Dinner ideas for six'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ChatCleanupStrings.delete));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ChatCleanupStrings.cancel));
    await tester.pumpAndSettle();
    expect(r.api.deletes, isEmpty);
    expect(r.history.selected, {'c'});
    await tester.tap(find.text(ChatCleanupStrings.archive));
    await tester.pumpAndSettle();
    expect(r.api.archives, [('c', true)]);
    expect(r.history.items.map((c) => c.id), isNot(contains('c')));
    expect(r.history.selecting, isFalse);
  });

  for (final (name, theme) in [
    ('light', AppTheme.light),
    ('dark', AppTheme.dark),
  ]) {
    testWidgets('golden: sidebar in selection mode ($name)', (tester) async {
      final r = await _pump(tester, theme: theme, golden: true);
      r.history.startSelection('b');
      r.history.toggleSelected('c');
      r.history.toggleSelected('p2');
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/sidebar_selection_$name.png'),
      );
    });

    testWidgets('golden: delete chats dialog ($name)', (tester) async {
      final r = await _pump(tester, theme: theme, golden: true);
      r.history.startSelection('b');
      r.history.toggleSelected('c');
      r.history.toggleSelected('d');
      await tester.pumpAndSettle();
      await tester.tap(find.text(ChatCleanupStrings.delete));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/sidebar_delete_confirm_$name.png'),
      );
    });
  }
}
