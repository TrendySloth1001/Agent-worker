import 'package:app/core/constants/app_files.dart';
import 'package:app/core/constants/app_strings.dart';
import 'package:app/core/constants/storage.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/core/widgets/dot_meter.dart';
import 'package:app/data/chat_message.dart';
import 'package:app/data/files_api.dart';
import 'package:app/features/chat/widgets/attachment_views.dart';
import 'package:app/features/storage/storage_screen.dart';
import 'package:app/features/storage/widgets/storage_tiles.dart';
import 'package:app/features/storage/widgets/storage_usage_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _id = '0f8fad5b-d9cb-469f-a165-70867728950e';

void main() {
  group('FileInfo', () {
    test('reads the deleted placeholder and library fields', () {
      final f = FileInfo.fromJson({
        'id': _id,
        'name': 'clip.mp4',
        'kind': 'video',
        'status': AppFiles.deletedStatus,
        'deleted': true,
        'createdAt': '2026-10-11T18:32:40.000Z',
        'conversation': {'id': 'c1', 'title': 'Trip'},
      });
      expect(f.deleted, isTrue);
      expect(f.kind, FileKind.video);
      expect(f.conversationId, 'c1');
      expect(f.conversationTitle, 'Trip');
      expect(f.createdAt, isNotNull);
      expect(f.toStorageJson()['deleted'], isTrue);
    });

    test('asDeleted drops the links, renamed keeps the rest', () {
      const f = FileInfo(
        id: _id,
        name: 'a.png',
        kind: FileKind.image,
        url: 'https://x/a',
        thumbUrl: 'https://x/t',
      );
      final d = f.asDeleted();
      expect(d.deleted, isTrue);
      expect(d.url, isNull);
      expect(d.thumbUrl, isNull);
      final r = f.renamed('b.png');
      expect(r.name, 'b.png');
      expect(r.url, f.url);
    });
  });

  test('StorageUsage parses limits, unlimited and per-kind totals', () {
    final u = StorageUsage.fromJson({
      'totalBytes': 50,
      'count': 3,
      'byKind': {
        'image': {'count': 2, 'bytes': 30},
        'video': {'count': 1, 'bytes': 20},
      },
      'limits': {'storageBytes': 100, 'uploadsPerDay': 20},
      'today': {'uploads': 4, 'bytes': 50},
    });
    expect(u.fraction, 0.5);
    expect(u.full, isFalse);
    expect(u.byKind[FileKind.image]!.count, 2);
    expect(u.byKind[FileKind.audio]!.bytes, 0);
    expect(u.uploadsToday, 4);
    final unlimited = StorageUsage.fromJson({
      'totalBytes': 50,
      'limits': {'storageBytes': null},
    });
    expect(unlimited.limitBytes, isNull);
    expect(unlimited.fraction, 0);
  });

  test('safeFileName strips paths and reserved characters', () {
    expect(safeFileName('../../etc/passwd'), 'passwd');
    expect(safeFileName('a:b?.txt'), 'a_b_.txt');
    expect(safeFileName('..'), AppFiles.fallbackName);
  });

  test('chat history leaves out deleted files', () {
    final m = ChatMessage(
      role: Role.user,
      content: '',
    )..attachments = [const FileInfo(id: 'gone', name: 'x.png', deleted: true)];
    final j = m.toJson();
    expect(j.containsKey('attachments'), isFalse);
    expect(j['content'], AppFiles.deletedHistoryText);

    final mixed = ChatMessage(role: Role.user, content: 'hi')
      ..attachments = [
        const FileInfo(id: 'gone', name: 'x.png', deleted: true),
        const FileInfo(id: 'kept', name: 'y.png'),
      ];
    expect(mixed.toJson()['attachments'], ['kept']);
    expect(mixed.toJson()['content'], 'hi');
  });

  test('formatBytes covers GB', () {
    expect(formatBytes(512), '512 B');
    expect(formatBytes(3 * AppFiles.mb ~/ 2), '1.5 MB');
    expect(formatBytes(2 * AppFiles.gb), '2.00 GB');
  });

  for (final (name, theme) in [
    ('light', AppTheme.light),
    ('dark', AppTheme.dark),
  ]) {
    testWidgets('storage screen: filter, select, bulk delete ($name)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = _FakeFiles();
      Finder chip(String label) => find.descendant(
        of: find.byType(StorageChip),
        matching: find.text(label),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: StorageScreen(api: api),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(StorageGridTile), findsNWidgets(4));
      expect(find.byType(StorageListRow), findsNWidgets(2));
      expect(find.textContaining('Planning'), findsOneWidget);

      // Documents only: the grid goes away.
      await tester.tap(chip(StorageStrings.documents));
      await tester.pumpAndSettle();
      expect(find.byType(StorageGridTile), findsNothing);
      expect(find.byType(StorageListRow), findsOneWidget);
      await tester.tap(chip(StorageStrings.all));
      await tester.pumpAndSettle();

      // Select two videos and delete them.
      await tester.tap(find.byTooltip(StorageStrings.select));
      await tester.pump();
      await tester.tap(find.byType(StorageGridTile).at(0));
      await tester.tap(find.byType(StorageGridTile).at(1));
      await tester.pump();
      expect(find.text(StorageStrings.selected(2)), findsOneWidget);
      await tester.tap(find.byTooltip(StorageStrings.delete));
      await tester.pumpAndSettle();
      expect(find.text(StorageStrings.deleteTitle(2)), findsOneWidget);
      await tester.tap(find.text(StorageStrings.delete).last);
      await tester.pumpAndSettle();
      expect(api.deleted, ['v0', 'v1']);
      expect(find.byType(StorageGridTile), findsNWidgets(2));
      expect(find.text(StorageStrings.selected(2)), findsNothing);
      expect(tester.takeException(), isNull);
    });

    Widget wrap(Widget child) => MaterialApp(
      theme: theme,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

    testWidgets('deleted attachment tile ($name)', (tester) async {
      await tester.pumpWidget(
        wrap(
          const DeletedFileTile(
            file: FileInfo(id: _id, name: 'report.pdf', deleted: true),
          ),
        ),
      );
      expect(find.text(AppStrings.attachDeleted), findsOneWidget);
      expect(find.text('report.pdf'), findsOneWidget);
    });

    testWidgets('usage card shows limit and kinds ($name)', (tester) async {
      final u = StorageUsage.fromJson({
        'totalBytes': 1024 * 1024,
        'count': 1,
        'byKind': {
          'video': {'count': 1, 'bytes': 1024 * 1024},
        },
        'limits': {'storageBytes': 100 * 1024 * 1024},
      });
      await tester.pumpWidget(wrap(StorageUsageCard(usage: u)));
      expect(find.text('1.0 MB'), findsWidgets);
      expect(find.text('${StorageStrings.of} 100.0 MB'), findsOneWidget);
      expect(find.text(StorageStrings.videos), findsOneWidget);
      expect(find.text(StorageStrings.unlimited), findsNothing);
    });

    testWidgets('usage hero shows dot bar and kinds ($name)', (tester) async {
      final u = StorageUsage.fromJson({
        'totalBytes': 1024 * 1024,
        'count': 1,
        'byKind': {
          'video': {'count': 1, 'bytes': 1024 * 1024},
        },
        'limits': {'storageBytes': 100 * 1024 * 1024, 'uploadsPerDay': 20},
      });
      await tester.pumpWidget(wrap(StorageHero(usage: u)));
      expect(find.byType(DotMeter), findsOneWidget);
      expect(find.text('1.0 MB'), findsWidgets);
      expect(find.text(StorageStrings.videos), findsOneWidget);
      expect(find.text(StorageStrings.uploadsToday), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('grid tile and list row ($name)', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        wrap(
          Column(
            children: [
              SizedBox(
                width: 120,
                height: 120,
                child: StorageGridTile(
                  file: const FileInfo(
                    id: _id,
                    name: 'clip.mp4',
                    kind: FileKind.video,
                    status: FileStatus.ready,
                    meta: {'durationS': 65},
                  ),
                  selecting: true,
                  selected: true,
                  onTap: () => taps++,
                  onLongPress: () {},
                ),
              ),
              StorageListRow(
                file: const FileInfo(
                  id: 'd',
                  name: 'notes.pdf',
                  status: FileStatus.failed,
                ),
                selecting: false,
                selected: false,
                onTap: () {},
                onLongPress: () {},
                onMore: () {},
              ),
            ],
          ),
        ),
      );
      expect(find.text('1:05'), findsOneWidget);
      expect(find.text('notes.pdf'), findsOneWidget);
      expect(find.textContaining(StorageStrings.failed), findsOneWidget);
      expect(find.textContaining(StorageStrings.notInChat), findsOneWidget);
      await tester.tap(find.byType(StorageGridTile));
      expect(taps, 1);
    });
  }
}

/// In-memory files for the Storage screen.
class _FakeFiles extends Fake implements FilesApi {
  final files = <FileInfo>[
    for (var i = 0; i < 4; i++)
      FileInfo(
        id: 'v$i',
        name: 'clip $i.mp4',
        kind: FileKind.video,
        status: FileStatus.ready,
        size: 1000 * (i + 1),
        meta: const {'durationS': 12},
      ),
    const FileInfo(
      id: 'd1',
      name: 'a very long document name that keeps going and going.pdf',
      size: 2048,
      status: FileStatus.ready,
      conversationId: 'c1',
      conversationTitle: 'Planning',
    ),
    const FileInfo(
      id: 'a1',
      name: 'memo.m4a',
      kind: FileKind.audio,
      status: FileStatus.processing,
    ),
  ];
  final deleted = <String>[];

  @override
  final changes = ValueNotifier<int>(0);

  @override
  Future<FilePage> list({
    FileKind? kind,
    String query = '',
    StorageSort sort = StorageSort.newest,
    String? cursor,
  }) async => FilePage(
    files: files
        .where((f) => kind == null || f.kind == kind)
        .where((f) => f.name.contains(query))
        .toList(),
  );

  @override
  Future<StorageUsage> usage() async => StorageUsage(
    totalBytes: files.fold(0, (n, f) => n + f.size),
    count: files.length,
    byKind: {for (final k in FileKind.values) k: (count: 0, bytes: 0)},
    limitBytes: 100 * AppFiles.mb,
  );

  @override
  Future<int> bulkDelete(List<String> ids) async {
    deleted.addAll(ids);
    files.removeWhere((f) => ids.contains(f.id));
    return ids.length;
  }
}
