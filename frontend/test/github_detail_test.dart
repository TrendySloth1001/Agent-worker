import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/core/app_scope.dart';
import 'package:app/core/constants/apps.dart';
import 'package:app/core/constants/github_detail.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/chat_api.dart';
import 'package:app/data/github_api.dart';
import 'package:app/data/usage_api.dart';
import 'package:app/features/chat/chat_launch.dart';
import 'package:app/features/connections/connections_controller.dart';
import 'package:app/features/github/commit_screen.dart';
import 'package:app/features/github/gh_item_controller.dart';
import 'package:app/features/github/github_screen.dart';
import 'package:app/features/github/issue_screen.dart';
import 'package:app/features/github/pr_screen.dart';
import 'package:app/features/github/widgets/gh_activity.dart';
import 'package:app/features/settings/settings_controller.dart';
import 'package:app/features/settings/usage_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/github_detail_fakes.dart';
import 'support/github_fakes.dart';
import 'support/shot.dart';

const _themes = [('light', false), ('dark', true)];

/// Pumps [home] on a 412x915 phone (dpr 2.6) under the app's scope; a
/// first route sits below so "Ask Sparky" has a chat to return to.
Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  bool dark = false,
  double height = 915,
}) async {
  tester.view.physicalSize = Size(412, height) * 2.6;
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
        theme: dark ? AppTheme.dark : AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute<void>(builder: (_) => home)),
                child: const Text('chat'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('chat'));
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

/// A review screenshot (outside the repo) of the whole 2.6x frame.
Future<void> _peek(WidgetTester tester, String name) async {
  final view = tester.binding.renderViews.first;
  final layer = view.debugLayer! as OffsetLayer;
  final size = tester.view.physicalSize;
  await tester.runAsync(() async {
    final image = await layer.toImage(Offset.zero & size);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(shotDir).createSync(recursive: true);
    File('$shotDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Future<void> _golden(WidgetTester tester, String name) async {
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/$name.png'),
  );
}

Widget _pr({FakeDetailGithubApi? api, int tab = 0}) => GithubPullScreen(
  owner: 'nickrivera',
  repo: 'sparky',
  number: 214,
  seedTitle: 'Add the Apps hub and GitHub screen',
  api: api ?? FakeDetailGithubApi(),
  initialTab: tab,
);

Widget _issue({FakeDetailGithubApi? api}) => GithubIssueScreen(
  owner: 'nickrivera',
  repo: 'sparky',
  number: 198,
  api: api ?? FakeDetailGithubApi(),
);

void main() {
  setUpAll(() async {
    await loadAppFonts();
    seedIcons();
  });

  setUp(() {
    GhItemController.clearMemo();
    GithubApi.instance = FakeDetailGithubApi();
    fakeConnected();
    ChatLaunch.instance.prompt.value = null;
  });

  tearDown(() {
    ConnectionsController.instance.state = null;
  });

  // ---- goldens ---------------------------------------------------------------

  for (final (name, dark) in _themes) {
    const tabs = ['conversation', 'commits', 'files', 'checks'];
    for (var t = 0; t < tabs.length; t++) {
      testWidgets('pull request ${tabs[t]} ($name)', (tester) async {
        await _pump(tester, _pr(tab: t), dark: dark);
        // Below the header: the tab's content.
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -420));
        await _settle(tester);
        await _golden(tester, 'github_pr_${tabs[t]}_$name');
        await _peek(tester, 'github_pr_${tabs[t]}_$name');
      });
    }

    testWidgets('pull request header ($name)', (tester) async {
      await _pump(tester, _pr(), dark: dark);
      await _golden(tester, 'github_pr_header_$name');
    });

    testWidgets('issue detail ($name)', (tester) async {
      await _pump(tester, _issue(), dark: dark);
      await _golden(tester, 'github_issue_$name');
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
      await _settle(tester);
      await _peek(tester, 'github_issue_scrolled_$name');
    });

    testWidgets('repo search field ($name)', (tester) async {
      await _pump(tester, const GithubScreen(), dark: dark);
      await _golden(tester, 'github_repo_search_$name');
      await tester.enterText(find.byType(TextField), 'sparky');
      await _settle(tester);
      await _golden(tester, 'github_repo_search_typed_$name');
      await tester.enterText(find.byType(TextField), 'zzzz');
      await _settle(tester);
      await _peek(tester, 'github_repo_search_empty_$name');
    });

    testWidgets('activity feed ($name)', (tester) async {
      await _pump(tester, const GithubScreen(), dark: dark);
      await tester.tap(find.text(GithubHubStrings.tabActivity));
      await _settle(tester);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await _settle(tester);
      await _peek(tester, 'github_activity_feed_$name');
      expect(find.text(GhActivityStrings.today), findsOneWidget);
      expect(find.text(GhActivityStrings.yesterday), findsOneWidget);
    });

    testWidgets('commit detail ($name)', (tester) async {
      await _pump(
        tester,
        GithubCommitScreen(
          owner: 'nickrivera',
          repo: 'sparky',
          sha: 'a1b2c3d4e5f6a7b8',
          api: FakeDetailGithubApi(),
        ),
        dark: dark,
      );
      await _peek(tester, 'github_commit_$name');
      expect(find.text('github_screen.dart'), findsOneWidget);
      expect(find.text(GhDetailStrings.askSparky), findsOneWidget);
    });
  }

  // ---- behavior ----------------------------------------------------------------

  testWidgets('a pull request row opens the in-app screen', (tester) async {
    await _pump(tester, const GithubScreen());
    await tester.tap(find.text(GithubHubStrings.tabPulls));
    await _settle(tester);
    await tester.tap(find.text('Add the Apps hub and GitHub screen'));
    await _settle(tester);
    expect(find.byType(GithubPullScreen), findsOneWidget);
    expect(find.text(GhDetailStrings.tabConversation), findsOneWidget);
  });

  testWidgets('an issue row opens the in-app screen', (tester) async {
    await _pump(tester, const GithubScreen());
    await tester.tap(find.text(GithubHubStrings.tabIssues));
    await _settle(tester);
    await tester.tap(find.text('Voice input stops after a long pause'));
    await _settle(tester);
    expect(find.byType(GithubIssueScreen), findsOneWidget);
  });

  testWidgets('activity items open pull requests and commits in-app', (
    tester,
  ) async {
    await _pump(tester, const GithubScreen());
    await tester.tap(find.text(GithubHubStrings.tabActivity));
    await _settle(tester);
    await tester.tap(find.text('Add the Apps hub and GitHub screen'));
    await _settle(tester);
    expect(find.byType(GithubPullScreen), findsOneWidget);
    await tester.pageBack();
    await _settle(tester);
    await tester.tap(find.text('feat(app): Apps hub with connectors'));
    await _settle(tester);
    expect(find.byType(GithubCommitScreen), findsOneWidget);
  });

  testWidgets('Ask Sparky on a pull request starts a chat with its context', (
    tester,
  ) async {
    await _pump(tester, _pr());
    await tester.tap(find.text(GhDetailStrings.askSparky));
    await _settle(tester);
    final prompt = ChatLaunch.instance.prompt.value!;
    expect(prompt, contains('nickrivera/sparky#214'));
    expect(prompt, contains('Add the Apps hub and GitHub screen'));
    // Back on the chat (the first route).
    expect(find.byType(GithubPullScreen), findsNothing);
    expect(find.text('chat'), findsOneWidget);
  });

  testWidgets('Ask Sparky on an issue, a file and an activity item', (
    tester,
  ) async {
    await _pump(tester, _issue());
    await tester.tap(find.byTooltip(GhDetailStrings.askSparky));
    await _settle(tester);
    expect(ChatLaunch.instance.prompt.value, contains('issue #198'));
    expect(ChatLaunch.instance.prompt.value, contains('nickrivera/sparky'));

    ChatLaunch.instance.prompt.value = null;
    await _pump(tester, _pr(tab: 2));
    await tester.tap(find.byTooltip(GhDetailStrings.askFile).first);
    await _settle(tester);
    expect(
      ChatLaunch.instance.prompt.value,
      contains('lib/features/github/github_screen.dart'),
    );

    final a = GhActivity(fakeEvents[1]);
    expect(activityPrompt(a), contains('nickrivera/sparky#214'));
  });

  testWidgets('posting a comment calls GitHub and reloads', (tester) async {
    final api = FakeDetailGithubApi();
    await _pump(tester, _pr(api: api));
    await tester.scrollUntilVisible(
      find.text(GhDetailStrings.commentHint),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.widgetWithText(TextField, GhDetailStrings.commentHint),
      'Ship it',
    );
    await tester.pump();
    await tester.tap(find.text(GhDetailStrings.send));
    await _settle(tester);
    expect(api.writes, ['comment:Ship it']);
    expect(find.text(GhDetailStrings.commentPosted), findsOneWidget);
  });

  testWidgets('merge runs the chosen method', (tester) async {
    final api = FakeDetailGithubApi();
    await _pump(tester, _pr(api: api));
    await tester.tap(find.text(GhDetailStrings.merge));
    await _settle(tester);
    expect(find.text(GhDetailStrings.mergeTitle), findsOneWidget);
    expect(find.text(GhDetailStrings.mergeRebase), findsNothing);
    await _peek(tester, 'github_pr_merge_sheet_light');
    await tester.tap(find.text(GhDetailStrings.mergeSquash).last);
    await _settle(tester);
    expect(api.writes, ['merge:squash']);
  });

  testWidgets('read-only access: banner, dimmed actions that explain why', (
    tester,
  ) async {
    final api = FakeDetailGithubApi(
      pull: pullJson(
        can: readOnly,
        why: {for (final k in readOnly.keys) k: scopeReason},
        needsReconnect: true,
      ),
    );
    await _pump(tester, _pr(api: api));
    await _peek(tester, 'github_pr_readonly_light');
    expect(find.text(GhDetailStrings.readOnlyTitle), findsOneWidget);
    await tester.tap(find.text(GhDetailStrings.merge));
    await tester.pump();
    expect(find.text(scopeReason), findsOneWidget);
    expect(
      find.widgetWithText(SnackBarAction, GhDetailStrings.reconnect),
      findsOneWidget,
    );
    expect(api.writes, isEmpty);
  });

  testWidgets('a refused write shows the reason with Reconnect', (
    tester,
  ) async {
    final api = FakeDetailGithubApi(
      failWrite: const GhApiException(
        "Your GitHub token can't do this here. Reconnect GitHub with repo access.",
        status: 403,
        code: 'github_scope_missing',
      ),
    );
    await _pump(tester, _issue(api: api));
    await tester.tap(find.text(GhDetailStrings.close));
    await _settle(tester);
    await tester.tap(find.text(GhDetailStrings.closeNotPlanned));
    await _settle(tester);
    expect(api.writes, ['update:state=closed;reason=not_planned']);
    expect(find.textContaining("can't do this here"), findsOneWidget);
    expect(
      find.widgetWithText(SnackBarAction, GhDetailStrings.reconnect),
      findsOneWidget,
    );
  });

  testWidgets('labels are picked from the repository and saved', (
    tester,
  ) async {
    final api = FakeDetailGithubApi();
    await _pump(tester, _issue(api: api));
    await tester.tap(find.byTooltip(GhDetailStrings.labels));
    await _settle(tester);
    await tester.tap(find.text('feature'));
    await tester.pump();
    await tester.tap(find.text(GhDetailStrings.save));
    await _settle(tester);
    expect(api.writes.single, startsWith('update:labels='));
    expect(api.writes.single, contains('feature'));
  });

  testWidgets('a failed refresh keeps the saved data with a banner', (
    tester,
  ) async {
    await _pump(tester, _pr());
    await tester.pageBack();
    await _settle(tester);
    // Same pull request again, now failing: the memo shows the old data.
    await _pump(tester, _pr(api: _FailingApi()));
    expect(find.text('Add the Apps hub and GitHub screen'), findsWidgets);
    expect(find.text(GhDetailStrings.staleTitle), findsOneWidget);
  });

  test('the repo search waits for typing to pause', () async {
    // Debounce is shorter than the settle loop in the widget tests.
    expect(GithubHubDurations.debounce.inMilliseconds, lessThan(600));
  });
}

class _FailingApi extends FakeDetailGithubApi {
  @override
  Future<GhItemDetail> pullDetail(String owner, String repo, int n) async =>
      throw const GhApiException(
        'GitHub rate limit reached until 10:20 UTC',
        status: 429,
        code: 'rate_limited',
      );
}
