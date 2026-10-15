import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/file_insight.dart';
import 'package:app/data/files_api.dart';
import 'package:app/features/chat/preview/preview_actions.dart';
import 'package:app/features/chat/preview/preview_view.dart';
import 'package:app/features/chat/preview/sparky_view.dart';
import 'package:app/features/chat/preview/text_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_understanding.dart';

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

Future<void> _show(WidgetTester tester, Widget home, bool dark) async {
  tester.view.physicalSize = const Size(412, 915) * 2.6;
  tester.view.devicePixelRatio = 2.6;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: dark ? AppTheme.dark : AppTheme.light,
      home: home,
    ),
  );
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// A preview shell: the real bar with the toggle over a sparky view.
class _Shell extends StatelessWidget {
  const _Shell({required this.file, required this.view});
  final FileInfo file;
  final PreviewView view;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: PreviewBar(file: file, view: view, onView: (_) {}),
    body: SparkyView(file: file),
  );
}

void main() {
  setUpAll(_fonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final (name, dark) in const [('light', false), ('dark', true)]) {
    testWidgets('sparky view of a document ($name)', (tester) async {
      final fake = FakeUnderstanding()
        ..data = docData(
          summary:
              'A one-year lease for a two-bedroom flat in Pune, starting '
              'on 1 June, with rent due on the first of each month.',
          points: [
            'Rent is ₹25,000 a month',
            'Deposit of ₹75,000, refundable on exit',
            'Either side can end it with 60 days’ notice',
          ],
        )
        ..pages = [
          'Lease agreement\n\nThis agreement is made between the landlord and '
              'the tenant for the flat described below, for a term of twelve '
              'months from the first of June.\n\n- Rent is paid monthly\n'
              '- The deposit is refundable\n\nSigned in Pune.',
        ];
      FileUnderstanding.instance = fake;
      const file = FileInfo(
        id: 'o1',
        name: 'Lease.docx',
        kind: FileKind.document,
        mime:
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        size: 48000,
      );
      await _show(tester, const TextPreviewScreen(file: file), dark);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/sparky_view_doc_$name.png'),
      );
    });
  }

  testWidgets('sparky view of a video: timeline (light)', (tester) async {
    FileUnderstanding.instance = FakeUnderstanding()..data = videoData();
    const file = FileInfo(id: 'v1', name: 'trip.mp4', kind: FileKind.video);
    await _show(
      tester,
      const _Shell(file: file, view: PreviewView.sparky),
      false,
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/sparky_view_video_light.png'),
    );
  });

  testWidgets('sparky view not read yet (dark)', (tester) async {
    FileUnderstanding.instance = FakeUnderstanding()
      ..data = const InsightData(hasText: false, chars: 0);
    const file = FileInfo(id: 'i1', name: 'receipt.jpg', kind: FileKind.image);
    await _show(
      tester,
      const _Shell(file: file, view: PreviewView.sparky),
      true,
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/sparky_view_unread_dark.png'),
    );
  });
}
