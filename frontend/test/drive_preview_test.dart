import 'dart:convert';
import 'dart:io';

import 'package:app/core/constants/connectors.dart';
import 'package:app/core/constants/preview.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/connect_api.dart';
import 'package:app/data/drive_ref.dart';
import 'package:app/data/file_cache.dart';
import 'package:app/data/file_insight.dart';
import 'package:app/features/chat/chat_launch.dart';
import 'package:app/features/chat/preview/file_actions.dart';
import 'package:app/features/chat/preview/pdf_preview.dart';
import 'package:app/features/chat/preview/preview_type.dart';
import 'package:app/features/chat/preview/preview_view.dart';
import 'package:app/features/chat/preview/sparky_view.dart';
import 'package:app/features/connectors/connector_auth.dart';
import 'package:app/features/connectors/drive_browse_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_understanding.dart';

DriveFile _drive({
  String id = 'drv1234567890',
  String name = 'Plan',
  String mime = 'application/vnd.google-apps.document',
  String modified = '2026-10-01T10:00:00.000Z',
  int? size,
}) => DriveFile({
  'id': id,
  'name': name,
  'mimeType': mime,
  'modifiedTime': modified,
  'size': size,
  'webViewLink': 'https://docs.google.com/d/$id',
  'kind': 'markdown',
});

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

late FakeUnderstanding _fake;
late Directory _dir;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _fake = FakeUnderstanding();
    FileUnderstanding.instance = _fake;
    _dir = Directory.systemTemp.createTempSync('drive_preview');
    ChatLaunch.instance.prompt.value = null;
    ChatLaunch.instance.apps = const [];
  });
  tearDown(() => _dir.deleteSync(recursive: true));

  group('Drive item as a preview file', () {
    test('the id is stable for one version and changes when edited', () {
      final a = DriveRef.toFileInfo(_drive());
      final same = DriveRef.toFileInfo(_drive());
      final edited = DriveRef.toFileInfo(
        _drive(modified: '2026-10-02T10:00:00.000Z'),
      );
      expect(a.id, same.id);
      expect(a.id, isNot(edited.id));
      expect(a.id, startsWith('drive:drv1234567890:'));
      expect(a.driveFileId, 'drv1234567890');
      expect(DriveRef.fileIdOf(a.id), 'drv1234567890');
      expect(DriveRef.dirName(a.id), isNot(contains(':')));
    });

    test('Google Docs, Sheets and Slides preview as their exported PDF', () {
      for (final m in const [
        'application/vnd.google-apps.document',
        'application/vnd.google-apps.spreadsheet',
        'application/vnd.google-apps.presentation',
      ]) {
        final f = DriveRef.toFileInfo(_drive(mime: m));
        expect(previewTypeOf(f), PreviewType.pdf, reason: m);
        expect(f.name, 'Plan.pdf');
        expect(hasSparkyView(f), isTrue);
      }
    });

    test('images, video, audio, Office and unknown types map to viewers', () {
      PreviewType t(String name, String mime) =>
          previewTypeOf(DriveRef.toFileInfo(_drive(name: name, mime: mime)));
      expect(t('a.png', 'image/png'), PreviewType.image);
      expect(t('a.mp4', 'video/mp4'), PreviewType.video);
      expect(t('a.mp3', 'audio/mpeg'), PreviewType.audio);
      expect(t('a.pdf', 'application/pdf'), PreviewType.pdf);
      expect(
        t(
          'a.docx',
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        ),
        PreviewType.office,
      );
      expect(t('notes', 'text/plain'), PreviewType.text);
      expect(t('a.zip', 'application/zip'), PreviewType.unknown);
    });

    test('a Drive file cannot be deleted from here but can be asked about', () {
      final f = DriveRef.toFileInfo(_drive());
      expect(canDeleteFile(f), isFalse);
      expect(canAskAboutFile(f), isTrue);
    });
  });

  group('the original comes through the authed backend proxy', () {
    FileCache cache(http.Client inner, List<String> infoCalls) => FileCache(
      root: () async => Directory('${_dir.path}/cache'),
      info: (id, {force = false}) async {
        infoCalls.add(id);
        throw StateError('Drive never asks for signed links');
      },
      client: () => inner,
    );

    test(
      'one download per version, keyed by file id and modifiedTime',
      () async {
        final urls = <String>[];
        final infoCalls = <String>[];
        final c = cache(
          MockClient.streaming((req, _) async {
            urls.add(req.url.toString());
            return http.StreamedResponse(
              Stream.value(utf8.encode('%PDF-1.7 hello')),
              200,
              contentLength: 14,
            );
          }),
          infoCalls,
        );
        final v1 = DriveRef.toFileInfo(_drive());
        final file = await c.fetch(v1);
        expect(file.readAsStringSync(), '%PDF-1.7 hello');
        expect(
          urls.single,
          contains('/connect/google_drive/files/drv1234567890/raw'),
        );
        expect(urls.single, isNot(contains('token')));
        expect(infoCalls, isEmpty);
        expect(file.path, isNot(contains(':')));

        await c.fetch(v1);
        expect(urls, hasLength(1), reason: 'the second open is a cache hit');

        final v2 = DriveRef.toFileInfo(
          _drive(modified: '2026-10-02T10:00:00.000Z'),
        );
        await c.fetch(v2);
        expect(urls, hasLength(2), reason: 'an edited file is fetched again');
      },
    );

    test('a refused download is a friendly error and leaves no file', () async {
      final c = cache(
        MockClient.streaming(
          (req, _) async => http.StreamedResponse(const Stream.empty(), 404),
        ),
        [],
      );
      final f = DriveRef.toFileInfo(_drive());
      await expectLater(c.fetch(f), throwsA(isA<Exception>()));
      expect(await c.cached(f), isNull);
    });
  });

  group('unified preview', () {
    testWidgets(
      'opening a Drive file shows Original | sparky and the reading',
      (tester) async {
        _fake.data = docData(summary: 'A plan to ship the picker.');
        tester.view.physicalSize = const Size(360, 780);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        FileCache.instance = FileCache(
          root: () async => Directory('${_dir.path}/cache'),
          client: () => MockClient.streaming(
            (req, _) async => http.StreamedResponse(const Stream.empty(), 404),
          ),
        );
        late BuildContext ctx;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Builder(
              builder: (c) {
                ctx = c;
                return const Scaffold();
              },
            ),
          ),
        );
        openDriveFile(ctx, _drive());
        await _settle(tester);
        expect(find.byType(PdfPreviewScreen), findsOneWidget);
        expect(find.text(PreviewStrings.viewOriginal), findsOneWidget);
        expect(find.text(PreviewStrings.viewSparky), findsOneWidget);
        expect(find.byType(SparkyView), findsNothing);

        await tester.tap(find.text(PreviewStrings.viewSparky).first);
        await _settle(tester);
        expect(find.text('A plan to ship the picker.'), findsOneWidget);

        // ASK SPARKY stays: it starts a chat that reads the Drive file live.
        await tester.tap(find.byTooltip(PreviewStrings.ask));
        await _settle(tester);
        expect(ChatLaunch.instance.prompt.value, contains('Plan'));
        expect(ChatLaunch.instance.apps.single, {
          'provider': 'google_drive',
          'id': 'drv1234567890',
          'title': 'Plan.pdf',
        });
        expect(ChatLaunch.instance.files, isEmpty);
      },
    );
  });

  group('folders', () {
    test('the picked summary names imports, skips and the Google limit', () {
      expect(DriveStrings.pickedSummary(picked: 2), DriveStrings.picked(2));
      final s = DriveStrings.pickedSummary(picked: 1, imported: 8, skipped: 2);
      expect(s, contains('9 files added.'));
      expect(s, contains(DriveStrings.fromFolders(8)));
      expect(s, contains(DriveStrings.skippedFiles(2)));
      expect(s, isNot(contains(DriveStrings.folderLimited)));
    });

    test('a folder Google will not open gets the friendly note', () {
      final s = DriveStrings.pickedSummary(picked: 3, limited: 1);
      expect(s, contains('3 files added.'));
      expect(s, endsWith(DriveStrings.folderLimited));
      expect(
        DriveStrings.folderLimited,
        'Google only lets sparky open files you pick — select the files inside the folder.',
      );
      // Nothing picked but a limited folder: only the note, not "No new files".
      expect(
        DriveStrings.pickedSummary(picked: 0, limited: 2),
        DriveStrings.folderLimited,
      );
    });

    test(
      'the picker deep link carries the folder counts to the outcome',
      () async {
        SharedPreferences.setMockInitialValues({
          'connector_web_pending': jsonEncode({
            'provider': 'google_drive',
            'flow': 'picker',
            'state': 'st4te',
            'url': 'https://x',
            'at': DateTime.now().millisecondsSinceEpoch,
          }),
        });
        final outcome = ConnectorAuth.instance.outcomes.first;
        await ConnectorAuth.instance.handleLink(
          Uri.parse(
            'sparky://auth/connect?provider=google_drive&mode=picker&picked=2&imported=7&skipped=1&limited=1&state=st4te',
          ),
        );
        final o = await outcome;
        expect(o.ok, isTrue);
        expect([o.picked, o.imported, o.skipped, o.limited], [2, 7, 1, 1]);
      },
    );
  });
}
