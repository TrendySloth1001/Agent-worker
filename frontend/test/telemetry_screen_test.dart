import 'dart:async';

import 'package:app/core/app_scope.dart';
import 'package:app/core/constants/m3_copy.dart';
import 'package:app/core/constants/telemetry.dart';
import 'package:app/data/chat_api.dart';
import 'package:app/data/telemetry.dart';
import 'package:app/data/telemetry_api.dart';
import 'package:app/data/usage_api.dart';
import 'package:app/features/settings/settings_controller.dart';
import 'package:app/features/settings/telemetry/telemetry_screen.dart';
import 'package:app/features/settings/usage_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/render.dart';

Map<String, dynamic> _agg(int requests, int failed) => {
  'requests': requests,
  'ok': requests - failed,
  'failed': failed,
  'failureRate': requests == 0 ? 0 : failed / requests,
  'tokensIn': 12345 * requests,
  'tokensOut': 678 * requests,
  'latencyP50': 840,
  'latencyP95': 2100,
  'ttftP50': 320,
  'ttftAvg': 400,
  'latencyAvg': 900,
};

class _FakeTelemetry implements TelemetryApi {
  @override
  String get baseUrl => 'http://localhost:1';

  @override
  Future<TelemetryOverview> overview(String window, TelemetryFilters f) async =>
      TelemetryOverview.fromJson({
        'window': window,
        'totals': _agg(1200, 130),
        'providers': [
          {'provider': 'groq', ..._agg(900, 100)},
          {'provider': 'nvidia', ..._agg(300, 30)},
        ],
        'models': [
          {
            'id': 'groq:a',
            'provider': 'groq',
            'model': 'openai/gpt-oss-20b',
            'name': 'GPT OSS 20B',
            'inRegistry': true,
            ..._agg(900, 100),
            'rateLimit': {'limitRequests': 100, 'remainingRequests': 40},
          },
        ],
        'kinds': [
          {'kind': 'chat', ..._agg(1000, 100)},
          {'kind': 'table-draft', ..._agg(200, 30)},
        ],
        'users': [
          {
            'email': 'someone.with.a.long.address@example.com',
            'role': 'owner',
            ..._agg(800, 10),
            'today': {'requests': 20, 'tokens': 4000, 'failed': 1},
          },
        ],
        'topErrors': [
          {
            'provider': 'groq',
            'model': 'openai/gpt-oss-20b',
            'code': 'rate_limited',
            'message': 'Too many requests, please slow down and try again.',
            'count': 12,
          },
        ],
      });

  @override
  Future<TelemetrySeries> series(
    String window,
    String? bucket,
    TelemetryFilters f,
  ) async => TelemetrySeries.fromJson({
    'bucket': bucket ?? '1m',
    'points': [
      for (var i = 0; i < 12; i++)
        {
          't': DateTime(2026, 10, 12, 10, i).toUtc().toIso8601String(),
          'requests': 5 + i,
          'failed': i % 3,
          'tokensIn': 1000 * i,
          'tokensOut': 200 * i,
          'latencyP50': 800 + 10 * i,
          'ttftP50': 300 + i,
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
      for (var i = 0; i < 4; i++)
        {
          'id': '${100 - i}',
          'ts': DateTime(2026, 10, 12, 10, 30 - i).toUtc().toIso8601String(),
          'provider': 'groq',
          'model': 'openai/gpt-oss-20b',
          'kind': 'chat',
          'purpose': 'table-draft',
          'ok': i != 1,
          'errorCode': i == 1 ? 'rate_limited' : null,
          'latencyMs': 900,
          'promptTokens': 100,
          'completionTokens': 50,
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

void main() {
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
      expect(find.text('REQUESTS'), findsWidgets);
      await scrollThrough(tester, steps: 14);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('range and granularity use segmented buttons', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsController.load();
    await pumpScreen(
      tester,
      TelemetryScreen(api: _FakeTelemetry()),
      height: 1800,
      wrap: (app) => _scope(app, settings),
    );
    expect(find.byType(SegmentedButton<String>), findsNWidgets(2));
    expect(find.byType(FilterChip), findsWidgets);
    expect(find.text(TelemetryCopy.bucketLabels['5m']!), findsOneWidget);
    await tester.tap(find.text('7D'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });
}
