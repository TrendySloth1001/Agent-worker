import 'dart:io';

import 'package:app/core/constants/app_strings.dart';
import 'package:app/core/constants/preview.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/file_cache.dart';
import 'package:app/data/file_insight.dart';
import 'package:app/data/files_api.dart';
import 'package:app/features/chat/preview/image_preview.dart';
import 'package:app/features/chat/preview/media_preview.dart';
import 'package:app/features/chat/preview/pdf_preview.dart';
import 'package:app/features/chat/preview/preview_type.dart';
import 'package:app/features/chat/preview/preview_view.dart';
import 'package:app/features/chat/preview/sparky_text.dart';
import 'package:app/features/chat/preview/sparky_view.dart';
import 'package:app/features/chat/preview/text_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_understanding.dart';

Future<void> _app(WidgetTester tester, Widget home, {bool dark = false}) async {
  tester.view.physicalSize = const Size(360, 780);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(theme: dark ? AppTheme.dark : AppTheme.light, home: home),
  );
  await tester.pump();
}

/// Lets real async work (fake calls, prefs) finish, then rebuilds.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _tapLabel(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).first);
  await _settle(tester);
}

const _docx = FileInfo(
  id: 'o1',
  name: 'Lease.docx',
  kind: FileKind.document,
  mime:
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
);
const _pdf = FileInfo(
  id: 'p1',
  name: 'plan.pdf',
  kind: FileKind.document,
  mime: 'application/pdf',
);
const _photo = FileInfo(id: 'i1', name: 'receipt.jpg', kind: FileKind.image);

late FakeUnderstanding _fake;
late Directory _dir;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _fake = FakeUnderstanding();
    FileUnderstanding.instance = _fake;
    _dir = Directory.systemTemp.createTempSync('sparky_view');
    FileCache.instance = FileCache(
      root: () async => Directory('${_dir.path}/cache'),
      info: (id, {force = false}) async => throw StateError('offline'),
    );
  });
  tearDown(() => _dir.deleteSync(recursive: true));

  group('defaults and memory', () {
    test('Office opens on sparky, everything else on the original', () {
      expect(defaultViewOf(PreviewType.office), PreviewView.sparky);
      for (final t in PreviewType.values.where(
        (t) => t != PreviewType.office,
      )) {
        expect(defaultViewOf(t), PreviewView.original, reason: t.name);
      }
    });

    test('the last pick is kept per type of file', () async {
      expect(
        await PreviewViewPrefs.load(PreviewType.pdf),
        PreviewView.original,
      );
      await PreviewViewPrefs.save(PreviewType.pdf, PreviewView.sparky);
      await PreviewViewPrefs.save(PreviewType.office, PreviewView.original);
      expect(await PreviewViewPrefs.load(PreviewType.pdf), PreviewView.sparky);
      expect(
        await PreviewViewPrefs.load(PreviewType.image),
        PreviewView.original,
      );
      expect(
        await PreviewViewPrefs.load(PreviewType.office),
        PreviewView.original,
      );
    });

    test('only server files of a known type have a sparky view', () {
      expect(hasSparkyView(_pdf), isTrue);
      expect(hasSparkyView(const FileInfo(id: '', name: 'a.pdf')), isFalse);
      expect(hasSparkyView(const FileInfo(id: 'z', name: 'a.zip')), isFalse);
      expect(hasSparkyView(_pdf.asDeleted()), isFalse);
    });
  });

  group('toggle in the top bar', () {
    testWidgets('an Office file opens on the sparky view and can switch', (
      tester,
    ) async {
      _fake.data = docData(summary: 'A one year lease for a flat in Pune.');
      _fake.pages = ['Lease\n\nRent is 500 per month.'];
      await _app(tester, const TextPreviewScreen(file: _docx));
      await _settle(tester);
      expect(find.text(PreviewStrings.viewOriginal), findsOneWidget);
      expect(find.text(PreviewStrings.viewSparky), findsOneWidget);
      expect(find.text('A one year lease for a flat in Pune.'), findsOneWidget);
      expect(
        find.textContaining('Rent is 500 per month.', findRichText: true),
        findsOneWidget,
      );
      expect(find.text(PreviewStrings.openWith), findsNothing);

      await _tapLabel(tester, PreviewStrings.viewOriginal);
      expect(find.text(PreviewStrings.originalOfficeTitle), findsOneWidget);
      expect(find.text(PreviewStrings.openWith), findsOneWidget);
      expect(
        await PreviewViewPrefs.load(PreviewType.office),
        PreviewView.original,
      );
    });

    testWidgets('the saved choice wins the next time', (tester) async {
      SharedPreferences.setMockInitialValues({
        '${PreviewConfig.viewPrefsKey}office': 'original',
      });
      _fake.data = docData();
      await _app(tester, const TextPreviewScreen(file: _docx));
      await _settle(tester);
      expect(find.text(PreviewStrings.originalOfficeTitle), findsOneWidget);
      expect(_fake.insightCalls, 0, reason: 'sparky view was never opened');
    });

    testWidgets('a PDF opens on the original, remembers sparky', (
      tester,
    ) async {
      _fake.data = docData(summary: 'A plan for the next quarter.');
      await _app(tester, const PdfPreviewScreen(file: _pdf));
      await _settle(tester);
      expect(find.byType(SparkyView), findsNothing);
      await _tapLabel(tester, PreviewStrings.viewSparky);
      expect(find.text('A plan for the next quarter.'), findsOneWidget);
      expect(await PreviewViewPrefs.load(PreviewType.pdf), PreviewView.sparky);

      // A fresh screen starts where the last one ended.
      await _app(tester, const SizedBox());
      await _app(tester, const PdfPreviewScreen(file: _pdf));
      await _settle(tester);
      expect(find.byType(SparkyView), findsOneWidget);
    });

    testWidgets('a picked local file has no toggle', (tester) async {
      final f = File('${_dir.path}/note.txt')..writeAsStringSync('hello');
      final local = FileInfo(
        id: '',
        name: 'note.txt',
        kind: FileKind.document,
        localPath: f.path,
      );
      await _app(tester, TextPreviewScreen(file: local));
      await _settle(tester);
      expect(find.text(PreviewStrings.viewSparky), findsNothing);
    });

    testWidgets('images open on the picture; sparky shows caption and OCR', (
      tester,
    ) async {
      _fake.data = imageData();
      await _app(tester, const FileImageViewer(files: [_photo], initial: 0));
      await _settle(tester);
      expect(find.byType(SparkyView), findsNothing);
      await _tapLabel(tester, PreviewStrings.viewSparky);
      expect(find.text('A receipt on a wooden table.'), findsOneWidget);
      expect(
        find.textContaining('TOTAL 12.40', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('video: switching to sparky pauses nothing it never started', (
      tester,
    ) async {
      _fake.data = videoData();
      const video = FileInfo(id: 'v1', name: 'trip.mp4', kind: FileKind.video);
      await _app(tester, const MediaPreviewScreen(file: video));
      await _settle(tester);
      await _tapLabel(tester, PreviewStrings.viewSparky);
      expect(find.text(PreviewStrings.sparkyTimeline), findsWidgets);
      expect(find.text('A dog runs across a beach.'), findsOneWidget);
      expect(find.text('Look at him go'), findsOneWidget);
    });
  });

  group('sparky view states', () {
    testWidgets('an image sparky has not read yet offers READ IT NOW', (
      tester,
    ) async {
      _fake.data = const InsightData(hasText: false, chars: 0);
      _fake.afterRead = imageData();
      await _app(tester, const Scaffold(body: SparkyView(file: _photo)));
      await _settle(tester);
      expect(find.text(PreviewStrings.sparkyNotReadTitle), findsOneWidget);
      await _tapLabel(tester, PreviewStrings.sparkyReadNow);
      expect(_fake.readCalls, 1);
      expect(find.text('A receipt on a wooden table.'), findsOneWidget);
      expect(find.text(PreviewStrings.sparkyNotReadTitle), findsNothing);
    });

    testWidgets('a failed read says so and can be tried again', (tester) async {
      _fake.data = const InsightData(hasText: false, chars: 0);
      _fake.failRead = true;
      await _app(tester, const Scaffold(body: SparkyView(file: _photo)));
      await _settle(tester);
      await _tapLabel(tester, PreviewStrings.sparkyReadNow);
      expect(find.text(PreviewStrings.sparkyReadFailed), findsOneWidget);
      _fake.failRead = false;
      _fake.afterRead = imageData();
      await _tapLabel(tester, PreviewStrings.sparkyReadNow);
      expect(find.text('A receipt on a wooden table.'), findsOneWidget);
    });

    testWidgets('a document with text but no summary offers SUMMARIZE', (
      tester,
    ) async {
      _fake.data = docData();
      _fake.pages = ['First page text.'];
      _fake.afterRead = docData(
        summary: 'It is about rent.',
        points: ['500 a month'],
      );
      await _app(tester, const Scaffold(body: SparkyView(file: _pdf)));
      await _settle(tester);
      expect(find.text(PreviewStrings.sparkySummarize), findsOneWidget);
      expect(
        find.textContaining('First page text.', findRichText: true),
        findsOneWidget,
      );
      await _tapLabel(tester, PreviewStrings.sparkySummarize);
      expect(find.text('It is about rent.'), findsOneWidget);
      expect(find.text('500 a month'), findsOneWidget);
      expect(find.text(PreviewStrings.sparkySummarize), findsNothing);
    });

    testWidgets('long text pages in with LOAD MORE', (tester) async {
      _fake.data = docData(summary: 'Long.', chars: 30);
      _fake.pages = ['first part ', 'second part'];
      await _app(tester, const Scaffold(body: SparkyView(file: _pdf)));
      await _settle(tester);
      expect(
        find.textContaining('second part', findRichText: true),
        findsNothing,
      );
      final more = find.textContaining('LOAD MORE');
      await tester.scrollUntilVisible(
        more,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(more);
      await _settle(tester);
      expect(
        find.textContaining('second part', findRichText: true),
        findsOneWidget,
      );
      expect(_fake.offsets, [0, 11]);
    });

    testWidgets('a file still being read says to check again', (tester) async {
      _fake.data = const InsightData(
        hasText: false,
        chars: 0,
        processing: true,
      );
      await _app(tester, const Scaffold(body: SparkyView(file: _pdf)));
      await _settle(tester);
      expect(find.text(PreviewStrings.sparkyBusyTitle), findsOneWidget);
      _fake.data = docData(summary: 'Done now.');
      await _tapLabel(tester, PreviewStrings.sparkyCheckAgain);
      expect(find.text('Done now.'), findsOneWidget);
    });

    testWidgets('a scan with no text explains itself', (tester) async {
      _fake.data = const InsightData(hasText: false, chars: 0);
      await _app(tester, const Scaffold(body: SparkyView(file: _pdf)));
      await _settle(tester);
      expect(find.text(PreviewStrings.sparkyNoTextTitle), findsOneWidget);
    });

    testWidgets('a server error shows the retry state', (tester) async {
      _fake.failInsight = true;
      await _app(tester, const Scaffold(body: SparkyView(file: _pdf)));
      await _settle(tester);
      expect(find.text(PreviewStrings.sparkyErrorTitle), findsOneWidget);
      _fake.failInsight = false;
      _fake.data = docData(summary: 'Back again.');
      await _tapLabel(tester, AppStrings.retry);
      expect(find.text('Back again.'), findsOneWidget);
    });

    testWidgets('audio shows its transcript', (tester) async {
      _fake.data = docData(summary: 'A voice memo about groceries.');
      _fake.pages = ['Buy milk and eggs.'];
      const audio = FileInfo(id: 'a1', name: 'memo.m4a', kind: FileKind.audio);
      await _app(tester, const Scaffold(body: SparkyView(file: audio)));
      await _settle(tester);
      expect(find.text(PreviewStrings.sparkyTranscript), findsOneWidget);
      expect(
        find.textContaining('Buy milk and eggs.', findRichText: true),
        findsOneWidget,
      );
    });
  });

  group('text shaping', () {
    test('wrapped prose joins, short lines and lists keep their breaks', () {
      const raw =
          'The tenant agrees to pay the rent on the first day of each\n'
          'month and to keep the flat in good order throughout the term.\r\n'
          '\r\n\r\n\r\n'
          'Name: A\nCity: Pune\n\n'
          '- one\n- two\n';
      expect(
        readableMarkdown(raw),
        'The tenant agrees to pay the rent on the first day of each '
        'month and to keep the flat in good order throughout the term.\n\n'
        'Name: A  \nCity: Pune\n\n'
        '- one\n- two',
      );
    });

    test('the timeline orders frames and speech by time', () {
      const v = VideoTimeline(
        durationS: 60,
        captionStatus: 'ok',
        transcriptStatus: 'ok',
        frames: [
          TimelineFrame(t: 0, caption: 'Start'),
          TimelineFrame(t: 30, caption: 'Middle'),
          TimelineFrame(t: 45),
        ],
        segments: [
          TimelineSegment(start: 0, end: 20, text: 'Hello'),
          TimelineSegment(start: 25, end: 40, text: 'Goodbye'),
        ],
      );
      expect(
        [for (final e in timelineOf(v)) e.text],
        ['Start', 'Hello', 'Goodbye', 'Middle'],
      );
    });
  });
}
