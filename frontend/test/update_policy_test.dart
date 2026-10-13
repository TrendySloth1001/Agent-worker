import 'package:app/core/update/update_models.dart';
import 'package:app/core/update/update_policy.dart';
import 'package:flutter_test/flutter_test.dart';

UpdateInfo _info(
  UpdateKind? kind, {
  int build = 30,
  int current = 25,
  bool required = false,
  int? min,
}) => UpdateInfo(
  current: current,
  minSupportedBuild: min,
  required: required,
  latest: kind == null
      ? null
      : UpdateRelease(version: '1.7.0', build: build, kind: kind, url: 'u'),
);

final _t0 = DateTime(2026, 10, 13, 12);

void main() {
  group('decide', () {
    test('nothing newer is none', () {
      expect(
        UpdatePolicy.decide(_info(null), PromptState.fresh, _t0),
        UpdatePrompt.none,
      );
    });

    test('patch is only a dot, even for a version never prompted', () {
      expect(
        UpdatePolicy.decide(_info(UpdateKind.patch), PromptState.fresh, _t0),
        UpdatePrompt.dot,
      );
    });

    test('critical is blocking', () {
      expect(
        UpdatePolicy.decide(_info(UpdateKind.critical), PromptState.fresh, _t0),
        UpdatePrompt.blocking,
      );
    });

    test('below the minimum build is blocking whatever the kind', () {
      for (final k in [
        UpdateKind.patch,
        UpdateKind.feature,
        UpdateKind.major,
      ]) {
        expect(
          UpdatePolicy.decide(
            _info(k, required: true, min: 28),
            PromptState.fresh,
            _t0,
          ),
          UpdatePrompt.blocking,
          reason: k.name,
        );
      }
    });

    test('a feature or major never prompted shows the sheet', () {
      for (final k in [UpdateKind.feature, UpdateKind.major]) {
        expect(
          UpdatePolicy.decide(_info(k), PromptState.fresh, _t0),
          UpdatePrompt.sheet,
          reason: k.name,
        );
      }
    });

    test('a newer build than the prompted one starts over', () {
      final old = PromptState(
        promptedBuild: 29,
        promptCount: 3,
        nextPromptAt: null,
      );
      expect(
        UpdatePolicy.decide(_info(UpdateKind.feature, build: 30), old, _t0),
        UpdatePrompt.sheet,
      );
    });

    test('after the first Later: dot for 3 days, then the sheet again', () {
      final s = UpdatePolicy.afterShown(PromptState.fresh, 30, _t0);
      expect(s.promptCount, 1);
      expect(s.nextPromptAt, _t0.add(const Duration(days: 3)));
      final info = _info(UpdateKind.feature);
      expect(
        UpdatePolicy.decide(info, s, _t0.add(const Duration(days: 2))),
        UpdatePrompt.dot,
      );
      expect(
        UpdatePolicy.decide(info, s, _t0.add(const Duration(days: 3))),
        UpdatePrompt.sheet,
      );
    });

    test('after the second Later: 7 days, then the sheet once more', () {
      final t1 = _t0.add(const Duration(days: 3));
      final first = UpdatePolicy.afterShown(PromptState.fresh, 30, _t0);
      final s = UpdatePolicy.afterShown(first, 30, t1);
      expect(s.promptCount, 2);
      expect(s.nextPromptAt, t1.add(const Duration(days: 7)));
      final info = _info(UpdateKind.major);
      expect(
        UpdatePolicy.decide(info, s, t1.add(const Duration(days: 6))),
        UpdatePrompt.dot,
      );
      expect(
        UpdatePolicy.decide(info, s, t1.add(const Duration(days: 7))),
        UpdatePrompt.sheet,
      );
    });

    test('after the third showing it never prompts again (dot only)', () {
      var s = PromptState.fresh;
      var t = _t0;
      for (var i = 0; i < 3; i++) {
        s = UpdatePolicy.afterShown(s, 30, t);
        t = t.add(const Duration(days: 30));
      }
      expect(s.promptCount, 3);
      expect(s.nextPromptAt, isNull);
      expect(
        UpdatePolicy.decide(
          _info(UpdateKind.feature),
          s,
          t.add(const Duration(days: 365)),
        ),
        UpdatePrompt.dot,
      );
    });

    test('a count at the cap is dot even with a stale next date', () {
      final s = PromptState(
        promptedBuild: 30,
        promptCount: 3,
        nextPromptAt: _t0.subtract(const Duration(days: 1)),
      );
      expect(
        UpdatePolicy.decide(_info(UpdateKind.feature), s, _t0),
        UpdatePrompt.dot,
      );
    });

    test('critical ignores the cadence', () {
      final s = UpdatePolicy.afterShown(PromptState.fresh, 30, _t0);
      expect(
        UpdatePolicy.decide(_info(UpdateKind.critical), s, _t0),
        UpdatePrompt.blocking,
      );
    });

    test('a new version after the old one was prompted restarts the count', () {
      final old = UpdatePolicy.afterShown(PromptState.fresh, 30, _t0);
      final next = UpdatePolicy.afterShown(old, 31, _t0);
      expect(next.promptedBuild, 31);
      expect(next.promptCount, 1);
    });
  });

  group('shouldNotify', () {
    test('once per version for feature and major', () {
      expect(
        UpdatePolicy.shouldNotify(_info(UpdateKind.feature), null),
        isTrue,
      );
      expect(UpdatePolicy.shouldNotify(_info(UpdateKind.major), 29), isTrue);
      expect(UpdatePolicy.shouldNotify(_info(UpdateKind.feature), 30), isFalse);
    });

    test('never for patch, critical, blocking or nothing', () {
      expect(UpdatePolicy.shouldNotify(_info(UpdateKind.patch), null), isFalse);
      expect(
        UpdatePolicy.shouldNotify(_info(UpdateKind.critical), null),
        isFalse,
      );
      expect(
        UpdatePolicy.shouldNotify(
          _info(UpdateKind.feature, required: true),
          null,
        ),
        isFalse,
      );
      expect(UpdatePolicy.shouldNotify(_info(null), null), isFalse);
    });
  });

  group('shouldAutoDownload', () {
    bool go(
      UpdateKind? k, {
      bool wifi = true,
      bool wifiOnly = true,
      bool have = false,
    }) => UpdatePolicy.shouldAutoDownload(
      _info(k),
      onWifi: wifi,
      wifiOnly: wifiOnly,
      haveIt: have,
    );

    test('patch on Wi-Fi downloads in the background', () {
      expect(go(UpdateKind.patch), isTrue);
    });

    test('patch off Wi-Fi waits when Wi-Fi only is on', () {
      expect(go(UpdateKind.patch, wifi: false), isFalse);
      expect(go(UpdateKind.patch, wifi: false, wifiOnly: false), isTrue);
    });

    test('only patches download by themselves', () {
      expect(go(UpdateKind.feature), isFalse);
      expect(go(UpdateKind.major), isFalse);
      expect(go(UpdateKind.critical), isFalse);
      expect(go(null), isFalse);
    });

    test('nothing to do when it is already downloaded', () {
      expect(go(UpdateKind.patch, have: true), isFalse);
    });
  });

  group('helpers', () {
    test('checkDue after 6 hours or never', () {
      expect(UpdatePolicy.checkDue(null, _t0), isTrue);
      expect(
        UpdatePolicy.checkDue(_t0.subtract(const Duration(hours: 5)), _t0),
        isFalse,
      );
      expect(
        UpdatePolicy.checkDue(_t0.subtract(const Duration(hours: 7)), _t0),
        isTrue,
      );
    });

    test('arm64 split version codes map back to the build number', () {
      expect(UpdatePolicy.buildFromVersionCode(2025), 25);
      expect(UpdatePolicy.buildFromVersionCode(25), 25);
    });
  });

  group('models', () {
    test('UpdateInfo parses the check response', () {
      final info = UpdateInfo.fromJson({
        'current': 25,
        'minSupportedBuild': 20,
        'required': false,
        'latest': {
          'version': '1.7.0',
          'build': 30,
          'kind': 'major',
          'title': 'Big one',
          'notes': ['a', ' ', 'b'],
          'size': 1234,
          'sha256': 'ABC',
          'url': 'https://x',
        },
      });
      expect(info.latest!.kind, UpdateKind.major);
      expect(info.latest!.notes, ['a', 'b']);
      expect(info.latest!.sha256, 'abc');
      expect(info.minSupportedBuild, 20);
      expect(
        UpdateInfo.fromJson({'current': 1, 'latest': null}).hasUpdate,
        isFalse,
      );
    });

    test('an unknown kind falls back to feature', () {
      expect(UpdateKind.parse('weird'), UpdateKind.feature);
    });
  });
}
