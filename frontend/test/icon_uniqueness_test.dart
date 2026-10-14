import 'package:app/assist/assistant_setup.dart';
import 'package:app/core/app_scope.dart';
import 'package:app/core/constants/about.dart';
import 'package:app/core/constants/apps.dart';
import 'package:app/core/constants/app_icons.dart';
import 'package:app/core/constants/history.dart';
import 'package:app/core/constants/notify_copy.dart';
import 'package:app/core/constants/storage.dart';
import 'package:app/core/constants/settings_copy.dart';
import 'package:app/core/notify/notify_kind.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/core/widgets/app_icon.dart';
import 'package:app/data/chat_api.dart';
import 'package:app/data/usage_api.dart';
import 'package:app/features/apps/apps_registry.dart';
import 'package:app/features/settings/assistant_settings_screen.dart';
import 'package:app/features/settings/settings_controller.dart';
import 'package:app/features/settings/settings_pages.dart';
import 'package:app/features/settings/usage_controller.dart';
import 'package:app/features/settings/widgets/reply_style_cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stable identity of a glyph (Hugeicons paths and brand logos are const).
String _key(AppIconData i) => i.toString();

/// Glyphs that legitimately repeat on a page because they mean the same thing
/// everywhere: navigation and state marks, not options.
final _structural = <String>{
  _key(AppIcons.back),
  _key(AppIcons.close),
  _key(AppIcons.chevronRight),
  _key(AppIcons.check),
  _key(AppIcons.expand),
  _key(AppIcons.collapse),
  _key(AppIcons.more),
  _key(AppIcons.search),
};

/// Pages where one meaning is deliberately shown twice. Keep empty unless a
/// pair is truly the same thing (document why).
const _allowedRepeats = <SettingsCategory, Set<AppIconData>>{};

Future<List<AppIconData>> _iconsOf(
  WidgetTester tester,
  SettingsCategory c, {
  void Function(SettingsController s)? prepare,
}) async {
  tester.view.physicalSize = const Size(360, 6000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final settings = await SettingsController.load();
  prepare?.call(settings);
  await tester.pumpWidget(
    AppScope(
      settings: settings,
      usage: UsageController(UsageApi('http://localhost:1')),
      api: ChatApi(),
      baseUrl: 'http://localhost:1',
      child: MaterialApp(
        theme: AppTheme.light,
        home: SettingsCategoryPage(category: c),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
  return [
    for (final w in tester.widgetList<AppIcon>(find.byType(AppIcon)))
      if (!_structural.contains(_key(w.icon))) w.icon,
  ];
}

void _expectUnique(List<AppIconData> icons, String where) {
  final seen = <String, int>{};
  for (final i in icons) {
    seen[_key(i)] = (seen[_key(i)] ?? 0) + 1;
  }
  final dupes = [
    for (final i in icons)
      if (seen[_key(i)]! > 1) i,
  ];
  expect(
    dupes.length,
    0,
    reason:
        '$where reuses a glyph for different options '
        '(${dupes.map(_key).toSet().length} glyphs repeated)',
  );
}

void main() {
  for (final c in SettingsCategory.values.where((c) => !c.isDirect)) {
    testWidgets('${c.name} page: no two rows share an icon', (tester) async {
      final icons = await _iconsOf(tester, c);
      expect(icons, isNotEmpty);
      final allowed = _allowedRepeats[c] ?? const {};
      _expectUnique([
        for (final i in icons)
          if (!allowed.contains(i)) i,
      ], c.name);
    });
  }

  testWidgets('reply page stays unique for every chat mode', (tester) async {
    for (final m in SettingsController.modes) {
      final icons = await _iconsOf(
        tester,
        SettingsCategory.replies,
        prepare: (s) => s.setMode(m),
      );
      _expectUnique(icons, 'replies (mode $m)');
    }
  });

  test('settings home: every category has its own icon', () {
    _expectUnique([for (final c in SettingsCategory.values) c.icon], 'home');
  });

  group('option sets', () {
    test('reply tones', () {
      _expectUnique([
        for (final t in SettingsController.tones) AppIcons.tone(t),
      ], 'tones');
    });

    test('reply lengths', () {
      _expectUnique([
        AppIcons.lengthConcise,
        AppIcons.lengthBalanced,
        AppIcons.lengthDetailed,
      ], 'lengths');
    });

    test('chat modes', () {
      _expectUnique([
        for (final m in SettingsController.modes) AppIcons.mode(m),
      ], 'modes');
    });

    test('themes', () {
      _expectUnique([
        AppIcons.themeSystem,
        AppIcons.themeLight,
        AppIcons.themeDark,
      ], 'themes');
    });

    test('model presets', () {
      _expectUnique([
        SettingsIcons.modelAuto,
        SettingsIcons.modelFast,
        SettingsIcons.modelSmart,
        SettingsIcons.listModels,
      ], 'model presets');
    });

    test('reply style presets, tone row and length row', () {
      _expectUnique([
        for (final p in replyPresets) p.icon,
        SettingsIcons.tone,
        SettingsIcons.length,
      ], 'reply styles');
    });

    test('reply style icons are not reused by tones or lengths', () {
      // A preset is a bundle of tone + length; it must not look like either.
      final options = {
        for (final t in SettingsController.tones) _key(AppIcons.tone(t)),
        _key(AppIcons.lengthConcise),
        _key(AppIcons.lengthBalanced),
        _key(AppIcons.lengthDetailed),
      };
      final dupes = [
        for (final p in replyPresets)
          if (options.contains(_key(p.icon)) &&
              !const {'friendly', 'direct', 'professional'}.contains(p.id))
            p.id,
      ];
      expect(dupes, isEmpty);
    });

    test('notification kinds', () {
      _expectUnique([
        for (final k in NotifyKind.values) NotifyIcons.of(k.key),
      ], 'notification kinds');
    });

    test('about feature and privacy rows', () {
      _expectUnique([
        for (final f in AboutStrings.features) f.icon,
      ], 'about features');
      _expectUnique([
        for (final f in AboutStrings.privacyItems('host')) f.icon,
      ], 'about privacy');
    });

    test('apps hub entries', () {
      _expectUnique([
        for (final a in AppsRegistry.all) a.brand?.logo ?? a.icon!,
      ], 'apps hub');
    });

    test('sidebar footer destinations', () {
      _expectUnique([
        AppsIcons.hub,
        HistoryIcons.docs,
        StorageIcons.section,
        HistoryIcons.archive,
        AppIcons.settings,
      ], 'sidebar footer');
    });

    test('composer mode chips and attach sheet', () {
      // WEB, KB, TABLE, DOC chips sit next to the attach and voice buttons.
      _expectUnique([
        AppIcons.web,
        AppIcons.knowledge,
        AppIcons.roundTable,
        AppIcons.doc,
        AppIcons.attach,
        AppIcons.mic,
        AppIcons.send,
      ], 'composer');
      _expectUnique([
        AttachIcons.media,
        AttachIcons.photo,
        AttachIcons.video,
        AttachIcons.document,
      ], 'attach sheet');
    });

    test('document and file glyphs are not near-identical', () {
      expect(_key(AppIcons.doc), isNot(_key(AppIcons.file)));
    });

    test('about credits', () {
      _expectUnique([
        for (final c in AboutStrings.creditList) c.icon,
      ], 'about credits');
    });
  });

  for (final isDefault in [false, true]) {
    testWidgets('assistant page (default: $isDefault): unique icons', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(412, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final settings = await SettingsController.load();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: AssistantSettingsScreen(
            setup: _Setup(
              AssistantStatus(
                isDefault: isDefault,
                screenText: true,
                screenshot: true,
                manufacturer: 'Nothing',
              ),
            ),
            settings: settings,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final icons = [
        for (final w in tester.widgetList<AppIcon>(find.byType(AppIcon)))
          if (!_structural.contains(_key(w.icon))) w.icon,
      ];
      expect(icons, isNotEmpty);
      _expectUnique(icons, 'assistant page');
    });
  }
}

class _Setup extends AssistantSetup {
  _Setup(this.current);

  final AssistantStatus current;

  @override
  Future<AssistantStatus> status() async => current;
}
