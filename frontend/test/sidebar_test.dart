import 'package:app/core/constants/app_strings.dart';
import 'package:app/core/widgets/m3_kit_extras.dart';
import 'package:app/core/constants/history.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/chat_api.dart';
import 'package:app/data/conversation.dart';
import 'package:app/data/conversations_api.dart';
import 'package:app/features/chat/chat_controller.dart';
import 'package:app/features/chat/widgets/app_drawer.dart';
import 'package:app/features/chat/widgets/drawer_shell.dart';
import 'package:app/features/history/history_controller.dart';
import 'package:app/features/history/history_grouping.dart';
import 'package:app/features/settings/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeConversations extends ConversationsApi {
  _FakeConversations(this.chats) : super('http://localhost:1');

  List<ConversationSummary> chats;
  final queries = <String>[];
  final pins = <(String, bool)>[];
  final archives = <(String, bool)>[];
  final renames = <(String, String)>[];

  @override
  Future<List<ConversationSummary>> list({
    String query = '',
    bool archived = false,
    int? limit,
    DateTime? before,
  }) async {
    queries.add(query);
    final q = query.toLowerCase();
    return [
      for (final c in chats)
        if (q.isEmpty || (c.title ?? '').toLowerCase().contains(q)) c,
    ];
  }

  @override
  Future<ConversationSummary> setPinned(String id, bool pinned) async {
    pins.add((id, pinned));
    return chats.firstWhere((c) => c.id == id);
  }

  @override
  Future<ConversationSummary> setArchived(String id, bool archived) async {
    archives.add((id, archived));
    return chats.firstWhere((c) => c.id == id);
  }

  @override
  Future<ConversationSummary> rename(String id, String title) async {
    renames.add((id, title));
    return _chat(id, title);
  }
}

ConversationSummary _chat(
  String id,
  String title, {
  DateTime? at,
  bool pinned = false,
  String? origin,
}) => ConversationSummary(
  id: id,
  title: title,
  preview: 'last words of $title',
  messageCount: 2,
  updatedAt: at ?? DateTime.now(),
  pinned: pinned,
  origin: origin,
);

List<ConversationSummary> _sample() {
  final now = DateTime.now();
  return [
    _chat('p', 'Pinned idea', pinned: true),
    _chat('a', 'Budget plan'),
    _chat('b', 'Trip to Oslo', origin: 'fork'),
    _chat('c', 'Old thing', at: now.subtract(const Duration(days: 2))),
    _chat('d', 'Ancient notes', at: now.subtract(const Duration(days: 90))),
  ];
}

Future<(_FakeConversations, HistoryController)> _pump(
  WidgetTester tester, {
  ThemeData? theme,
  double textScale = 1,
  Size size = const Size(360, 780),
  List<ConversationSummary>? chats,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final settings = await SettingsController.load();
  final api = _FakeConversations(chats ?? _sample());
  final history = HistoryController(api);
  addTearDown(history.dispose);
  final chat = ChatController(ChatApi(), settings, api);
  addTearDown(chat.dispose);
  final shell = GlobalKey<DrawerShellState>();
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: DrawerShell(
          key: shell,
          drawer: AppDrawer(chat: chat, history: history),
          child: const SizedBox(),
        ),
      ),
    ),
  );
  shell.currentState!.open();
  await tester.pumpAndSettle();
  return (api, history);
}

void main() {
  group('grouping', () {
    final now = DateTime(2026, 10, 12, 15);

    test('buckets by recency, then month and year', () {
      String at(DateTime d) => historyBucket(d, now);
      expect(at(DateTime(2026, 10, 12, 1)), HistoryStrings.today);
      expect(at(DateTime(2026, 10, 11, 23)), HistoryStrings.yesterday);
      expect(at(DateTime(2026, 10, 9)), HistoryStrings.previous7);
      expect(at(DateTime(2026, 10, 5)), HistoryStrings.previous7);
      expect(at(DateTime(2026, 10, 4)), HistoryStrings.previous30);
      expect(at(DateTime(2026, 9, 12)), HistoryStrings.previous30);
      expect(at(DateTime(2026, 8, 20)), 'AUGUST');
      expect(at(DateTime(2025, 12, 1)), 'DECEMBER 2025');
    });

    test('pinned first, groups keep server order', () {
      final groups = groupConversations([
        _chat('p', 'P', at: DateTime(2026, 1, 1), pinned: true),
        _chat('t', 'T', at: DateTime(2026, 10, 12, 9)),
        _chat('y', 'Y', at: DateTime(2026, 10, 11)),
        _chat('t2', 'T2', at: DateTime(2026, 10, 12, 8)),
        _chat('m', 'M', at: DateTime(2026, 7, 3)),
      ], now);
      expect(groups.map((g) => g.label), [
        HistoryStrings.pinned,
        HistoryStrings.today,
        HistoryStrings.yesterday,
        'JULY',
      ]);
      expect(groups[1].items.map((c) => c.id), ['t', 't2']);
      expect(groups.first.isPinned, isTrue);
    });

    test('relative time', () {
      expect(historyTime(now.subtract(const Duration(seconds: 5)), now), 'now');
      expect(historyTime(now.subtract(const Duration(minutes: 7)), now), '7m');
      expect(historyTime(now.subtract(const Duration(hours: 3)), now), '3h');
      expect(historyTime(now.subtract(const Duration(days: 2)), now), '2d');
      expect(
        historyTime(DateTime(2026, 8, 3), now),
        '3 ${AppStrings.months[7]}',
      );
    });
  });

  for (final (name, theme) in [
    ('light', AppTheme.light),
    ('dark', AppTheme.dark),
  ]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('drawer fits 360dp without overflow ($name, x$scale)', (
        tester,
      ) async {
        await _pump(tester, theme: theme, textScale: scale);
        expect(tester.takeException(), isNull);
        expect(find.text('sparky'), findsOneWidget);
        expect(find.text('Budget plan'), findsOneWidget);
        expect(find.text(sentenceCase(HistoryStrings.today)), findsOneWidget);
        expect(find.text(sentenceCase(HistoryStrings.pinned)), findsOneWidget);
      });
    }
  }

  testWidgets('drawer fits a landscape phone', (tester) async {
    await _pump(tester, size: const Size(780, 360), textScale: 1.3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search filters locally at once, then asks the server', (
    tester,
  ) async {
    final (api, _) = await _pump(tester);
    await tester.tap(find.text(HistoryStrings.searchHint));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'osl');
    await tester.pump();
    expect(find.text('Trip to Oslo'), findsOneWidget);
    expect(find.text('Budget plan'), findsNothing);
    await tester.pump(const Duration(milliseconds: 400));
    expect(api.queries, contains('osl'));
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.textContaining(HistoryStrings.noMatchesFor), findsOneWidget);
  });

  testWidgets('swiping right pins, swiping left archives', (tester) async {
    final (api, _) = await _pump(tester);
    await tester.drag(find.text('Budget plan'), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(api.pins, [('a', true)]);
    await tester.drag(find.text('Trip to Oslo'), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(api.archives, [('b', true)]);
  });

  testWidgets('long press opens the actions sheet; rename is inline', (
    tester,
  ) async {
    final (api, _) = await _pump(tester);
    await tester.longPress(find.text('Budget plan'));
    await tester.pumpAndSettle();
    for (final label in [
      AppStrings.rename,
      AppStrings.pinChat,
      AppStrings.archiveChat,
      AppStrings.deleteChat,
    ]) {
      expect(find.text(sentenceCase(label)), findsOneWidget);
    }
    await tester.tap(find.text(sentenceCase(AppStrings.rename)));
    await tester.pumpAndSettle();
    final field = find.widgetWithText(TextField, 'Budget plan');
    expect(field, findsOneWidget);
    await tester.enterText(field, 'Budget 2027');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(api.renames, [('a', 'Budget 2027')]);
  });

  testWidgets('shows the empty state when there are no chats', (tester) async {
    await _pump(tester, chats: const []);
    expect(find.text(AppStrings.historyEmpty), findsOneWidget);
  });
}
