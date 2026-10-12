import 'package:app/core/app_scope.dart';
import 'package:app/core/constants/apps.dart';
import 'package:app/core/constants/history.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/chat_api.dart';
import 'package:app/data/github_api.dart';
import 'package:app/features/apps/apps_screen.dart';
import 'package:app/features/connections/connections_controller.dart';
import 'package:app/features/github/github_controller.dart';
import 'package:app/features/github/github_repo_screen.dart';
import 'package:app/features/github/github_screen.dart';
import 'package:app/features/history/widgets/history_footer.dart';
import 'package:app/features/knowledge/knowledge_screen.dart';
import 'package:app/features/settings/settings_controller.dart';
import 'package:app/features/settings/usage_controller.dart';
import 'package:app/data/usage_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/github_fakes.dart';
import 'support/shot.dart';

Finder _repo(String full) => find.text(full, findRichText: true);

const _themes = [('light', false), ('dark', true)];

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  bool dark = false,
  double height = 915,
}) async {
  // 412dp wide; the shot helper renders at 2x.
  tester.view.physicalSize = Size(412, height);
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
        debugShowCheckedModeBanner: false,
        theme: dark ? AppTheme.dark : AppTheme.light,
        home: home,
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
    seedIcons();
  });

  setUp(() {
    GithubApi.instance = FakeGithubApi();
    fakeConnected();
  });

  tearDown(() {
    ConnectionsController.instance.state = null;
  });

  for (final (name, dark) in _themes) {
    testWidgets('apps hub renders ($name)', (tester) async {
      await _pump(
        tester,
        AppsScreen(sourceCount: () async => 7),
        dark: dark,
      );
      await _settle(tester);
      await shot(tester, 'apps_hub_$name');
      expect(find.text(AppsStrings.title), findsWidgets);
      expect(find.text('@nickrivera'), findsOneWidget);
      expect(find.text(AppsStrings.knowledge), findsOneWidget);
      expect(find.text('7 sources'), findsOneWidget);
      expect(find.text(AppsStrings.memory), findsOneWidget);
      // Coming soon, below the fold on a short phone: scroll to it.
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
      await _settle(tester);
      await shot(tester, 'apps_hub_${name}_soon');
      expect(find.text(AppsStrings.googleDrive), findsOneWidget);
      expect(find.text(AppsStrings.slack), findsOneWidget);
      expect(find.text(AppsStrings.soon), findsWidgets);
    });
  }

  testWidgets('apps hub opens the knowledge base', (tester) async {
    await _pump(tester, AppsScreen(sourceCount: () async => 2));
    await _settle(tester);
    await tester.tap(find.text(AppsStrings.knowledge));
    await _settle(tester);
    expect(find.byType(KnowledgeScreen), findsOneWidget);
  });

  testWidgets('apps hub opens GitHub', (tester) async {
    await _pump(tester, AppsScreen(sourceCount: () async => 2));
    await _settle(tester);
    await tester.tap(find.text(AppsStrings.github));
    await _settle(tester);
    expect(find.byType(GithubScreen), findsOneWidget);
  });

  testWidgets('apps hub shows GitHub as not connected', (tester) async {
    fakeConnected(connected: false);
    await _pump(tester, AppsScreen(sourceCount: () async => 0));
    await _settle(tester);
    expect(find.text(AppsStrings.notConnected), findsOneWidget);
    expect(find.text(AppsStrings.noSources), findsOneWidget);
  });

  testWidgets('sidebar footer shows Apps instead of Knowledge', (tester) async {
    await _pump(
      tester,
      Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: HistoryFooter(
            archivedActive: false,
            compact: false,
            onApps: () {},
            onDocs: () {},
            onStorage: () {},
            onArchived: () {},
            onProfile: () {},
            onSettings: () {},
          ),
        ),
      ),
    );
    expect(find.text(HistoryStrings.apps), findsOneWidget);
    expect(find.text('Knowledge'), findsNothing);
    expect(find.text(HistoryStrings.docs), findsOneWidget);
    expect(find.text(HistoryStrings.storage), findsOneWidget);
    expect(find.text(HistoryStrings.archived), findsOneWidget);
  });

  for (final (name, dark) in _themes) {
    testWidgets('github screen renders connected ($name)', (tester) async {
      await _pump(tester, const GithubScreen(), dark: dark);
      await _settle(tester);
      await shot(tester, 'github_connected_$name');
      expect(find.text('Nick Rivera'), findsOneWidget);
      expect(find.text('@nickrivera'), findsOneWidget);
      expect(find.text(GithubHubStrings.connectedStatus), findsOneWidget);
      expect(find.text(GithubHubStrings.openOnGithub), findsOneWidget);
      expect(find.text(GithubHubStrings.reconnect), findsOneWidget);
      expect(find.text(GithubHubStrings.disconnect), findsOneWidget);
      expect(_repo('nickrivera/sparky'), findsOneWidget);
    });

    testWidgets('missing scopes ask for full access ($name)', (tester) async {
      fakeConnected(missingScopes: ['workflow', 'notifications']);
      await _pump(tester, const GithubScreen(), dark: dark);
      await _settle(tester);
      await shot(tester, 'github_full_access_$name');
      expect(find.text(GithubHubStrings.fullAccess), findsOneWidget);
      expect(find.text(GithubHubStrings.fullAccessHint), findsOneWidget);
    });

    testWidgets('github screen renders not connected ($name)', (tester) async {
      fakeConnected(connected: false);
      await _pump(tester, const GithubScreen(), dark: dark, height: 1100);
      await _settle(tester);
      await shot(tester, 'github_not_connected_$name');
      expect(find.text('Connect GitHub'), findsOneWidget);
      expect(find.text('CONNECT'), findsOneWidget);
      expect(find.text(GithubHubStrings.openOnGithub), findsNothing);
    });

    testWidgets('repo detail renders ($name)', (tester) async {
      await _pump(
        tester,
        GithubRepoScreen(seed: GhRepo(fakeRepos.first)),
        dark: dark,
        height: 1500,
      );
      await _settle(tester);
      await shot(tester, 'github_repo_$name');
      expect(find.text('nickrivera/sparky'), findsWidgets);
      expect(find.text(GithubRepoStrings.askSparky), findsOneWidget);
      expect(find.text(GithubRepoStrings.tabCommits), findsOneWidget);
      expect(find.textContaining('sparky-worker'), findsWidgets);
    });
  }

  testWidgets('github tabs load pull requests, issues and activity', (
    tester,
  ) async {
    await _pump(tester, const GithubScreen());
    await _settle(tester);
    await tester.tap(find.text(GithubHubStrings.tabPulls));
    await _settle(tester);
    await shot(tester, 'github_pulls_light');
    expect(find.text('Add the Apps hub and GitHub screen'), findsOneWidget);
    await tester.tap(find.text(GithubHubStrings.tabIssues));
    await _settle(tester);
    expect(find.text('Voice input stops after a long pause'), findsOneWidget);
    await tester.tap(find.text(GithubHubStrings.tabActivity));
    await _settle(tester);
    await shot(tester, 'github_activity_light');
    expect(
      find.text('feat(app): Apps hub with connectors'),
      findsOneWidget,
    );
  });

  testWidgets('repo search filters the list', (tester) async {
    await _pump(tester, const GithubScreen());
    await _settle(tester);
    await tester.enterText(find.byType(TextField), 'design');
    await _settle(tester);
    expect(_repo('cloudnsofts/design-tokens'), findsOneWidget);
    expect(_repo('nickrivera/dotfiles'), findsNothing);
    expect(_repo('nickrivera/sparky'), findsNothing);
    await shot(tester, 'github_search_light');
    await tester.enterText(find.byType(TextField), 'zzzz');
    await _settle(tester);
    expect(find.text(GithubHubStrings.noMatches), findsOneWidget);
  });

  test('repo filters and sorting', () async {
    final c = GithubHubController(api: FakeGithubApi());
    await c.load();
    expect(c.repos.length, fakeRepos.length);
    c.setFilter(RepoFilter.private);
    expect(c.filtered.map((r) => r.name), ['sparky-worker']);
    c.setFilter(RepoFilter.forks);
    expect(c.filtered.map((r) => r.name), ['flutter']);
    c.setFilter(RepoFilter.public);
    expect(c.filtered.any((r) => r.isPrivate), isFalse);
    c.setFilter(RepoFilter.all);
    c.setSort(RepoSort.stars);
    expect(c.filtered.first.name, 'platform');
    c.setSort(RepoSort.name);
    expect(c.filtered.first.fullName, 'cloudnsofts/design-tokens');
    c.setSort(RepoSort.pushed);
    expect(c.filtered.first.name, 'sparky');
    c.setQuery('go experiment');
    expect(c.filtered.every((r) => r.language == 'Go'), isTrue);
  });

  test('repo list grows a page at a time', () async {
    final c = GithubHubController(api: FakeGithubApi());
    await c.load();
    expect(c.shown.length, GithubHubSizes.reposPage);
    expect(c.hasMore, isTrue);
    c.showMore();
    expect(c.shown.length, fakeRepos.length);
    expect(c.hasMore, isFalse);
  });
}
