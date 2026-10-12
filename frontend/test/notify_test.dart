import 'dart:convert';

import 'package:app/core/constants/notify_copy.dart';
import 'package:app/core/notify/job_watch.dart';
import 'package:app/core/notify/notification_center.dart';
import 'package:app/core/notify/notify_kind.dart';
import 'package:app/core/notify/notify_policy.dart';
import 'package:app/core/notify/notify_prefs.dart';
import 'package:app/core/notify/notify_target.dart';
import 'package:app/data/chat_event.dart';
import 'package:app/data/files_api.dart';
import 'package:app/data/kb_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

DateTime _at(int h, [int m = 0]) => DateTime(2026, 1, 1, h, m);

void main() {
  group('registry', () {
    test('every channel id is unique and described', () {
      final ids = <String>[];
      for (final k in NotifyKind.values) {
        for (final c in k.channels) {
          ids.add(c.id);
          expect(c.name, isNotEmpty, reason: c.id);
          expect(c.description, isNotEmpty, reason: c.id);
        }
      }
      expect(ids.toSet().length, ids.length);
    });

    test('each kind owns its own id range, apart from group summaries', () {
      final ranges = [
        for (final k in NotifyKind.values)
          (k.idBase, k.idBase + NotifyConfig.idSpan - 1),
      ];
      for (var i = 0; i < ranges.length; i++) {
        expect(ranges[i].$1, greaterThan(NotifyConfig.testId));
        for (var j = i + 1; j < ranges.length; j++) {
          expect(
            ranges[i].$2 < ranges[j].$1 || ranges[j].$2 < ranges[i].$1,
            isTrue,
            reason: '${NotifyKind.values[i]} overlaps ${NotifyKind.values[j]}',
          );
        }
      }
      for (final g in NotifyGroup.values) {
        expect(g.summaryId, lessThan(NotifyConfig.testId));
        expect(g.summaryId, greaterThanOrEqualTo(NotifyConfig.summaryBase));
      }
    });

    test('item ids stay in the kind range, never on the progress slot', () {
      for (final k in NotifyKind.values) {
        for (final item in ['a', 'doc-1', 'x' * 200, '']) {
          final id = k.idFor(item);
          expect(id, greaterThan(k.progressId));
          expect(id, lessThan(k.idBase + NotifyConfig.idSpan));
          expect(k.idFor(item), id);
        }
      }
    });

    test('the hash is stable (not String.hashCode)', () {
      expect(NotifyKind.stableHash('abc'), NotifyKind.stableHash('abc'));
      expect(NotifyKind.stableHash('abc'), isNot(NotifyKind.stableHash('abd')));
    });

    test('pref keys are unique and the round table keeps its old one', () {
      final keys = [for (final k in NotifyKind.values) k.prefKey];
      expect(keys.toSet().length, keys.length);
      expect(NotifyKind.roundTable.prefKey, 'notify_round_table');
    });

    test('memory and reminders are off by default', () {
      expect(NotifyKind.memory.defaultOn, isFalse);
      expect(NotifyKind.resume.defaultOn, isFalse);
      expect(NotifyKind.reply.defaultOn, isTrue);
    });

    test('memory has Undo; every kind has a label and help', () {
      expect(NotifyKind.memory.actions, contains(NotifyAction.undo));
      for (final k in NotifyKind.values) {
        expect(k.label, isNotEmpty);
        expect(k.help, isNotEmpty);
      }
    });
  });

  group('payloads', () {
    test('round trip', () {
      for (final t in <NotifyTarget>[
        const ChatTarget('c1'),
        const DocTarget('d1'),
        const FileTarget('f1'),
        const TableTarget('t1'),
        const MemoryTarget(),
        const MemoryTarget('m1'),
        const SettingsTarget('apps'),
      ]) {
        expect(NotifyTarget.parse(t.payload), t);
      }
    });

    test('formats', () {
      expect(const ChatTarget('x').payload, 'chat:x');
      expect(const MemoryTarget().payload, 'memory');
      expect(
        const SettingsTarget('notifications').payload,
        'settings:notifications',
      );
    });

    test('a bare id is a chat (payload of old versions)', () {
      expect(NotifyTarget.parse('abc-123'), const ChatTarget('abc-123'));
    });

    test('empty or unknown gives null', () {
      expect(NotifyTarget.parse(null), isNull);
      expect(NotifyTarget.parse(''), isNull);
      expect(NotifyTarget.parse('chat:'), isNull);
      expect(NotifyTarget.parse('nope:1'), isNull);
    });

    test('ids may contain colons', () {
      expect(NotifyTarget.parse('doc:a:b'), const DocTarget('a:b'));
    });
  });

  group('quiet hours', () {
    const night = QuietHours(
      enabled: true,
      startMinute: 22 * 60,
      endMinute: 7 * 60,
    );

    test('a window across midnight', () {
      expect(night.contains(_at(23)), isTrue);
      expect(night.contains(_at(0, 30)), isTrue);
      expect(night.contains(_at(6, 59)), isTrue);
      expect(night.contains(_at(7)), isFalse);
      expect(night.contains(_at(12)), isFalse);
      expect(night.contains(_at(21, 59)), isFalse);
      expect(night.contains(_at(22)), isTrue);
    });

    test('a window inside one day', () {
      const lunch = QuietHours(
        enabled: true,
        startMinute: 12 * 60,
        endMinute: 13 * 60,
      );
      expect(lunch.contains(_at(12, 30)), isTrue);
      expect(lunch.contains(_at(13)), isFalse);
      expect(lunch.contains(_at(11, 59)), isFalse);
    });

    test('off, or an empty window, is never quiet', () {
      const off = QuietHours(
        enabled: false,
        startMinute: 22 * 60,
        endMinute: 7 * 60,
      );
      expect(off.contains(_at(23)), isFalse);
      const empty = QuietHours(enabled: true, startMinute: 600, endMinute: 600);
      expect(empty.contains(_at(10)), isFalse);
    });

    test('formats minutes as HH:MM', () {
      expect(QuietHours.format(22 * 60), '22:00');
      expect(QuietHours.format(7 * 60 + 5), '07:05');
    });
  });

  group('policy', () {
    NotifyDecision decide({
      bool master = true,
      bool kind = true,
      bool bgOnly = false,
      bool inBackground = false,
      bool quiet = false,
      bool looking = false,
      bool force = false,
    }) => NotifyPolicy.decide(
      masterOn: master,
      kindOn: kind,
      backgroundOnly: bgOnly,
      appInBackground: inBackground,
      quiet: quiet,
      lookingAt: looking,
      force: force,
    );

    test('master off blocks everything, even a forced one', () {
      expect(decide(master: false), NotifyDecision.skip);
      expect(decide(master: false, force: true), NotifyDecision.skip);
    });

    test('a kind switched off is skipped unless the user asked', () {
      expect(decide(kind: false), NotifyDecision.skip);
      expect(decide(kind: false, force: true), NotifyDecision.post);
    });

    test('background-only kinds wait for the user to leave', () {
      expect(decide(bgOnly: true), NotifyDecision.skip);
      expect(decide(bgOnly: true, inBackground: true), NotifyDecision.post);
      expect(
        decide(bgOnly: true, force: true),
        NotifyDecision.post,
        reason: 'asked for it',
      );
    });

    test('nothing for what the user is looking at', () {
      expect(decide(looking: true), NotifyDecision.skip);
      expect(decide(looking: true, inBackground: true), NotifyDecision.post);
    });

    test('quiet hours post without sound', () {
      expect(decide(quiet: true), NotifyDecision.postQuiet);
      expect(decide(quiet: true, kind: false), NotifyDecision.skip);
    });

    test('repeating alerts back off', () {
      final now = _at(12);
      const gap = Duration(hours: 12);
      expect(NotifyPolicy.tooSoon(null, now, gap), isFalse);
      expect(NotifyPolicy.tooSoon(_at(6), now, gap), isTrue);
      expect(
        NotifyPolicy.tooSoon(now.subtract(const Duration(hours: 13)), now, gap),
        isFalse,
      );
      expect(NotifyPolicy.tooSoon(now, now, Duration.zero), isFalse);
    });
  });

  group('prefs', () {
    test('defaults', () async {
      SharedPreferences.setMockInitialValues({});
      final p = NotifyPrefs(await SharedPreferences.getInstance());
      expect(p.master, isTrue);
      expect(p.isOn(NotifyKind.reply), isTrue);
      expect(p.isOn(NotifyKind.memory), isFalse);
      expect(p.quiet.enabled, isFalse);
      expect(p.quietStart, NotifyConfig.defaultQuietStart);
    });

    test('the old round table key still works', () async {
      SharedPreferences.setMockInitialValues({'notify_round_table': false});
      final raw = await SharedPreferences.getInstance();
      final p = NotifyPrefs(raw);
      expect(p.isOn(NotifyKind.roundTable), isFalse);
      p.setKind(NotifyKind.roundTable, true);
      expect(raw.getBool('notify_round_table'), isTrue);
    });

    test('values persist and reset restores defaults', () async {
      SharedPreferences.setMockInitialValues({});
      final raw = await SharedPreferences.getInstance();
      final p = NotifyPrefs(raw)
        ..setMaster(false)
        ..setKind(NotifyKind.memory, true)
        ..setQuietOn(true)
        ..setQuietStart(60)
        ..setQuietEnd(120);
      final again = NotifyPrefs(raw);
      expect(again.master, isFalse);
      expect(again.isOn(NotifyKind.memory), isTrue);
      expect(again.quiet.contains(_at(1, 30)), isTrue);
      expect(again.allows(NotifyKind.reply), isFalse, reason: 'master off');
      p.reset();
      final fresh = NotifyPrefs(raw);
      expect(fresh.master, isTrue);
      expect(fresh.isOn(NotifyKind.memory), isFalse);
      expect(fresh.quietOn, isFalse);
    });

    test('notifies listeners', () {
      final p = NotifyPrefs(null);
      var n = 0;
      p.addListener(() => n++);
      p.setKind(NotifyKind.doc, false);
      p.setQuietOn(true);
      expect(n, 2);
    });
  });

  group('center decisions', () {
    final c = NotificationCenter.instance;
    final saved = c.prefs;
    tearDown(() {
      c.prefs = saved;
      c.background.value = false;
      c.clock = DateTime.now;
    });

    test('uses prefs, background state and quiet hours', () {
      c.prefs = NotifyPrefs(null);
      expect(c.decide(NotifyKind.reply), NotifyDecision.skip);
      c.background.value = true;
      c.clock = () => _at(12);
      expect(c.decide(NotifyKind.reply), NotifyDecision.post);
      c.prefs.setQuietOn(true);
      c.clock = () => _at(23);
      expect(c.decide(NotifyKind.reply), NotifyDecision.postQuiet);
      c.prefs.setKind(NotifyKind.reply, false);
      expect(c.decide(NotifyKind.reply), NotifyDecision.skip);
      c.prefs.setMaster(false);
      expect(c.decide(NotifyKind.reply, force: true), NotifyDecision.skip);
    });

    test('a repeating alert is held back for its gap', () {
      c.prefs = NotifyPrefs(null);
      c.clock = () => _at(12);
      expect(c.decide(NotifyKind.usage), NotifyDecision.post);
      c.prefs.markPosted(NotifyKind.usage, _at(10));
      expect(c.decide(NotifyKind.usage), NotifyDecision.skip);
      c.clock = () => DateTime(2026, 1, 2, 23);
      expect(c.decide(NotifyKind.usage), NotifyDecision.post);
    });
  });

  group('memory event', () {
    test('carries the memories that were added', () {
      final e =
          ChatEvent.parse(
                'memory',
                jsonEncode({
                  'changes': [
                    {'op': 'ADD', 'id': 'm1', 'text': 'likes tea'},
                    {'op': 'UPDATE', 'id': 'm2', 'text': 'x'},
                    {'op': 'DELETE', 'id': 'm3', 'text': ''},
                  ],
                }),
              )
              as MemoryEvent;
      expect(e.ops, ['ADD', 'UPDATE', 'DELETE']);
      expect(e.added, [(id: 'm1', text: 'likes tea')]);
    });
  });

  group('job watch', () {
    test('a finished file is dropped and the timer stops', () async {
      var calls = 0;
      final watch = JobWatch(
        enabled: () => true,
        fetchFile: (id) async {
          calls++;
          return FileInfo(
            id: id,
            name: 'clip.mp4',
            kind: FileKind.video,
            status: FileStatus.ready,
          );
        },
        fetchSources: () async => [],
      );
      addTearDown(watch.dispose);
      const file = FileInfo(id: 'f1', name: 'clip.mp4', kind: FileKind.video);
      watch.watchFile(file);
      watch.watchFile(file);
      expect(watch.pending, 1, reason: 'watched once');
      await watch.tick();
      expect(calls, 1);
      expect(watch.pending, 0);
    });

    test(
      'a still processing file stays; ready files are not watched',
      () async {
        final watch = JobWatch(
          enabled: () => true,
          fetchFile: (id) async => FileInfo(id: id, name: 'a.pdf'),
          fetchSources: () async => [],
        );
        addTearDown(watch.dispose);
        watch.watchFile(const FileInfo(id: 'a', name: 'a.pdf'));
        watch.watchFile(
          const FileInfo(id: 'b', name: 'b.pdf', status: FileStatus.ready),
        );
        expect(watch.pending, 1);
        await watch.tick();
        expect(watch.pending, 1);
      },
    );

    test('sources finish, vanish or expire', () async {
      var now = DateTime(2026);
      var list = <KbSource>[
        KbSource.fromJson({'id': 's1', 'type': 'web', 'status': 'running'}),
      ];
      final watch = JobWatch(
        enabled: () => true,
        clock: () => now,
        fetchFile: (id) async => FileInfo(id: id, name: ''),
        fetchSources: () async => list,
      );
      addTearDown(watch.dispose);
      watch.watchSource(list.first);
      await watch.tick();
      expect(watch.pending, 1);
      list = [
        KbSource.fromJson({'id': 's1', 'type': 'web', 'status': 'ready'}),
      ];
      await watch.tick();
      expect(watch.pending, 0);

      list = [
        KbSource.fromJson({'id': 's2', 'type': 'web', 'status': 'queued'}),
      ];
      watch.watchSource(list.first);
      now = now.add(NotifyConfig.watchMaxAge + const Duration(minutes: 1));
      await watch.tick();
      expect(watch.pending, 0, reason: 'expired');
    });

    test('does nothing while notifications are unavailable', () {
      final watch = JobWatch(enabled: () => false);
      addTearDown(watch.dispose);
      watch.watchFile(const FileInfo(id: 'a', name: 'a'));
      expect(watch.pending, 0);
    });
  });
}
