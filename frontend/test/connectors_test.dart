import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/core/app_scope.dart';
import 'package:app/core/constants/apps.dart';
import 'package:app/core/constants/connectors.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/chat_api.dart';
import 'package:app/data/connect_api.dart';
import 'package:app/data/connections_api.dart';
import 'package:app/data/usage_api.dart';
import 'package:app/features/apps/apps_screen.dart';
import 'package:app/features/chat/chat_launch.dart';
import 'package:app/features/connections/connections_controller.dart';
import 'package:app/features/connectors/connector_auth.dart';
import 'package:app/features/connectors/drive_screen.dart';
import 'package:app/features/connectors/notion_screen.dart';
import 'package:app/features/settings/settings_controller.dart';
import 'package:app/features/settings/usage_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/github_fakes.dart';
import 'support/shot.dart';

const _themes = [('light', false), ('dark', true)];
final _now = DateTime(2026, 10, 13, 12);

/// Fake backend for the connected apps.
class FakeConnectApi extends ConnectApi {
  FakeConnectApi({
    this.files = const [],
    this.pages = const [],
    this.page,
    this.error,
  });

  List<Map<String, dynamic>> files;
  List<Map<String, dynamic>> pages;
  Map<String, dynamic>? page;
  ConnectException? error;
  final calls = <String>[];

  @override
  Future<List<DriveFile>> driveFiles({String query = ''}) async {
    calls.add('driveFiles:$query');
    if (error != null) throw error!;
    return [
      for (final f in files)
        if (query.isEmpty ||
            (f['name'] as String).toLowerCase().contains(query.toLowerCase()))
          DriveFile(f),
    ];
  }

  @override
  Future<List<NotionItem>> notionSearch({
    String query = '',
    String? kind,
  }) async {
    calls.add('notionSearch:$query');
    if (error != null) throw error!;
    return [
      for (final p in pages)
        if (query.isEmpty ||
            (p['title'] as String).toLowerCase().contains(query.toLowerCase()))
          NotionItem(p),
    ];
  }

  @override
  Future<NotionPage> notionRead(String id) async {
    calls.add('notionRead:$id');
    return NotionPage(page!);
  }

  @override
  Future<void> notionToKnowledge(String id) async =>
      calls.add('notionToKnowledge:$id');
}

String _ago(Duration d) => _now.subtract(d).toUtc().toIso8601String();

final _files = [
  {
    'id': 'f1',
    'name': 'Q4 roadmap',
    'mimeType': 'application/vnd.google-apps.document',
    'modifiedTime': _ago(const Duration(hours: 3)),
    'kind': 'markdown',
    'webViewLink': 'https://docs.google.com/document/d/f1',
  },
  {
    'id': 'f2',
    'name': 'Budget 2026',
    'mimeType': 'application/vnd.google-apps.spreadsheet',
    'modifiedTime': _ago(const Duration(days: 2)),
    'kind': 'csv',
  },
  {
    'id': 'f3',
    'name': 'Sodium limits study.pdf',
    'mimeType': 'application/pdf',
    'modifiedTime': _ago(const Duration(days: 9)),
    'kind': 'pdf',
  },
  {
    'id': 'f4',
    'name': 'Launch notes.md',
    'mimeType': 'text/markdown',
    'modifiedTime': _ago(const Duration(days: 30)),
    'kind': 'text',
  },
];

final _pages = [
  {
    'id': '11111111-1111-1111-1111-111111111111',
    'object': 'page',
    'title': 'Product roadmap',
    'icon': null,
    'url': 'https://www.notion.so/roadmap',
    'lastEdited': _ago(const Duration(hours: 1)),
  },
  {
    'id': '22222222-2222-2222-2222-222222222222',
    'object': 'page',
    'title': 'Weekly sync notes',
    'icon': null,
    'url': 'https://www.notion.so/sync',
    'lastEdited': _ago(const Duration(days: 1)),
  },
  {
    'id': '33333333-3333-3333-3333-333333333333',
    'object': 'database',
    'title': 'Reading list',
    'icon': null,
    'url': 'https://www.notion.so/reading',
    'lastEdited': _ago(const Duration(days: 4)),
  },
  {
    'id': '44444444-4444-4444-4444-444444444444',
    'object': 'page',
    'title': 'Offsite plan',
    'icon': null,
    'url': 'https://www.notion.so/offsite',
    'lastEdited': _ago(const Duration(days: 12)),
  },
];

const _pageBody = '''
## Goals

- Ship **Apps**: Google Drive and Notion
- Cut cold start below 1.2 s
- [x] Pick files with Google's picker

## Timeline

| Month | Milestone |
| --- | --- |
| Oct | Connectors |
| Nov | Offline mode |

> Keep the scope small.
''';

/// Connections: GitHub always; Drive / Notion as asked.
void _fakeState({
  bool drive = false,
  bool notion = false,
  bool driveConfigured = true,
  bool notionConfigured = true,
  bool driveReauth = false,
}) {
  ConnectionsController.instance.state = ConnectionsState({
    'items': [
      {
        'provider': 'github',
        'accountLogin': 'nickrivera',
        'avatarUrl': '',
        'scopes': ['repo'],
      },
      if (drive)
        {
          'provider': 'google_drive',
          'accountLogin': 'nick.rivera@gmail.com',
          'accountName': 'Nick Rivera',
          'accountEmail': 'nick.rivera@gmail.com',
          'avatarUrl': '',
          'needsReauth': driveReauth,
        },
      if (notion)
        {
          'provider': 'notion',
          'accountLogin': 'nick@rivera.studio',
          'accountName': 'Nick Rivera',
          'accountEmail': 'nick@rivera.studio',
          'avatarUrl': '',
          'meta': {'workspaceName': 'Rivera Studio', 'workspaceIcon': ''},
        },
    ],
    'providers': {
      'github': {'configured': true, 'web': true},
      'google_drive': {'configured': driveConfigured, 'picker': true},
      'notion': {'configured': notionConfigured},
    },
    'isOwner': false,
  });
}

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  bool dark = false,
}) async {
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

/// Review screenshot (outside the repo) plus the committed golden.
Future<void> _capture(WidgetTester tester, String name) async {
  final view = tester.binding.renderViews.first;
  final layer = view.debugLayer! as OffsetLayer;
  final size = tester.view.physicalSize;
  await tester.runAsync(() async {
    final image = await layer.toImage(Offset.zero & size);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(shotDir).createSync(recursive: true);
    File('$shotDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/$name.png'),
  );
}

void main() {
  late FakeConnectApi api;

  setUpAll(() async {
    await loadAppFonts();
    seedIcons();
  });

  setUp(() {
    api = FakeConnectApi(files: _files, pages: _pages);
    ConnectApi.instance = api;
  });

  tearDown(() {
    ConnectionsController.instance.state = null;
    ConnectorAuth.instance.cancel();
  });

  for (final (name, dark) in _themes) {
    testWidgets('apps hub with Drive and Notion ($name)', (tester) async {
      _fakeState(drive: true);
      await _pump(tester, AppsScreen(sourceCount: () async => 7), dark: dark);
      await _capture(tester, 'connectors_apps_hub_$name');
      expect(find.text(AppsStrings.googleDrive), findsOneWidget);
      expect(find.text('nick.rivera@gmail.com'), findsOneWidget);
      expect(find.text(AppsStrings.notion), findsOneWidget);
      expect(find.text(AppsStrings.connect), findsOneWidget);
    });

    testWidgets('drive not connected ($name)', (tester) async {
      _fakeState();
      await _pump(tester, DriveScreen(now: _now), dark: dark);
      await _capture(tester, 'connectors_drive_disconnected_$name');
      expect(find.text(DriveStrings.permTitle), findsOneWidget);
      expect(find.text(ConnectorStrings.continueTo('Google')), findsOneWidget);
      expect(api.calls, isEmpty);
    });

    testWidgets('drive connected with files ($name)', (tester) async {
      _fakeState(drive: true);
      await _pump(tester, DriveScreen(now: _now), dark: dark);
      await _capture(tester, 'connectors_drive_files_$name');
      expect(find.text('Nick Rivera'), findsOneWidget);
      expect(find.text(DriveStrings.pick), findsOneWidget);
      expect(find.text('Q4 roadmap'), findsOneWidget);
      expect(find.text('Google Doc · 3h ago'), findsOneWidget);
    });

    testWidgets('notion not connected ($name)', (tester) async {
      _fakeState();
      await _pump(tester, NotionScreen(now: _now), dark: dark);
      await _capture(tester, 'connectors_notion_disconnected_$name');
      expect(find.text(NotionStrings.permTitle), findsOneWidget);
      expect(find.text(ConnectorStrings.continueTo('Notion')), findsOneWidget);
    });

    testWidgets('notion connected with pages ($name)', (tester) async {
      _fakeState(notion: true);
      await _pump(tester, NotionScreen(now: _now), dark: dark);
      await _capture(tester, 'connectors_notion_pages_$name');
      expect(find.text('Rivera Studio'), findsOneWidget);
      expect(find.text('Product roadmap'), findsOneWidget);
      expect(find.text(NotionStrings.database), findsOneWidget);
    });

    testWidgets('notion page reader ($name)', (tester) async {
      _fakeState(notion: true);
      api.page = {..._pages.first, 'markdown': _pageBody};
      await _pump(
        tester,
        NotionPageScreen(item: NotionItem(_pages.first)),
        dark: dark,
      );
      await _capture(tester, 'connectors_notion_reader_$name');
      expect(find.text(ConnectorStrings.askSparky), findsOneWidget);
      expect(find.text('Goals'), findsOneWidget);
    });
  }

  testWidgets('not set up on this server', (tester) async {
    _fakeState(notionConfigured: false);
    await _pump(tester, const NotionScreen());
    expect(find.text(ConnectorStrings.notSetUp), findsOneWidget);
    expect(find.text(ConnectorStrings.continueTo('Notion')), findsNothing);
  });

  testWidgets('apps hub tags an app the server lacks', (tester) async {
    _fakeState(notionConfigured: false);
    await _pump(tester, AppsScreen(sourceCount: () async => 0));
    expect(find.text(ConnectorStrings.notSetUpTag), findsOneWidget);
    expect(find.text(ConnectorStrings.notSetUp), findsOneWidget);
  });

  testWidgets('expired Drive access asks to reconnect', (tester) async {
    _fakeState(drive: true, driveReauth: true);
    await _pump(tester, DriveScreen(now: _now));
    expect(find.text(ConnectorStrings.expiredTitle), findsOneWidget);
    expect(find.text(ConnectorStrings.reconnectTag), findsOneWidget);
    expect(find.text(DriveStrings.pick), findsNothing);
  });

  testWidgets('offline keeps the last files with a retry banner', (
    tester,
  ) async {
    _fakeState(drive: true);
    await _pump(tester, DriveScreen(now: _now));
    expect(find.text('Budget 2026'), findsOneWidget);
    api.error = const ConnectException(ConnectorStrings.offline, offline: true);
    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, 400),
      1000,
    );
    await _settle(tester);
    await tester.pump(const Duration(seconds: 1));
    await _settle(tester);
    expect(find.text(ConnectorStrings.offline), findsOneWidget);
    expect(find.text('Budget 2026'), findsOneWidget);
  });

  testWidgets('notion search filters the shared pages', (tester) async {
    _fakeState(notion: true);
    await _pump(tester, NotionScreen(now: _now));
    await tester.enterText(find.byType(TextField), 'sync');
    await tester.pump(const Duration(milliseconds: 400));
    await _settle(tester);
    expect(api.calls, contains('notionSearch:sync'));
    expect(find.text('Weekly sync notes'), findsOneWidget);
    expect(find.text('Product roadmap'), findsNothing);
    expect(find.text(NotionStrings.results), findsOneWidget);
  });

  testWidgets('ask sparky starts a chat that carries the page', (tester) async {
    _fakeState(notion: true);
    api.page = {..._pages.first, 'markdown': _pageBody};
    await _pump(tester, NotionPageScreen(item: NotionItem(_pages.first)));
    await tester.tap(find.text(ConnectorStrings.askSparky));
    await _settle(tester);
    expect(ChatLaunch.instance.prompt.value, contains('Product roadmap'));
    expect(ChatLaunch.instance.apps.single, {
      'provider': 'notion',
      'id': '11111111-1111-1111-1111-111111111111',
      'title': 'Product roadmap',
    });
    ChatLaunch.instance.prompt.value = null;
  });

  test('a stray or replayed connect link is ignored', () async {
    SharedPreferences.setMockInitialValues({});
    await ConnectorAuth.instance.handleLink(
      Uri.parse('sparky://auth/connect?provider=notion&ticket=x&state=nope'),
    );
    expect(ConnectorAuth.instance.phase, ConnectorPhase.idle);
  });
}
