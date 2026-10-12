import 'package:app/core/constants/home_copy.dart';
import 'package:app/core/theme/app_palette.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/core/widgets/dot_grid_background.dart';
import 'package:app/data/conversation.dart';
import 'package:app/features/chat/widgets/empty_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/shot.dart';

const _shots = bool.fromEnvironment('SHOTS');

List<ConversationSummary> _chats() => [
  ConversationSummary(
    id: 'a',
    title: 'Media player crash causes',
    preview: 'x',
    messageCount: 12,
    updatedAt: DateTime.now().subtract(const Duration(hours: 1)),
  ),
  ConversationSummary(
    id: 'b',
    title: 'Understanding HTTPS and TLS 1.3',
    preview: 'x',
    messageCount: 4,
    updatedAt: DateTime.now().subtract(const Duration(hours: 4)),
  ),
];

class _Rig {
  final sent = <String>[];
  final edited = <String>[];
  final caps = <HomeCapability>[];
  final opened = <String>[];
}

/// Pumps the home over the dot grid with a stand-in composer, like the chat.
Future<_Rig> _pump(
  WidgetTester tester, {
  required Size size,
  required ThemeData theme,
  double scale = 1,
  double keyboard = 0,
  String name = 'shot',
  bool recents = true,
}) async {
  EmptyState.resetCache();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final rig = _Rig();
  const composer = 132.0;
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          padding: const EdgeInsets.only(top: 28, bottom: 16),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    const Positioned.fill(child: DotGridBackground()),
                    Positioned.fill(
                      child: EmptyState(
                        name: 'Nikhil',
                        now: DateTime(2026, 10, 12, 19),
                        startersLoader: () async => const [
                          'Explain media player crash causes',
                          'Detail Flutter video playback bugs',
                          'Compare PostgreSQL and MongoDB chat',
                          'Describe user request handling concepts',
                        ],
                        onSuggestion: rig.sent.add,
                        onEdit: rig.edited.add,
                        onCapability: rig.caps.add,
                        isOn: (c) => c == HomeCapability.knowledge,
                        recentLoader: recents ? () async => _chats() : null,
                        onOpenChat: rig.opened.add,
                        bottomClear: composer + 16 + 16,
                      ),
                    ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 16,
                      child: Container(
                        height: composer,
                        decoration: BoxDecoration(
                          color: context.palette.surface,
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: context.palette.border),
                        ),
                        alignment: Alignment.topLeft,
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          'Ask anything',
                          style: context.text.body.copyWith(
                            color: context.palette.textTertiary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: keyboard),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 900));
  if (_shots) {
    await tester.runAsync(loadAppFonts);
    await tester.pump();
    await shot(tester, 'home_$name');
  }
  return rig;
}

void main() {
  final sizes = <(String, Size)>[
    ('412x915', const Size(412, 915)),
    ('360x780', const Size(360, 780)),
    ('360x780_kb', const Size(360, 780)),
    ('780x360_land', const Size(780, 360)),
  ];
  for (final (themeName, theme) in [
    ('light', AppTheme.light),
    ('dark', AppTheme.dark),
  ]) {
    for (final (sizeName, size) in sizes) {
      for (final scale in [1.0, 1.3]) {
        testWidgets(
          'home renders without overflow $themeName $sizeName x$scale',
          (tester) async {
            await _pump(
              tester,
              size: size,
              theme: theme,
              scale: scale,
              keyboard: sizeName.endsWith('_kb') ? 300 : 0,
              name: '${themeName}_$sizeName${scale == 1 ? '' : '_130'}',
            );
            expect(tester.takeException(), isNull);
            expect(find.textContaining('Good evening, Nikhil'), findsOneWidget);
          },
        );
      }
    }
  }

  testWidgets('tapping a starter sends it, long-press edits it', (
    tester,
  ) async {
    final rig = await _pump(
      tester,
      size: const Size(412, 915),
      theme: AppTheme.light,
    );
    await tester.tap(find.text('Explain media player crash causes'));
    expect(rig.sent, ['Explain media player crash causes']);
    await tester.longPress(find.text('Detail Flutter video playback bugs'));
    expect(rig.edited, ['Detail Flutter video playback bugs']);
  });

  testWidgets('shuffle shows different suggestions', (tester) async {
    await _pump(tester, size: const Size(412, 915), theme: AppTheme.light);
    expect(find.text('Explain a concept'), findsNothing);
    await tester.tap(find.bySemanticsLabel(HomeStrings.shuffle));
    await tester.pump();
    expect(find.text('Explain media player crash causes'), findsNothing);
  });

  testWidgets('capability chips report the capability', (tester) async {
    final rig = await _pump(
      tester,
      size: const Size(412, 915),
      theme: AppTheme.light,
    );
    await tester.tap(find.text(HomeStrings.capDoc));
    await tester.tap(find.text(HomeStrings.capTable));
    expect(rig.caps, [HomeCapability.doc, HomeCapability.roundTable]);
  });

  testWidgets('continue row opens the chat', (tester) async {
    final rig = await _pump(
      tester,
      size: const Size(412, 915),
      theme: AppTheme.dark,
    );
    await tester.tap(find.text('Media player crash causes'));
    expect(rig.opened, ['a']);
  });

  testWidgets('greeting follows the time of day', (tester) async {
    expect(greetingFor(DateTime(2026, 1, 1, 8)), HomeStrings.morning);
    expect(greetingFor(DateTime(2026, 1, 1, 14)), HomeStrings.afternoon);
    expect(greetingFor(DateTime(2026, 1, 1, 19)), HomeStrings.evening);
    expect(greetingFor(DateTime(2026, 1, 1, 2)), HomeStrings.night);
    expect(kindOfPrompt('Compare A vs B'), StarterKind.compare);
  });
}
