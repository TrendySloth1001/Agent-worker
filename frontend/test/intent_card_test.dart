import 'dart:convert';
import 'dart:io';

import 'package:app/core/constants/intent_cards.dart';
import 'package:app/core/haptics.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/features/cards/intent_card.dart';
import 'package:app/features/cards/intent_card_model.dart';
import 'package:app/features/cards/intent_runner.dart';
import 'package:app/features/chat/widgets/rich/widget_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Cards exactly as the server builds them (backend cards.ts); regenerate
/// with the backend's buildCard when the wire format changes.
final Map<String, String> _cards = Map<String, String>.from(
  jsonDecode(File('test/fixtures/intent_cards.json').readAsStringSync()) as Map,
);

const _channel = MethodChannel(IntentCardWire.channel);

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

void main() {
  late List<MethodCall> calls;
  late Set<String> installedPackages;
  late String runResult;
  late List<Uri> opened;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _fonts();
    Haptics.enabled = false;
  });

  setUp(() {
    calls = [];
    opened = [];
    installedPackages = {};
    runResult = IntentCardWire.ok;
    InstalledCardApps.reset();
    IntentRunner.instance = ChannelIntentRunner(
      channel: _channel,
      openLink: (u) async {
        opened.add(u);
        return true;
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          if (call.method == IntentCardWire.installed) {
            final pkgs =
                (call.arguments as Map)[IntentCardWire.packages] as List;
            return {
              for (final p in pkgs) p as String: installedPackages.contains(p),
            };
          }
          calls.add(call);
          return runResult;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  Widget host(String source, {bool dark = false}) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: dark ? AppTheme.dark : AppTheme.light,
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: IntentCard(source: source),
      ),
    ),
  );

  Future<void> pump(
    WidgetTester tester,
    String key, {
    bool dark = false,
  }) async {
    await tester.pumpWidget(host(_cards[key]!, dark: dark));
    await tester.pump();
    await tester.pump();
  }

  Future<void> tapButton(WidgetTester tester, String label) async {
    await tester.tap(
      find
          .byWidgetPredicate(
            (w) =>
                w is Semantics &&
                (w.properties.label ?? '').startsWith('$label,'),
          )
          .first,
    );
    await tester.pump();
    await tester.pump();
  }

  Map<String, Object?> args(int i) =>
      Map<String, Object?>.from(calls[i].arguments as Map);

  group('parsing and the allow-list', () {
    test('a finished card parses; junk does not', () {
      expect(IntentCardSpec.parse(_cards['place']!), isNotNull);
      expect(IntentCardSpec.parse('not json'), isNull);
      expect(IntentCardSpec.parse('{"type":"place","title":"x"}'), isNull);
      // What the model writes (no actions) is not a card.
      expect(
        IntentCardSpec.parse('{"type":"place","name":"Blue Tokai"}'),
        isNull,
      );
    });

    test(
      'unknown actions, schemes, hosts, extras and packages are dropped',
      () {
        CardIntent? p(Map<String, Object?> m) => CardIntent.parse(m);
        expect(p({'action': 'view', 'uri': 'javascript:alert(1)'}), isNull);
        expect(p({'action': 'view', 'uri': 'https://evil.example/x'}), isNull);
        expect(p({'action': 'view', 'uri': 'http://www.amazon.in/'}), isNull);
        expect(p({'action': 'view', 'uri': 'intent://x#Intent;end'}), isNull);
        expect(p({'action': 'view', 'uri': 'content://contacts'}), isNull);
        expect(p({'action': 'dial', 'uri': 'https://www.amazon.in/'}), isNull);
        expect(p({'action': 'view'}), isNull);
        expect(p({'action': 'format_disk'}), isNull);
        expect(p({'action': 'launch'}), isNull);
        final ok = p({
          'action': 'set_timer',
          'package': 'no good!',
          'fallback': 'https://evil.example/',
          'extras': {'length': 60, 'skipUi': true, 'message': 'x'},
        })!;
        expect(ok.package, isNull);
        expect(ok.fallback, isNull);
        expect(ok.extras, {'length': 60, 'message': 'x'});
      },
    );

    test('event times become epoch milliseconds', () {
      final i = CardIntent.parse({
        'action': 'insert_event',
        'extras': {'title': 'T', 'begin': '2026-10-16T16:00'},
      })!;
      final extras = i.toChannel()['extras'] as Map;
      expect(
        extras['beginMs'],
        DateTime(2026, 10, 16, 16).millisecondsSinceEpoch,
      );
      expect(extras.containsKey('begin'), isFalse);
    });
  });

  group('cards render and run on tap only', () {
    testWidgets('place: details, Directions to the Maps app, Call, Share', (
      tester,
    ) async {
      await pump(tester, 'place');
      expect(find.text('Blue Tokai Coffee'), findsOneWidget);
      expect(find.textContaining('80 Feet Road'), findsOneWidget);
      expect(find.text('MO-SU 08:00-23:00'), findsNothing);
      expect(find.text('Mo-Su 08:00-23:00'), findsOneWidget);
      expect(calls, isEmpty, reason: 'nothing runs until a tap');

      await tapButton(tester, 'Directions');
      expect(args(0), {
        'action': 'view',
        'uri': 'google.navigation:q=12.9352%2C77.6245',
        'package': 'com.google.android.apps.maps',
        'chooser': false,
        'extras': <Object?, Object?>{},
      });
      await tapButton(tester, 'Call');
      expect(args(1)['action'], 'dial');
      expect(args(1)['uri'], 'tel:+918041234567');
      await tapButton(tester, 'Share');
      expect(args(2)['action'], 'send');
      expect((args(2)['extras'] as Map)['text'], contains('Blue Tokai'));
    });

    testWidgets('place not found: name and a Directions search only', (
      tester,
    ) async {
      await pump(tester, 'place_missing');
      expect(find.text("Raju's Chai Stall"), findsOneWidget);
      expect(find.text('Call'), findsNothing);
      await tapButton(tester, 'Directions');
      expect(args(0)['uri'], startsWith('google.navigation:q='));
    });

    testWidgets('event: Add to calendar with the times in ms', (tester) async {
      await pump(tester, 'event');
      expect(find.text('Dentist appointment'), findsOneWidget);
      expect(find.textContaining('Smile Clinic'), findsOneWidget);
      await tapButton(tester, 'Add to calendar');
      final a = args(0);
      expect(a['action'], 'insert_event');
      final x = a['extras'] as Map;
      expect(x['title'], 'Dentist appointment');
      expect(x['beginMs'], DateTime(2026, 10, 16, 16).millisecondsSinceEpoch);
      expect(x['endMs'], DateTime(2026, 10, 16, 17).millisecondsSinceEpoch);
      expect(x['location'], 'Smile Clinic, Indiranagar');
      expect(x['description'], 'Bring X-rays');
    });

    testWidgets('clock: alarm button and timer chips', (tester) async {
      await pump(tester, 'clock');
      await tapButton(tester, 'Set alarm 19:30');
      expect(args(0)['action'], 'set_alarm');
      expect(args(0)['extras'], {
        'hour': 19,
        'minutes': 30,
        'message': 'Dinner',
      });
      await tapButton(tester, 'Boil pasta · 10 min');
      expect(args(1)['action'], 'set_timer');
      expect(args(1)['extras'], {'length': 600, 'message': 'Boil pasta'});
      await tapButton(tester, 'Simmer sauce · 7 min');
      expect((args(2)['extras'] as Map)['length'], 420);
    });

    testWidgets('contact: call, WhatsApp prefilled, SMS, save', (tester) async {
      await pump(tester, 'contact');
      expect(find.text('Rahul Sharma'), findsOneWidget);
      await tapButton(tester, 'Call');
      expect(args(0)['uri'], 'tel:+919876543210');
      await tapButton(tester, 'WhatsApp');
      expect(
        args(1)['uri'],
        'https://wa.me/919876543210?text=Running%2010%20minutes%20late',
      );
      expect(args(1)['package'], 'com.whatsapp');
      await tapButton(tester, 'SMS');
      expect(args(2)['uri'], 'smsto:+919876543210');
      expect((args(2)['extras'] as Map)['body'], 'Running 10 minutes late');
      await tapButton(tester, 'Save contact');
      expect(args(3)['action'], 'insert_contact');
      expect(args(3)['extras'], {
        'name': 'Rahul Sharma',
        'phone': '+919876543210',
      });
    });

    testWidgets('product: Amazon, Flipkart, Myntra search links', (
      tester,
    ) async {
      await pump(tester, 'product');
      expect(find.text('about Rs 3,495'), findsOneWidget);
      await tapButton(tester, 'Amazon');
      expect(
        args(0)['uri'],
        'https://www.amazon.in/s?k=Nike%20Revolution%207%20running%20shoes',
      );
      expect(args(0)['package'], 'in.amazon.mShop.android.shopping');
      await tapButton(tester, 'Myntra');
      expect(
        args(1)['uri'],
        startsWith('https://www.myntra.com/nike-revolution'),
      );
    });

    testWidgets('product: an installed app is offered first', (tester) async {
      installedPackages = {'com.flipkart.android'};
      await pump(tester, 'product');
      final amazon = tester.getTopLeft(find.text('Amazon')).dx;
      final flipkart = tester.getTopLeft(find.text('Flipkart')).dx;
      expect(flipkart, lessThan(amazon));
    });

    testWidgets('ride: Uber with the drop, Ola and Rapido open the app', (
      tester,
    ) async {
      await pump(tester, 'ride');
      await tapButton(tester, 'Uber');
      expect(
        args(0)['uri'],
        contains('dropoff%5Bformatted_address%5D=Kempegowda'),
      );
      expect(args(0)['package'], 'com.ubercab');
      await tapButton(tester, 'Ola');
      expect(args(1)['action'], 'launch');
      expect(args(1)['package'], 'com.olacabs.customer');
      await tapButton(tester, 'Directions');
      expect(args(2)['uri'], startsWith('google.navigation:q='));
    });

    testWidgets('food: Swiggy and Zomato searches', (tester) async {
      await pump(tester, 'food');
      await tapButton(tester, 'Swiggy');
      expect(
        args(0)['uri'],
        'https://www.swiggy.com/search?query=chicken%20biryani%20HSR%20Layout',
      );
      await tapButton(tester, 'Zomato');
      expect(args(1)['package'], 'com.application.zomato');
    });

    testWidgets('travel (train): IRCTC app, ixigo, MakeMyTrip, web search', (
      tester,
    ) async {
      await pump(tester, 'travel');
      expect(find.text('Pune to Mumbai'), findsOneWidget);
      await tapButton(tester, 'IRCTC');
      expect(args(0)['action'], 'launch');
      await tapButton(tester, 'ixigo');
      expect(args(1)['uri'], 'https://www.ixigo.com/trains');
      await tapButton(tester, 'Search the web');
      expect(args(2)['uri'], contains('trains%20from%20Pune%20to%20Mumbai'));
    });

    testWidgets('UPI: says it never pays; opens a chooser with the prefill', (
      tester,
    ) async {
      await pump(tester, 'upi');
      expect(find.text('Pay Rahul'), findsOneWidget);
      expect(
        find.textContaining('confirm and pay in your UPI app'),
        findsOneWidget,
      );
      expect(find.textContaining('never pays'), findsOneWidget);
      expect(find.textContaining('₹500'), findsOneWidget);
      expect(calls, isEmpty);
      await tapButton(tester, 'Open UPI app');
      expect(
        args(0)['uri'],
        'upi://pay?pa=rahul%40okaxis&pn=Rahul&am=500&tn=dinner&cu=INR',
      );
      expect(args(0)['chooser'], true);
    });
  });

  group('failures', () {
    testWidgets('no app can do it: message, and the web fallback opens', (
      tester,
    ) async {
      runResult = IntentCardWire.unavailable;
      await pump(tester, 'place');
      await tapButton(tester, 'Directions');
      expect(
        opened.single.toString(),
        startsWith('https://www.google.com/maps/dir/'),
      );
    });

    testWidgets('unavailable without a fallback shows a message', (
      tester,
    ) async {
      runResult = IntentCardWire.unavailable;
      await pump(tester, 'contact');
      await tapButton(tester, 'Call');
      expect(find.text(IntentCardStrings.unavailable), findsOneWidget);
      expect(opened, isEmpty);
    });

    testWidgets('a failed intent shows a message', (tester) async {
      runResult = 'failed';
      await pump(tester, 'contact');
      await tapButton(tester, 'Call');
      expect(find.text(IntentCardStrings.failed), findsOneWidget);
    });
  });

  testWidgets('the registry builds the card for sparky-card', (tester) async {
    final w = buildRichWidget(
      IntentCardWire.fence,
      _cards['food']!,
      streaming: false,
    );
    expect(w, isA<IntentCard>());
    expect(
      buildRichWidget(IntentCardWire.fence, '{', streaming: true),
      isNotNull,
    );
  });

  group('golden', () {
    for (final key in ['place', 'upi', 'clock', 'product']) {
      for (final dark in [false, true]) {
        final theme = dark ? 'dark' : 'light';
        testWidgets('$key $theme', (tester) async {
          tester.view.physicalSize = const Size(412 * 2, 420 * 2);
          tester.view.devicePixelRatio = 2;
          addTearDown(tester.view.reset);
          await pump(tester, key, dark: dark);
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('goldens/intent_card_${key}_$theme.png'),
          );
        });
      }
    }
  });
}
