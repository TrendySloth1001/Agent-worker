import 'dart:convert';
import 'dart:ui' show PlatformDispatcher;

import 'package:app/core/constants/errors.dart';
import 'package:app/core/errors/breadcrumbs.dart';
import 'package:app/core/errors/error_queue.dart';
import 'package:app/core/errors/error_reporter.dart';
import 'package:app/core/errors/errors_api.dart';
import 'package:app/core/errors/session_tracker.dart';
import 'package:app/data/chat_api.dart';
import 'package:app/features/settings/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeErrorsApi implements ErrorsApi {
  final errors = <List<Map<String, dynamic>>>[];
  final sessions = <List<Map<String, dynamic>>>[];
  Object? fail;

  @override
  Future<void> sendErrors(List<Map<String, dynamic>> e) async {
    if (fail != null) throw fail!;
    errors.add(e);
  }

  @override
  Future<void> sendSessions(List<Map<String, dynamic>> s) async {
    if (fail != null) throw fail!;
    sessions.add(s);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Clock {
  DateTime now = DateTime(2026, 10, 21, 12);
  DateTime call() => now;
  void advance(Duration d) => now = now.add(d);
}

Future<(ErrorReporter, FakeErrorsApi, SharedPreferences, Clock)> _make({
  bool owner = false,
  bool signedIn = true,
  Map<String, Object> prefs = const {},
  Map<String, dynamic>? native,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final p = await SharedPreferences.getInstance();
  final api = FakeErrorsApi();
  final clock = Clock();
  final r = ErrorReporter(
    prefs: p,
    api: api,
    isOwner: () => owner,
    signedIn: () => signedIn,
    build: 34,
    clock: clock.call,
    crumbs: Breadcrumbs(clock: clock.call),
    native: () async => native,
  );
  addTearDown(r.dispose);
  return (r, api, p, clock);
}

Future<bool> _rec(ErrorReporter r, String type, String stack) =>
    r.record(kind: 'dart', type: type, message: 'boom', stack: stack);

String _stack(int n) => '#0      f$n (package:app/core/x$n.dart:10:3)';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('handlers', () {
    test(
      'FlutterError, PlatformDispatcher and isolate errors are captured and queued',
      () async {
        final (r, _, _, _) = await _make();
        final prevFlutter = FlutterError.onError;
        final prevPlatform = PlatformDispatcher.instance.onError;
        addTearDown(() {
          FlutterError.onError = prevFlutter;
          PlatformDispatcher.instance.onError = prevPlatform;
        });
        r.installHandlers();

        FlutterError.onError!(
          FlutterErrorDetails(
            exception: StateError('framework'),
            stack: StackTrace.fromString(_stack(1)),
          ),
        );
        final handled = PlatformDispatcher.instance.onError!(
          ArgumentError('async'),
          StackTrace.fromString(_stack(2)),
        );
        // The platform handler must return true: the error is handled.
        expect(handled, isTrue);
        r.recordIsolateError(['IsolateBoom', _stack(3)]);
        await Future<void>.delayed(Duration.zero);

        final kinds = r.queue.read().map((e) => e.payload['kind']).toList();
        expect(kinds, ['dart', 'platform', 'isolate']);
        final first = r.queue.read().first.payload;
        expect(first['type'], 'StateError');
        expect(first['build'], 34);
        expect(first['sessionId'], isNull);
        expect(first['stack'], contains('package:app/core/x1.dart'));
      },
    );

    test('payload is trimmed: first line, 200 chars, 8 KB stack', () async {
      final (r, _, _, _) = await _make();
      await r.record(
        kind: 'dart',
        type: 'T' * 300,
        message: '${'m' * 500}\nsecond line with more text',
        stack: 'x' * 20000,
      );
      final p = r.queue.read().single.payload;
      expect((p['message'] as String).length, ErrorsConfig.maxMessage);
      expect(p['message'], isNot(contains('second')));
      expect((p['stack'] as String).length, ErrorsConfig.maxStack);
      expect((p['type'] as String).length, ErrorsConfig.maxType);
    });
  });

  group('rate limits', () {
    test('the same error is recorded at most once per 60 seconds', () async {
      final (r, _, _, clock) = await _make();
      expect(await _rec(r, 'E', _stack(1)), isTrue);
      expect(await _rec(r, 'E', _stack(1)), isFalse);
      // Line numbers do not make it a different error.
      expect(
        await _rec(r, 'E', _stack(1).replaceAll(':10:3', ':99:1')),
        isFalse,
      );
      clock.advance(const Duration(seconds: 59));
      expect(await _rec(r, 'E', _stack(1)), isFalse);
      clock.advance(const Duration(seconds: 2));
      expect(await _rec(r, 'E', _stack(1)), isTrue);
      expect(r.queue.length, 2);
    });

    test('at most 10 distinct errors per session', () async {
      final (r, _, _, _) = await _make();
      for (var i = 0; i < 10; i++) {
        expect(await _rec(r, 'E$i', _stack(i)), isTrue);
      }
      expect(await _rec(r, 'E10', _stack(10)), isFalse);
      expect(r.queue.length, 10);
    });

    test('queue keeps at most 50 entries, oldest dropped first', () async {
      SharedPreferences.setMockInitialValues({});
      final p = await SharedPreferences.getInstance();
      final q = ErrorQueue(p, 'q');
      for (var i = 0; i < 60; i++) {
        await q.add({'n': i});
      }
      final all = q.read();
      expect(all.length, ErrorsConfig.queueMaxEntries);
      expect(all.first.payload['n'], 10);
      expect(all.last.payload['n'], 59);
    });

    test('queue keeps at most 200 KB', () async {
      SharedPreferences.setMockInitialValues({});
      final p = await SharedPreferences.getInstance();
      final q = ErrorQueue(p, 'q');
      for (var i = 0; i < 40; i++) {
        await q.add({'n': i, 'blob': 'x' * 8000});
      }
      final bytes = utf8
          .encode(jsonEncode([for (final e in q.read()) e.toJson()]))
          .length;
      expect(bytes, lessThanOrEqualTo(ErrorsConfig.queueMaxBytes));
      expect(q.read().last.payload['n'], 39);
    });

    test('entries older than 7 days are dropped', () async {
      SharedPreferences.setMockInitialValues({});
      final p = await SharedPreferences.getInstance();
      final clock = Clock();
      final q = ErrorQueue(p, 'q', clock: clock.call);
      await q.add({'n': 1});
      clock.advance(const Duration(days: 6));
      await q.add({'n': 2});
      expect(q.read().length, 2);
      clock.advance(const Duration(days: 2));
      expect(q.read().map((e) => e.payload['n']), [2]);
    });
  });

  group('sending', () {
    test('flush sends batches of at most 10 and empties the queue', () async {
      final (r, api, _, _) = await _make();
      final seed = ErrorQueue(
        await SharedPreferences.getInstance(),
        ErrorsPrefs.errorQueue,
      );
      for (var i = 0; i < 23; i++) {
        await seed.add({'kind': 'dart', 'n': i});
      }
      await r.flush();
      expect(api.errors.map((b) => b.length), [10, 10, 3]);
      expect(r.queue.length, 0);
    });

    test('nothing is sent while signed out; the queue is kept', () async {
      final (r, api, _, _) = await _make(signedIn: false);
      await _rec(r, 'E', _stack(1));
      await r.flush();
      expect(api.errors, isEmpty);
      expect(r.queue.length, 1);
    });

    test(
      'network and server failures keep the queue; a 400 drops the batch',
      () async {
        final (r, api, _, _) = await _make();
        await _rec(r, 'E', _stack(1));
        api.fail = const ApiException('down', status: 503);
        await r.flush();
        expect(r.queue.length, 1);
        api.fail = Exception('socket');
        await r.flush();
        expect(r.queue.length, 1);
        api.fail = const ApiException('limited', status: 429);
        await r.flush();
        expect(r.queue.length, 1);
        api.fail = const ApiException('bad', status: 400);
        await r.flush();
        expect(r.queue.length, 0);
      },
    );
  });

  group('send crash reports switch', () {
    test('off: nothing is recorded and the queue is cleared', () async {
      final (r, api, p, _) = await _make();
      await _rec(r, 'E', _stack(1));
      expect(r.queue.length, 1);
      SharedPreferences.setMockInitialValues({});
      final settings = await SettingsController.load();
      // Same store as the reporter: use its prefs through the controller path.
      await p.setBool(ErrorsPrefs.sendReports, false);
      await r.flush();
      expect(r.queue.length, 0);
      expect(api.errors, isEmpty);
      expect(await _rec(r, 'F', _stack(2)), isFalse);
      expect(settings.sendCrashReports, isTrue);
    });

    test(
      'SettingsController.setSendCrashReports(false) removes every queue',
      () async {
        SharedPreferences.setMockInitialValues({
          ErrorsPrefs.errorQueue: '[1]',
          ErrorsPrefs.assistErrorQueue: '[1]',
          ErrorsPrefs.sessionQueue: '[1]',
        });
        final settings = await SettingsController.load();
        expect(settings.sendCrashReports, isTrue);
        settings.setSendCrashReports(false);
        final p = await SharedPreferences.getInstance();
        expect(p.getBool(ErrorsPrefs.sendReports), isFalse);
        for (final k in [
          ErrorsPrefs.errorQueue,
          ErrorsPrefs.assistErrorQueue,
          ErrorsPrefs.sessionQueue,
        ]) {
          expect(p.getString(k), isNull, reason: k);
        }
        settings.setSendCrashReports(true);
        expect(p.getBool(ErrorsPrefs.sendReports), isTrue);
      },
    );

    test('the owner is always on, whatever the switch says', () async {
      final (r, _, _, _) = await _make(
        owner: true,
        prefs: {ErrorsPrefs.sendReports: false},
      );
      expect(r.enabled, isTrue);
      expect(await _rec(r, 'E', _stack(1)), isTrue);
    });
  });

  group('breadcrumbs', () {
    test('ring buffer keeps the last 30', () {
      final c = Breadcrumbs();
      for (var i = 0; i < 45; i++) {
        c.net(const [ConnectivityLike.wifi]);
      }
      expect(c.items.length, 30);
    });

    test(
      'route names lose ids, queries and anything that is not a plain path',
      () {
        const id = '123e4567-e89b-12d3-a456-426614174000';
        expect(Breadcrumbs.routeLabel('/chat/$id'), '/chat/:id');
        expect(
          Breadcrumbs.routeLabel('/chat/1234567?q=my%20secret'),
          '/chat/:id',
        );
        expect(Breadcrumbs.routeLabel('/files/report final.pdf'), 'unnamed');
        expect(Breadcrumbs.routeLabel('/files/report.pdf'), 'unnamed');
        expect(Breadcrumbs.routeLabel('What is my password'), 'unnamed');
        expect(Breadcrumbs.routeLabel(null), 'unnamed');
        expect(Breadcrumbs.routeLabel(''), 'unnamed');
        expect(Breadcrumbs.routeLabel('/settings'), '/settings');
      },
    );

    test('route arguments and content never reach the trail', () {
      final c = Breadcrumbs();
      final observer = BreadcrumbObserver(c);
      observer.didPush(
        MaterialPageRoute<void>(
          settings: const RouteSettings(
            name: '/chat/9876543210',
            arguments: 'my private message about my medical results',
          ),
          builder: (_) => const SizedBox(),
        ),
        null,
      );
      observer.didPush(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: 'Tell me about my bank account'),
          builder: (_) => const SizedBox(),
        ),
        null,
      );
      c.update(TargetPlatform.android);
      c.lifecycle(AppLifecycleState.paused);
      final json = jsonEncode(c.toJson());
      expect(json, isNot(contains('private')));
      expect(json, isNot(contains('medical')));
      expect(json, isNot(contains('bank')));
      expect(json, isNot(contains('9876543210')));
      for (final crumb in c.items) {
        expect(crumb.label, matches(RegExp(r'^[a-z0-9_/: +-]{1,60}$')));
      }
    });

    test(
      'an error report carries the trail and no field outside the whitelist',
      () async {
        final (r, _, _, _) = await _make();
        r.crumbs.lifecycle(AppLifecycleState.resumed);
        r.crumbs.route(
          'push',
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: '/settings'),
            builder: (_) => const SizedBox(),
          ),
        );
        await _rec(r, 'E', _stack(1));
        final p = r.queue.read().single.payload;
        expect(p.keys.toSet(), {
          'kind',
          'type',
          'message',
          'stack',
          'build',
          'at',
          'breadcrumbs',
          'device',
        });
        expect((p['breadcrumbs'] as List).length, 2);
        expect((p['device'] as Map).keys, everyElement(isIn(['locale', 'fg'])));
      },
    );
  });

  group('sessions', () {
    Future<(SessionTracker, SharedPreferences, Clock)> tracker({
      SharedPreferences? prefs,
      bool enabled = true,
    }) async {
      if (prefs == null) SharedPreferences.setMockInitialValues({});
      final p = prefs ?? await SharedPreferences.getInstance();
      final clock = Clock();
      return (
        SessionTracker(
          prefs: p,
          build: 34,
          enabled: () => enabled,
          clock: clock.call,
        ),
        p,
        clock,
      );
    }

    test(
      'cold start queues a start; a clean pause ends it ok; resume starts a new session',
      () async {
        final (t, _, clock) = await tracker();
        expect(await t.begin(), isNull);
        final first = t.currentId!;
        expect(first, matches(RegExp(r'^[0-9a-f-]{36}$')));
        clock.advance(const Duration(minutes: 3));
        await t.end();
        await t.resume();
        expect(t.currentId, isNot(first));
        final q = t.queue.read().map((e) => e.payload).toList();
        expect(q.map((e) => e['outcome']), ['unknown', 'ok', 'unknown']);
        expect(q[1]['id'], first);
        expect(q[1]['endedAt'], isNotNull);
        expect(q[0]['build'], 34);
      },
    );

    test(
      'a start without an end is a crashed session on the next launch',
      () async {
        final (t1, p, _) = await tracker();
        await t1.begin();
        final dead = t1.currentId!;
        final (t2, _, _) = await tracker(prefs: p);
        final prev = await t2.begin(
          native: {
            'crash': {
              'type': 'IllegalStateException',
              'message': 'x',
              'stack': '',
              'at': 1,
            },
          },
        );
        expect(prev!.sessionId, dead);
        expect(prev.outcome, 'crash');
        final settled = t2.queue
            .read()
            .map((e) => e.payload)
            .where((e) => e['id'] == dead);
        expect(settled.map((e) => e['outcome']), contains('crash'));
      },
    );

    test('exit reasons map to outcomes; a clean end stays ok', () {
      String o(
        bool ended, [
        Map<String, dynamic>? exit,
        Map<String, dynamic>? crash,
      ]) => SessionTracker.outcomeOf(ended: ended, exit: exit, crash: crash);
      expect(o(false, {'reason': 'anr'}), 'anr');
      expect(o(false, {'reason': 'crash_native'}), 'crash');
      expect(o(false, {'reason': 'low_memory'}), 'killed');
      expect(o(false), 'unknown');
      expect(o(true), 'ok');
      expect(o(true, {'reason': 'low_memory'}), 'ok');
      expect(o(true, {'reason': 'anr'}), 'anr');
    });

    test('nothing is queued when reporting is off', () async {
      final (t, _, _) = await tracker(enabled: false);
      await t.begin();
      await t.end();
      expect(t.queue.length, 0);
    });

    test(
      'reporter turns the last run\'s Kotlin crash into an error on the crashed build',
      () async {
        final (r1, _, p, _) = await _make();
        await r1.sessions.begin();
        // Process died; next launch.
        final (r2, _, _, _) = await _make(
          prefs: {for (final k in p.getKeys()) k: p.get(k)!},
          native: {
            'crash': {
              'type': 'IllegalStateException',
              'message': 'boom',
              'stack':
                  'java.lang.IllegalStateException\n\tat com.sparky.app.Updater.install(Updater.kt:5)',
              'at': DateTime(2026, 10, 21, 11).millisecondsSinceEpoch,
            },
          },
        );
        await r2.start();
        final crash = r2.queue
            .read()
            .map((e) => e.payload)
            .singleWhere((e) => e['kind'] == 'kotlin');
        expect(crash['type'], 'IllegalStateException');
        expect(crash['build'], 34);
        expect(crash['sessionId'], isNotNull);
      },
    );
  });
}

/// A stand-in enum for connectivity types so the test needs no plugin.
enum ConnectivityLike { wifi }
