import 'package:app/core/constants/update.dart';
import 'package:app/core/update/update_downloader.dart';
import 'package:app/core/update/update_installer.dart';
import 'package:app/core/update/update_events.dart';
import 'package:app/core/update/update_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/update_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('event queue', () {
    late DateTime now;
    late List<List<Map<String, dynamic>>> sent;
    Object? failWith;

    UpdateEventReporter make() => UpdateEventReporter(
      send: (id, events) async {
        if (failWith != null) throw failWith!;
        sent.add(events);
      },
      clock: () => now,
    );

    Future<void> add(UpdateEventReporter r, int n, {InstallStage stage = InstallStage.downloadOk}) async {
      for (var i = 0; i < n; i++) {
        await r.record(build: 1, toBuild: 2, stage: stage);
      }
    }

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      now = DateTime(2026, 10, 14, 12);
      sent = [];
      failWith = null;
    });

    test('flush sends and clears the queue', () async {
      final r = make();
      await r.record(build: 33, toBuild: 34, stage: InstallStage.installOk, code: 'relaunch', via: InstallVia.resume);
      await r.flush();
      expect(sent, hasLength(1));
      expect(sent.single.single['stage'], 'install_ok');
      expect(sent.single.single['via'], 'resume');
      expect(sent.single.single['code'], 'relaunch');
      expect(await r.pending(), 0);
    });

    test('an offline flush keeps everything for next time', () async {
      final r = make();
      await add(r, 3);
      failWith = Exception('offline');
      await r.flush();
      expect(await r.pending(), 3);
      failWith = null;
      await r.flush();
      expect(sent.single, hasLength(3));
      expect(await r.pending(), 0);
    });

    test('the queue is bounded: the oldest events are dropped', () async {
      final r = make();
      await r.record(build: 1, toBuild: 1, stage: InstallStage.downloadStart, code: 'oldest');
      await add(r, UpdateConfig.eventQueueMax);
      expect(await r.pending(), UpdateConfig.eventQueueMax);
      await r.flush();
      expect(sent.expand((b) => b).any((e) => e['code'] == 'oldest'), isFalse);
    });

    test('batches never exceed the server limit', () async {
      final r = make();
      await add(r, 120);
      await r.flush();
      expect(sent.map((b) => b.length), [50, 50]);
      expect(await r.pending(), 0);
    });

    test('a failure part-way keeps only the unsent batch', () async {
      final r = UpdateEventReporter(
        send: (id, events) async {
          if (sent.isNotEmpty) throw Exception('rate limited');
          sent.add(events);
        },
        clock: () => now,
      );
      await add(r, 70);
      await r.flush();
      expect(sent.single, hasLength(50));
      expect(await r.pending(), 20);
    });

    test('events older than a week are dropped', () async {
      final r = make();
      await add(r, 2);
      now = now.add(const Duration(days: 8));
      await add(r, 1);
      await r.flush();
      expect(sent.single, hasLength(1));
    });

    test('a device id is made once and kept', () async {
      final r = make();
      final a = await r.deviceId();
      expect(a, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(await make().deviceId(), a);
    });

    test('malformed stored events are ignored, not fatal', () async {
      SharedPreferences.setMockInitialValues({UpdatePrefs.events: 'not json'});
      final r = make();
      expect(await r.pending(), 0);
      await add(r, 1);
      expect(await r.pending(), 1);
    });
  });

  group('first launch detection', () {
    test('only a newer build than the last launch counts', () {
      expect(FirstLaunch.afterUpdate(null, 34), isFalse, reason: 'fresh install');
      expect(FirstLaunch.afterUpdate(34, 34), isFalse);
      expect(FirstLaunch.afterUpdate(33, 34), isTrue);
      expect(FirstLaunch.afterUpdate(35, 34), isFalse);
    });
  });

  group('controller reports outcomes', () {
    UpdateInfo info() => UpdateInfo(current: 25, latest: fakeRelease(kind: UpdateKind.patch, build: 26));

    test('download then install success are reported in order', () async {
      final r = UpdateRig(info: info(), wifi: false);
      await r.controller.check();
      await r.controller.begin();
      await r.flush();
      expect([for (final e in r.api.sentEvents) e['stage']], ['download_start', 'download_ok', 'install_start', 'install_ok']);
      expect(r.api.sentEvents.first['build'], 25);
      expect(r.api.sentEvents.first['toBuild'], 26);
    });

    test('a failed download reports download_fail', () async {
      final r = UpdateRig(info: info(), wifi: false);
      r.downloader.error = Exception('offline');
      await r.controller.check();
      await r.controller.begin();
      await r.flush();
      expect([for (final e in r.api.sentEvents) e['stage']], ['download_start', 'download_fail']);
      expect(r.api.sentEvents.last['code'], 'network');
    });

    test('a checksum mismatch reports verify_fail (twice: one retry)', () async {
      final r = UpdateRig(info: info(), wifi: false);
      r.downloader.error = const UpdateVerifyException();
      await r.controller.check();
      await r.controller.begin();
      await r.flush();
      expect([for (final e in r.api.sentEvents) e['stage']], ['download_start', 'verify_fail', 'verify_fail']);
    });

    test('cancel, signature mismatch and install failure map to their stages', () async {
      for (final (status, stage) in [
        (InstallStatus.cancelled, 'cancelled'),
        (InstallStatus.signatureMismatch, 'signature_mismatch'),
        (InstallStatus.failed, 'install_fail'),
      ]) {
        final r = UpdateRig(info: info(), wifi: false);
        r.installer.result = status;
        await r.controller.check();
        await r.controller.begin();
        await r.flush();
        expect(r.api.sentEvents.last['stage'], stage, reason: '$status');
      }
    });

    test('events survive being offline and go out on the next flush', () async {
      final r = UpdateRig(info: info(), wifi: false);
      r.api.eventsError = Exception('offline');
      await r.controller.check();
      await r.controller.begin();
      await r.flush();
      expect(r.api.sentEvents, isEmpty);
      r.api.eventsError = null;
      await r.flush();
      expect(r.api.sentEvents, isNotEmpty);
    });

    test('first launch after an update: inferred install_ok + first_launch_ok', () async {
      final r = UpdateRig(
        info: UpdateInfo(current: 26),
        build: 26,
        prefs: {UpdatePrefs.lastBuild: 25, UpdatePrefs.pending: '25|26'},
      );
      await r.controller.launch();
      await r.flush();
      final got = [for (final e in r.api.sentEvents) (e['stage'], e['build'], e['toBuild'])];
      expect(got, [('install_ok', 25, 26), ('first_launch_ok', 26, 26)]);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(UpdatePrefs.lastBuild), 26);
      expect(prefs.getString(UpdatePrefs.pending), isNull);
    });

    test('first launch with no install on record only reports first_launch_ok', () async {
      final r = UpdateRig(info: UpdateInfo(current: 26), build: 26, prefs: {UpdatePrefs.lastBuild: 24});
      await r.controller.launch();
      await r.flush();
      expect([for (final e in r.api.sentEvents) e['stage']], ['first_launch_ok']);
    });

    test('an ordinary launch and a fresh install report nothing', () async {
      final same = UpdateRig(info: UpdateInfo(current: 26), build: 26, prefs: {UpdatePrefs.lastBuild: 26});
      await same.controller.launch();
      await same.flush();
      expect(same.api.sentEvents, isEmpty);
      final fresh = UpdateRig(info: UpdateInfo(current: 26), build: 26);
      await fresh.controller.launch();
      await fresh.flush();
      expect(fresh.api.sentEvents, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(UpdatePrefs.lastBuild), 26);
    });
  });
}
