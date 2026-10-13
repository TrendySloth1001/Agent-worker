import 'dart:async';

import 'package:app/assist/circle/circle_geometry.dart';
import 'package:app/assist/live/live_voice.dart';
import 'package:app/assist/live/speakable.dart';
import 'package:app/assist/live/speaker.dart';
import 'package:app/assist/screen_text.dart';
import 'package:app/assist/share_payload.dart';
import 'package:app/core/constants/assist.dart';
import 'package:app/core/constants/device_actions.dart';
import 'package:app/core/haptics.dart';
import 'package:app/features/actions/device_action.dart';
import 'package:app/features/actions/device_action_runner.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

// ---- live fakes ---------------------------------------------------------------

class FakeEars implements LiveEars {
  void Function(String, bool)? onText;
  void Function()? onSilence;
  int listens = 0, stops = 0;
  bool _on = false;

  @override
  bool get listening => _on;

  @override
  Future<void> listen({
    required void Function(String text, bool isFinal) onText,
    required void Function() onSilence,
  }) async {
    listens++;
    _on = true;
    this.onText = onText;
    this.onSilence = onSilence;
  }

  @override
  Future<void> stop() async {
    stops++;
    _on = false;
  }

  void say(String text, {bool done = true}) {
    if (done) _on = false;
    onText!(text, done);
  }

  void silence() {
    _on = false;
    onSilence!();
  }
}

class FakeSpeaker implements Speaker {
  final spoken = <String>[];
  final langs = <String?>[];
  Completer<void>? current;
  int stops = 0;

  @override
  Future<void> speak(String text, {String? lang}) {
    spoken.add(text);
    langs.add(lang);
    current = Completer<void>();
    return current!.future;
  }

  @override
  Future<void> stop() async {
    stops++;
    if (current != null && !current!.isCompleted) current!.complete();
  }

  void finish() => current!.complete();
}

void main() {
  setUpAll(() => Haptics.enabled = false);

  group('circle geometry', () {
    const view = Size(400, 800);

    test('a stroke selects its bounding box', () {
      final box = selectionOf(const [
        Offset(100, 200),
        Offset(220, 180),
        Offset(240, 300),
        Offset(90, 320),
      ], view: view);
      expect(box, const Rect.fromLTRB(90, 180, 240, 320));
    });

    test('a tap selects a square around the finger, kept on screen', () {
      final box = selectionOf(const [Offset(10, 400)], view: view)!;
      expect(box.right, 10 + 60);
      expect(box.left, 0);
      expect(box.height, 120);
    });

    test('empty stroke selects nothing', () {
      expect(selectionOf(const [], view: view), isNull);
    });

    test('a thin selection is padded to a minimum box, kept on screen', () {
      // A straight horizontal line.
      final line = padToMin(
        const Rect.fromLTRB(100, 300, 300, 302),
        view: view,
        minSide: 96,
      );
      expect(line, const Rect.fromLTRB(100, 253, 300, 349));
      // A short line in the corner grows inwards.
      final corner = padToMin(
        const Rect.fromLTRB(0, 0, 40, 1),
        view: view,
        minSide: 96,
      );
      expect(corner, const Rect.fromLTRB(0, 0, 96, 96));
      // Never larger than the view.
      final tiny = padToMin(
        const Rect.fromLTRB(10, 10, 20, 20),
        view: const Size(50, 50),
        minSide: 96,
      );
      expect(tiny, const Rect.fromLTRB(0, 0, 50, 50));
      // Big enough already: unchanged.
      const big = Rect.fromLTRB(10, 10, 210, 210);
      expect(padToMin(big, view: view, minSide: 96), big);
    });

    test('several strokes select the union of their boxes', () {
      final box = selectionOfStrokes(const [
        [Offset(100, 100), Offset(200, 160)],
        [Offset(200, 160), Offset(150, 260)],
        [Offset(150, 260), Offset(90, 160)],
      ], view: view)!;
      expect(box, const Rect.fromLTRB(90, 100, 200, 260));
      expect(selectionOfStrokes(const [[], []], view: view), isNull);
    });

    test('crop rect: padded, scaled to the image, clamped, whole pixels', () {
      // The image is half the view's size.
      final r = cropRectFor(
        const Rect.fromLTRB(100, 100, 201, 300),
        view: view,
        image: const Size(200, 400),
        padding: 16,
      )!;
      expect(r, const Rect.fromLTRB(42, 42, 109, 158));
      final edge = cropRectFor(
        const Rect.fromLTRB(0, 0, 100, 100),
        view: view,
        image: const Size(200, 400),
      )!;
      expect(edge.left, 0);
      expect(edge.top, 0);
    });

    test('a tiny crop is refused', () {
      expect(
        cropRectFor(
          const Rect.fromLTRB(10, 10, 12, 12),
          view: view,
          image: const Size(40, 80),
          padding: 0,
        ),
        isNull,
      );
    });

    test(
      'text nodes: covered ones count, far ones and big containers do not',
      () {
        const nodes = [
          ScreenNode('Air Max 90', bounds: Rect.fromLTRB(100, 100, 300, 140)),
          ScreenNode('£129', bounds: Rect.fromLTRB(100, 150, 180, 190)),
          ScreenNode('Footer', bounds: Rect.fromLTRB(0, 1800, 1000, 1900)),
          // The page: the selection is a small part of it, it is a small part
          // of the selection's... no: it covers the whole selection.
          ScreenNode('Long article', bounds: Rect.fromLTRB(0, 0, 1000, 2000)),
          ScreenNode('No bounds'),
        ];
        final hit = nodesIn(const Rect.fromLTRB(80, 80, 320, 200), nodes);
        expect(hit.map((n) => n.text), ['Air Max 90', '£129', 'Long article']);
        // A word circled inside a paragraph keeps the paragraph.
        final inside = nodesIn(const Rect.fromLTRB(110, 105, 140, 135), nodes);
        expect(inside.first.text, 'Air Max 90');
      },
    );

    test('selection text maps view to screen pixels', () {
      const screen = ScreenContext(
        screenSize: Size(800, 1600),
        nodes: [
          ScreenNode('Hello', bounds: Rect.fromLTRB(200, 200, 400, 260)),
          ScreenNode('Elsewhere', bounds: Rect.fromLTRB(0, 1400, 800, 1500)),
        ],
      );
      expect(
        selectionText(
          const Rect.fromLTRB(90, 90, 210, 140),
          view: view,
          screen: screen,
        ),
        'Hello',
      );
    });

    test('channel nodes keep their bounds and the screen size', () {
      final ctx = ScreenContext.fromChannel({
        AssistChannel.available: true,
        AssistChannel.nodes: [
          {
            AssistChannel.nodeText: 'Hi',
            AssistChannel.nodeLeft: 1,
            AssistChannel.nodeTop: 2,
            AssistChannel.nodeRight: 30,
            AssistChannel.nodeBottom: 40,
          },
          {AssistChannel.nodeText: 'No box'},
        ],
        AssistChannel.screenWidth: 1080,
        AssistChannel.screenHeight: 2400,
      });
      expect(ctx.nodes.first.bounds, const Rect.fromLTRB(1, 2, 30, 40));
      expect(ctx.nodes.last.bounds, isNull);
      expect(ctx.screenSize, const Size(1080, 2400));
      expect(ctx.text, 'Hi\nNo box');
    });
  });

  group('share payload', () {
    test('files, text and subject', () {
      final p = SharedPayload.parse({
        AssistChannel.sharedText: 'https://example.com/a',
        AssistChannel.sharedSubject: 'An article',
        AssistChannel.sharedFiles: [
          {
            AssistChannel.filePath: '/c/0-photo.jpg',
            AssistChannel.fileName: '0-photo.jpg',
            AssistChannel.fileSize: 1200,
          },
          {AssistChannel.filePath: '/c/no-name'},
        ],
        AssistChannel.sharedSkipped: 1,
      })!;
      expect(p.files.single.name, '0-photo.jpg');
      expect(p.files.single.size, 1200);
      expect(p.skipped, 1);
      expect(p.draft, 'An article\nhttps://example.com/a');
    });

    test('subject already in the text is not repeated; junk is null', () {
      final p = SharedPayload.parse({
        AssistChannel.sharedText: 'Title — https://x.y',
        AssistChannel.sharedSubject: 'Title',
      })!;
      expect(p.draft, 'Title — https://x.y');
      expect(SharedPayload.parse('nope'), isNull);
      expect(SharedPayload.parse(<String, Object>{})!.isEmpty, isTrue);
    });
  });

  group('device actions', () {
    test('alarm: time parsed, channel args normalised', () {
      final a = DeviceAction.parse(
        '{"type":"alarm","time":"7:05","label":"Gym"}',
      )!;
      expect(a.title, DeviceActionStrings.alarmTitle('07:05'));
      expect(a.toChannel(), {
        'type': 'alarm',
        'hour': 7,
        'minute': 5,
        'label': 'Gym',
      });
      expect(a.type.leaves, isFalse);
    });

    test('invalid actions never become cards', () {
      for (final bad in [
        'not json',
        '{"type":"launch_missiles"}',
        '{"type":"alarm","time":"25:00"}',
        '{"type":"timer","seconds":0}',
        '{"type":"url","url":"javascript:alert(1)"}',
        '{"type":"dial","number":"call mum"}',
        '{"type":"event","title":"x"}',
        '{"type":"reminder","text":"x","at":"soon"}',
      ]) {
        expect(DeviceAction.parse(bad), isNull, reason: bad);
      }
    });

    test('event: start and end in local time, epoch millis to Kotlin', () {
      final a = DeviceAction.parse(
        '{"type":"event","title":"Dentist","start":"2026-10-14T15:00",'
        '"end":"2026-10-14T15:30","location":"High St"}',
      )!;
      final args = a.toChannel();
      expect(
        args[DeviceActionWire.beginMs],
        DateTime(2026, 10, 14, 15).millisecondsSinceEpoch,
      );
      expect(
        args[DeviceActionWire.endMs],
        DateTime(2026, 10, 14, 15, 30).millisecondsSinceEpoch,
      );
      expect(a.details.map((d) => d.$1), [
        DeviceActionStrings.startLabel,
        DeviceActionStrings.endLabel,
        DeviceActionStrings.whereLabel,
      ]);
    });

    test('dial only fills the dialer; messages say you press send', () {
      expect(
        DeviceAction.parse('{"type":"dial","number":"+44 20 7946 0000"}')!.hint,
        DeviceActionStrings.dialHint,
      );
      expect(
        DeviceAction.parse('{"type":"sms","body":"On my way"}')!.hint,
        DeviceActionStrings.sendHint,
      );
    });

    test('channel results map to outcomes', () {
      expect(outcomeOf('ok'), ActionOutcome.done);
      expect(outcomeOf('not_found'), ActionOutcome.notFound);
      expect(outcomeOf('unavailable'), ActionOutcome.unavailable);
      expect(outcomeOf(null), ActionOutcome.failed);
    });

    test('reminders go to notifications, not the channel', () async {
      final reminded = <DeviceAction>[];
      final runner = ChannelDeviceActionRunner(
        remind: (a) async {
          reminded.add(a);
          return true;
        },
      );
      final a = DeviceAction.parse(
        '{"type":"reminder","text":"Call the bank","at":"2026-10-14T09:00"}',
      )!;
      expect(await runner.run(a), ActionOutcome.done);
      expect(reminded.single.when, DateTime(2026, 10, 14, 9));
    });

    test('local time with its offset for the request', () {
      final iso = localIso(DateTime(2026, 10, 13, 14, 5, 9));
      expect(iso, startsWith('2026-10-13T14:05:09'));
      expect(iso, matches(RegExp(r'[+-]\d\d:\d\d$')));
      expect(deviceActionsRequest().keys, [DeviceActionWire.localTime]);
    });
  });

  group('speakable text', () {
    test('markdown read aloud without code, links or citations', () {
      expect(
        speakable(
          '**Sunny**, see [the forecast](https://x.y) [W1].\n\n'
          '- High 21\n```sparky-action\n{"type":"alarm"}\n```',
        ),
        'Sunny, see the forecast. High 21.',
      );
    });

    test('chunks end on a finished sentence; all of it once done', () {
      const text = 'It is sunny in London today. Expect a high of';
      final (first, at) = nextChunk(text, 0, done: false);
      expect(first, 'It is sunny in London today.');
      final (rest, end) = nextChunk(text, at, done: true);
      expect(rest, 'Expect a high of');
      expect(end, text.length);
    });

    test('an open code fence is never cut into', () {
      const text = 'Here is the setup you asked about.\n```dart\nvoid main(';
      final (chunk, at) = nextChunk(text, 0, done: false);
      expect(chunk, 'Here is the setup you asked about.');
      expect(text.substring(at), startsWith('```'));
    });

    test('barge-in: new words count, the phone\'s own echo does not', () {
      const said = 'It is sunny in London today';
      expect(isBargeIn('sunny in London', said), isFalse);
      expect(isBargeIn('wait what about tomorrow', said), isTrue);
    });
  });

  group('live voice', () {
    late FakeEars ears;
    late FakeSpeaker speaker;
    late List<String> asked;
    late int interrupts;
    LiveAnswer? reply;
    late LiveVoice live;

    setUp(() {
      ears = FakeEars();
      speaker = FakeSpeaker();
      asked = [];
      interrupts = 0;
      reply = null;
      live = LiveVoice(
        ears: ears,
        speaker: speaker,
        ask: (t) async {
          asked.add(t);
          reply = (text: '', done: false);
          return true;
        },
        answer: () => reply,
        onInterrupt: () => interrupts++,
        lang: () => 'fr-FR',
      );
    });

    Future<void> flush() => Future<void>.delayed(Duration.zero);

    test(
      'listen, send on pause, speak sentence by sentence, listen again',
      () async {
        live.start();
        await flush();
        expect(live.phase, LivePhase.listening);
        ears.say('what is the weather', done: false);
        expect(live.heard, 'what is the weather');
        ears.say('what is the weather');
        await flush();
        expect(asked, ['what is the weather']);
        expect(live.phase, LivePhase.thinking);

        reply = (text: 'It is sunny in Paris today. A high of 21', done: false);
        live.answerChanged();
        await flush();
        expect(live.phase, LivePhase.speaking);
        expect(speaker.spoken, ['It is sunny in Paris today.']);
        expect(speaker.langs, ['fr-FR']);

        reply = (text: 'It is sunny in Paris today. A high of 21.', done: true);
        live.answerChanged();
        speaker.finish();
        await flush();
        expect(speaker.spoken.last, 'A high of 21.');
        speaker.finish();
        await flush();
        expect(live.phase, LivePhase.listening);
      },
    );

    test('tap interrupts: speech stops, the reply stops, it listens', () async {
      live.start();
      await flush();
      ears.say('tell me a story');
      await flush();
      reply = (text: 'Once upon a time there was a fox. And', done: false);
      live.answerChanged();
      await flush();
      expect(live.phase, LivePhase.speaking);
      live.interrupt();
      await flush();
      expect(speaker.stops, greaterThan(0));
      expect(interrupts, 1);
      expect(live.phase, LivePhase.listening);
    });

    test('talking over it stops it; its own echo does not', () async {
      live.start();
      await flush();
      ears.say('tell me a story');
      await flush();
      reply = (text: 'Once upon a time there was a fox. And', done: false);
      live.answerChanged();
      await flush();
      // The mic is open while it talks.
      expect(ears.listening, isTrue);
      ears.say('once upon a time', done: false);
      expect(live.phase, LivePhase.speaking);
      ears.say('stop and tell me the weather', done: false);
      expect(live.phase, LivePhase.listening);
      expect(interrupts, 1);
      ears.say('stop and tell me the weather');
      await flush();
      expect(asked.last, 'stop and tell me the weather');
    });

    test(
      'ends by itself after silent turns; end() silences everything',
      () async {
        live.start();
        await flush();
        ears.silence();
        await flush();
        expect(live.phase, LivePhase.listening);
        ears.silence();
        await flush();
        expect(live.phase, LivePhase.off);
        expect(live.endedBySilence, isTrue);

        live.start();
        await flush();
        live.end();
        expect(live.phase, LivePhase.off);
        expect(speaker.stops, greaterThan(0));
        expect(ears.listening, isFalse);
      },
    );
  });
}
