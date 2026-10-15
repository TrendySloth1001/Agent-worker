import 'dart:convert';

import 'package:app/core/app_scope.dart';
import 'package:app/core/constants/location.dart';
import 'package:app/core/constants/smart_toggles.dart';
import 'package:app/core/haptics.dart';
import 'package:app/core/platform/phone_hints.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/chat_api.dart';
import 'package:app/data/chat_message.dart';
import 'package:app/data/usage_api.dart';
import 'package:app/features/chat/chat_turn.dart';
import 'package:app/features/settings/settings_controller.dart';
import 'package:app/features/settings/settings_pages.dart';
import 'package:app/features/settings/usage_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/shot.dart';

Future<SettingsController> _pump(WidgetTester tester) async {
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
        theme: AppTheme.light,
        home: const SettingsCategoryPage(category: SettingsCategory.privacy),
      ),
    ),
  );
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
  return settings;
}

/// Sends one turn through the real [ChatApi] and returns the JSON body the
/// server would receive.
Future<Map<String, dynamic>> _sentBody(ChatTurn turn) async {
  late Map<String, dynamic> body;
  final client = MockClient((request) async {
    body = jsonDecode(request.body) as Map<String, dynamic>;
    return http.Response('event: done\ndata: {}\n\n', 200);
  });
  await turn
      .stream(ChatApi(), client, [
        ChatMessage(role: Role.user, content: 'weather today'),
      ])
      .drain<void>()
      .catchError((_) {});
  return body;
}

ChatTurn _turn({bool approx = true, Map<String, String> profile = const {}}) =>
    ChatTurn(
      webMode: WebMode.auto,
      knowledge: false,
      mode: 'default',
      profile: profile,
      approxLocation: approx,
    );

void main() {
  setUpAll(() async {
    await loadAppFonts();
    Haptics.enabled = false;
  });
  tearDown(() => PhoneHints.debugSet(null));

  group('Settings → Privacy', () {
    testWidgets('shows the switch (on by default) and My city', (tester) async {
      final s = await _pump(tester);
      expect(find.text(LocationStrings.approxTitle), findsOneWidget);
      expect(find.text(LocationStrings.approxHelp), findsOneWidget);
      expect(find.text(LocationStrings.cityLabel), findsOneWidget);
      expect(s.approxLocation, isTrue);
    });

    testWidgets('the switch turns approximate location off and persists', (
      tester,
    ) async {
      final s = await _pump(tester);
      await tester.tap(find.text(LocationStrings.approxTitle));
      await tester.pump(const Duration(milliseconds: 300));
      expect(s.approxLocation, isFalse);
      final p = await SharedPreferences.getInstance();
      expect(p.getBool('approx_location'), isFalse);
    });

    testWidgets('My city is shown, saved, and sent in the profile', (
      tester,
    ) async {
      final s = await _pump(tester);
      s.setCity('  Pune ');
      await tester.pump(const Duration(milliseconds: 300));
      expect(s.city, 'Pune');
      expect(find.text('Pune'), findsOneWidget);
      expect(s.profileJson()['city'], 'Pune');
      s.setCity('');
      expect(s.profileJson().containsKey('city'), isFalse);
    });

    testWidgets('reset to defaults turns it back on but keeps My city', (
      tester,
    ) async {
      final s = await _pump(tester);
      s.setCity('Pune');
      s.setApproxLocation(false);
      s.resetToDefaults();
      expect(s.approxLocation, isTrue);
      expect(s.city, 'Pune');
    });
  });

  group('phone hints on requests', () {
    test('are attached when approximate location is on', () async {
      PhoneHints.debugSet({
        LocationConfig.simCountry: 'in',
        LocationConfig.networkCountry: 'in',
        LocationConfig.timeZone: 'Asia/Kolkata',
        LocationConfig.locale: 'en-IN',
      });
      final body = await _sentBody(_turn(profile: {'city': 'Pune'}));
      expect(body['locationHints'], {
        'simCountry': 'in',
        'networkCountry': 'in',
        'timeZone': 'Asia/Kolkata',
        'locale': 'en-IN',
      });
      expect(body.containsKey('approxLocation'), isFalse);
      expect((body['profile'] as Map)['city'], 'Pune');
    });

    test('are not sent when it is off, which the server is told', () async {
      PhoneHints.debugSet({LocationConfig.networkCountry: 'in'});
      final body = await _sentBody(_turn(approx: false));
      expect(body.containsKey('locationHints'), isFalse);
      expect(body['approxLocation'], isFalse);
    });

    test('a phone with nothing to say sends no empty object', () async {
      PhoneHints.debugSet(const {});
      final body = await _sentBody(_turn());
      expect(body.containsKey('locationHints'), isFalse);
    });

    test('ChatTurn.of follows the setting', () async {
      SharedPreferences.setMockInitialValues({'approx_location': false});
      final s = await SettingsController.load();
      final turn = ChatTurn.of(
        s,
        models: const [],
        webMode: WebMode.auto,
        knowledge: false,
        roundTable: false,
      );
      expect(turn.approxLocation, isFalse);
    });
  });
}
