import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/core/app_scope.dart';
import 'package:app/core/constants/m3_copy.dart';
import 'package:app/core/constants/telemetry.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/chat_api.dart';
import 'package:app/data/telemetry.dart';
import 'package:app/data/telemetry_api.dart';
import 'package:app/data/usage_api.dart';
import 'package:app/features/settings/settings_controller.dart';
import 'package:app/features/settings/telemetry/telemetry_grouping.dart';
import 'package:app/features/settings/telemetry/telemetry_screen.dart';
import 'package:app/features/settings/telemetry/telemetry_widgets.dart';
import 'package:app/features/settings/telemetry/users_screen.dart';
import 'package:app/features/settings/usage_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/render.dart';

/// Set `--dart-define=TEL_SHOTS=/some/dir` to write review screenshots.
const _shots = String.fromEnvironment('TEL_SHOTS');

Map<String, dynamic> _agg(
  int requests,
  int failed, {
  int p50 = 840,
  int unknown = 0,
}) => {
  'requests': requests,
  'ok': requests - failed - unknown,
  'failed': failed,
  'unknown': unknown,
  'failureRate': requests == 0 ? 0 : failed / requests,
  'tokensIn': 3200 * requests,
  'tokensOut': 480 * requests,
  'latencyP50': p50,
  'latencyP95': p50 * 3,
  'ttftP50': 320,
  'ttftAvg': 410,
  'latencyAvg': p50 + 60,
  'lastAt': DateTime.now()
      .subtract(const Duration(minutes: 2))
      .toUtc()
      .toIso8601String(),
};

List<double> _spark(int seed) => [
  for (var i = 0; i < 24; i++) 4 + ((i * seed) % 9) + (i > 16 ? i - 16 : 0),
];

class _FakeTelemetry implements TelemetryApi {
  final List<TelemetryFilters> overviewCalls = [];

  @override
  String get baseUrl => 'http://localhost:1';

  @override
  Future<TelemetryOverview> overview(String window, TelemetryFilters f) async {
    overviewCalls.add(f);
    final groqOnly = f.provider == 'groq';
    return TelemetryOverview.fromJson({
      'window': window,
      'totals': _agg(groqOnly ? 1480 : 2310, groqOnly ? 61 : 187, unknown: 24),
      'providers': [
        {'provider': 'groq', ..._agg(1480, 61), 'spark': _spark(3)},
        if (!groqOnly) ...[
          {
            'provider': 'nvidia',
            ..._agg(620, 98, p50: 1900),
            'spark': _spark(5),
          },
          {
            'provider': 'openrouter',
            ..._agg(140, 6, p50: 1200),
            'spark': _spark(7),
          },
          {'provider': 'tavily', ..._agg(70, 22, p50: 700), 'spark': _spark(2)},
        ],
      ],
      'models': [
        {
          'id': 'groq:openai/gpt-oss-20b',
          'provider': 'groq',
          'model': 'openai/gpt-oss-20b',
          'name': 'GPT OSS 20B',
          'inRegistry': true,
          'kinds': ['chat'],
          ..._agg(1100, 40),
          'failuresByCode': {'http_429': 31, 'timeout': 9},
          'lastError': {
            'at': DateTime.now()
                .subtract(const Duration(minutes: 7))
                .toUtc()
                .toIso8601String(),
            'code': 'http_429',
            'message': 'Rate limit reached for model openai/gpt-oss-20b',
          },
          'rateLimit': {
            'limitTokens': 8000,
            'remainingTokens': 7600,
            'limitRequests': 30,
            'remainingRequests': 22,
            'resetsAt': DateTime.now()
                .add(const Duration(seconds: 70))
                .toUtc()
                .toIso8601String(),
          },
        },
        {
          'id': 'openrouter:openai/gpt-oss-20b',
          'provider': 'openrouter',
          'model': 'openai/gpt-oss-20b',
          'name': 'GPT OSS 20B',
          'inRegistry': true,
          'kinds': ['chat'],
          ..._agg(140, 6, p50: 1200),
        },
        {
          'id': 'groq:llama-3.3-70b-versatile',
          'provider': 'groq',
          'model': 'llama-3.3-70b-versatile',
          'name': 'Llama 3.3 70B',
          'inRegistry': true,
          'kinds': ['chat'],
          ..._agg(380, 21, p50: 1340),
          'cooldownMs': 95000,
        },
        {
          'id': 'nvidia:nemotron',
          'provider': 'nvidia',
          'model': 'nvidia/llama-3.1-nemotron-ultra-253b-v1',
          'name': 'Nemotron Ultra 253B',
          'inRegistry': true,
          'kinds': ['chat'],
          ..._agg(620, 98, p50: 1900),
        },
        {
          'id': 'tavily:',
          'provider': 'tavily',
          'model': null,
          'name': '',
          'kinds': ['search'],
          ..._agg(70, 22, p50: 700),
        },
        {
          'id': 'ollama:unused',
          'provider': 'ollama',
          'model': 'qwen3:8b',
          'name': 'Qwen3 8B',
          'inRegistry': true,
          ..._agg(0, 0),
        },
      ],
      'kinds': [
        {'kind': 'chat', ..._agg(2000, 150)},
        {'kind': 'web-search', ..._agg(70, 22)},
        {'kind': 'table-draft', ..._agg(200, 30)},
      ],
      'users': [
        {
          'email': 'someone.with.a.long.address@example.com',
          'role': 'owner',
          'window': _agg(1800, 10),
          'today': {'requests': 120, 'tokens': 40000, 'failed': 1},
        },
        {
          'role': null,
          'window': _agg(510, 177),
          'today': {'requests': 40, 'tokens': 9000, 'failed': 0},
        },
      ],
      'topErrors': [
        {
          'provider': 'groq',
          'model': 'openai/gpt-oss-20b',
          'code': 'http_429',
          'message': 'Rate limit reached for model openai/gpt-oss-20b in org',
          'count': 31,
          'lastAt': DateTime.now()
              .subtract(const Duration(minutes: 7))
              .toUtc()
              .toIso8601String(),
        },
        {
          'provider': 'groq',
          'model': 'openai/gpt-oss-20b',
          'code': 'http_429',
          'message': 'Please try again in 1.2s. Need more tokens?',
          'count': 4,
          'lastAt': DateTime.now()
              .subtract(const Duration(minutes: 30))
              .toUtc()
              .toIso8601String(),
        },
        {
          'provider': 'nvidia',
          'model': 'nvidia/llama-3.1-nemotron-ultra-253b-v1',
          'code': 'timeout',
          'message': 'no first byte within 20000ms',
          'count': 18,
          'lastAt': DateTime.now()
              .subtract(const Duration(hours: 2))
              .toUtc()
              .toIso8601String(),
        },
        {
          'provider': 'tavily',
          'model': null,
          'code': 'http_432',
          'message': 'Plan usage limit exceeded',
          'count': 22,
          'lastAt': DateTime.now()
              .subtract(const Duration(minutes: 41))
              .toUtc()
              .toIso8601String(),
        },
      ],
      'budgets': {
        'scopes': [
          {
            'scope': 'groq:openai/gpt-oss-120b',
            'minute': {'requests': 4, 'tokens': 5120, 'rpm': 30, 'tpm': 8000},
            'day': {
              'requests': 212,
              'tokens': 90000,
              'rpd': 1000,
              'tpd': 200000,
            },
          },
          {
            'scope': 'nvidia',
            'minute': {'requests': 7, 'tokens': 2300, 'rpm': 40, 'tpm': null},
            'day': {
              'requests': 388,
              'tokens': 410000,
              'rpd': null,
              'tpd': null,
            },
          },
        ],
        'skips': [
          {'model': 'groq:openai/gpt-oss-120b', 'reason': 'tpm', 'count': 6},
          {'model': 'groq:qwen/qwen3.8-27b', 'reason': 'rpd', 'count': 1},
        ],
        'waits': {'count': 2, 'totalMs': 3100},
        'auxDeferred': {'suggestions': 3, 'title': 1},
        'auxCacheHits': {'title': 5},
        'userCaps': {'chat': 1},
      },
      'turns': f.provider != null
          ? null
          : {
              'turns': 412,
              'auxCalls': 1030,
              'auxAvg': 2.5,
              'auxMax': 9,
              'ttftAvg': 1180,
              'ttftP50': 940,
              'latencyP50': 5200,
            },
    });
  }

  @override
  Future<TelemetrySeries> series(
    String window,
    String? bucket,
    TelemetryFilters f,
  ) async => TelemetrySeries.fromJson({
    'bucket': '1h',
    'points': [
      for (var i = 0; i < 24; i++)
        {
          't': DateTime(2026, 10, 11, i).toUtc().toIso8601String(),
          'requests': i < 6 ? 8 : 30 + (i * 7) % 40,
          'failed': i % 5 == 0 ? 6 : i % 3,
          'tokensIn': 90000 * (i % 7 + 1),
          'tokensOut': 14000 * (i % 5 + 1),
          'latencyP50': 800 + 90 * (i % 6),
          'ttftP50': 300 + 25 * (i % 4),
        },
    ],
  });

  @override
  Future<EventsPage> events(
    TelemetryFilters f, {
    String? before,
    bool failedOnly = false,
    int limit = TelemetrySizes.pageSize,
  }) async => EventsPage.fromJson({
    'events': [
      for (var i = 0; i < 6; i++)
        {
          'id': '${100 - i}',
          'ts': DateTime.now()
              .subtract(Duration(minutes: i * 3))
              .toUtc()
              .toIso8601String(),
          'provider': i == 4 ? 'nvidia' : 'groq',
          'model': i == 4
              ? 'nvidia/llama-3.1-nemotron-ultra-253b-v1'
              : 'openai/gpt-oss-20b',
          'kind': 'chat',
          'purpose': i == 2 ? 'title' : 'chat',
          'ok': i != 1 && i != 4 && i != 5,
          'status': i == 1 ? 429 : null,
          'errorCode': i == 1 ? 'http_429' : null,
          'errorMessage': i == 1 ? 'Rate limit reached for model' : null,
          'latencyMs': 900 + i * 40,
          'promptTokens': 3100,
          'completionTokens': 520,
        },
    ],
  });

  @override
  Stream<TelemetryEvent> live(http.Client client, {void Function()? onOpen}) {
    onOpen?.call();
    return StreamController<TelemetryEvent>().stream;
  }
}

Widget _scope(Widget app, SettingsController settings) => AppScope(
  settings: settings,
  usage: UsageController(UsageApi('http://localhost:1')),
  api: ChatApi(),
  baseUrl: 'http://localhost:1',
  child: app,
);

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final bytes = File('assets/fonts/$f').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  await load('SpaceGrotesk', ['SpaceGrotesk.ttf']);
  await load('SpaceMono', ['SpaceMono-Regular.ttf', 'SpaceMono-Bold.ttf']);
}

void main() {
  setUpAll(_loadFonts);

  for (final (name, theme, scale) in renderCases) {
    testWidgets('telemetry renders at 360dp ($name)', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = await SettingsController.load();
      await pumpScreen(
        tester,
        TelemetryScreen(api: _FakeTelemetry()),
        theme: theme,
        textScale: scale,
        wrap: (app) => _scope(app, settings),
      );
      expect(find.text(TelemetryStrings.live), findsOneWidget);
      expect(find.text('24H'), findsOneWidget);
      expect(find.byType(Card), findsNothing);
      await scrollThrough(tester, steps: 14);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('users live on their own screen, not in telemetry', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsController.load();
    await pumpScreen(
      tester,
      TelemetryScreen(api: _FakeTelemetry()),
      height: 4000,
      wrap: (app) => _scope(app, settings),
    );
    expect(
      find.text('someone.with.a.long.address@example.com', findRichText: true),
      findsNothing,
    );
    await pumpScreen(
      tester,
      UsersScreen(api: _FakeTelemetry()),
      wrap: (app) => _scope(app, settings),
    );
    expect(find.byType(UserRow), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('one range selector, one chart behind tabs', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsController.load();
    await pumpScreen(
      tester,
      TelemetryScreen(api: _FakeTelemetry()),
      height: 2400,
      wrap: (app) => _scope(app, settings),
    );
    expect(find.byType(SegmentedButton<String>), findsOneWidget);
    expect(find.byType(FilterChip), findsNothing);
    expect(find.text(TelemetryCopy.metricTokens), findsWidgets);
    await tester.tap(find.text(TelemetryCopy.metricLatency));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('7D'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a provider filters the whole screen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsController.load();
    final api = _FakeTelemetry();
    await pumpScreen(
      tester,
      TelemetryScreen(api: api),
      height: 2400,
      wrap: (app) => _scope(app, settings),
    );
    const nvidia = ValueKey('provider-nvidia');
    expect(find.byKey(nvidia), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('provider-groq')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(api.overviewCalls.last.provider, 'groq');
    expect(find.byKey(nvidia), findsNothing);
    // The same row clears it again.
    await tester.tap(find.byKey(const ValueKey('provider-groq')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(api.overviewCalls.last.provider, isNull);
    expect(find.byKey(nvidia), findsOneWidget);
  });

  testWidgets('a model row expands; duplicates merge; unused are hidden', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsController.load();
    await pumpScreen(
      tester,
      TelemetryScreen(api: _FakeTelemetry()),
      height: 2400,
      wrap: (app) => _scope(app, settings),
    );
    // GPT OSS 20B is served by Groq and OpenRouter: one row.
    expect(find.text('GPT OSS 20B'), findsOneWidget);
    expect(find.text('Groq · OpenRouter'), findsOneWidget);
    expect(find.text('Qwen3 8B'), findsNothing);
    expect(find.text('(no model)'), findsNothing);
    expect(find.text(TelemetryCopy.webSearch), findsOneWidget);
    expect(find.text(TelemetryCopy.detailTtft), findsNothing);
    await tester.tap(find.text('GPT OSS 20B'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(TelemetryCopy.detailTtft), findsOneWidget);
    expect(find.text(TelemetryCopy.detailTokens), findsOneWidget);
    expect(find.text(TelemetryCopy.detailLastCall), findsOneWidget);
    await tester.tap(find.text('GPT OSS 20B'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(TelemetryCopy.detailTtft), findsNothing);
  });

  testWidgets('cost per message shows only with turn data', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsController.load();
    await pumpScreen(
      tester,
      TelemetryScreen(api: _FakeTelemetry()),
      height: 2400,
      wrap: (app) => _scope(app, settings),
    );
    expect(find.text(TelemetryCopy.perTurn), findsOneWidget);
    expect(find.text('2.5'), findsOneWidget);
  });

  testWidgets('budgets show use per scope and pre-call skips', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsController.load();
    await pumpScreen(
      tester,
      TelemetryScreen(api: _FakeTelemetry()),
      height: 3200,
      wrap: (app) => _scope(app, settings),
    );
    expect(find.text(TelemetryCopy.budgets), findsOneWidget);
    expect(find.text('Groq gpt-oss-120b'), findsOneWidget);
    expect(find.textContaining('4/30 req'), findsOneWidget);
    // 6 + 1 skips before calling.
    expect(find.text('7'), findsWidgets);
  });

  test('grouping merges providers and names model-less rows', () {
    ModelTelemetry m(String provider, String? model, int n, List<String> k) =>
        ModelTelemetry.fromJson({
          'id': '$provider:$model',
          'provider': provider,
          'model': model,
          'name': model ?? '',
          'kinds': k,
          ..._agg(n, 0),
        }, DateTime.now());
    final r = groupModels([
      m('groq', 'x', 10, ['chat']),
      m('nvidia', 'x', 30, ['chat']),
      m('tavily', null, 5, ['search']),
      m('ollama', 'y', 0, ['chat']),
    ]);
    expect(r.groups.map((g) => g.name), ['x', TelemetryCopy.webSearch]);
    expect(r.groups.first.providers, ['nvidia', 'groq']);
    expect(r.groups.first.agg.requests, 40);
    expect(r.hidden, 1);
  });

  test('events failed only with a status >= 400 or an error code', () {
    TelemetryEvent e(Map<String, dynamic> j) => TelemetryEvent.fromJson({
      'id': '1',
      'ts': DateTime.now().toIso8601String(),
      'provider': 'groq',
      'kind': 'chat',
      ...j,
    });
    expect(e({'ok': false}).failed, isFalse);
    expect(e({'ok': false}).unknown, isTrue);
    expect(e({'ok': false, 'status': 503}).failed, isTrue);
    expect(e({'ok': false, 'errorCode': 'timeout'}).failed, isTrue);
    expect(e({'ok': true, 'status': 200}).failed, isFalse);
  });

  if (_shots.isNotEmpty) {
    for (final (name, theme, scale) in [
      ('light', AppTheme.light, 1.0),
      ('dark', AppTheme.dark, 1.0),
      ('light_13', AppTheme.light, 1.3),
    ]) {
      testWidgets('shot $name', (tester) async {
        SharedPreferences.setMockInitialValues({});
        final settings = await SettingsController.load();
        tester.view.physicalSize = const Size(412 * 2, 2900 * 2);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        final key = GlobalKey();
        await tester.pumpWidget(
          _scope(
            RepaintBoundary(
              key: key,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: theme,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: TelemetryScreen(api: _FakeTelemetry()),
              ),
            ),
            settings,
          ),
        );
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump(const Duration(milliseconds: 600));
        await tester.runAsync(() async {
          final b =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final img = await b.toImage(pixelRatio: 1.5);
          final data = await img.toByteData(format: ui.ImageByteFormat.png);
          File(
            '$_shots/tel_$name.png',
          ).writeAsBytesSync(data!.buffer.asUint8List());
        });
      });
    }
  }
}
