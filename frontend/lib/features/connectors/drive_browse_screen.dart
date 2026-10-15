import 'package:flutter/material.dart';

import '../../core/constants/app_icons.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/constants/connectors.dart';
import '../../core/haptics.dart';
import '../../core/theme/app_palette.dart';
import '../../core/time_ago.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/m3_kit_extras.dart';
import '../../data/connect_api.dart';
import '../../data/drive_ref.dart';
import '../chat/preview/file_preview.dart';
import '../github/widgets/gh_rows.dart';
import '../settings/widgets/settings_kit.dart';
import 'connector_controllers.dart';
import 'widgets/connector_kit.dart';

enum DriveFilter { all, docs, sheets, pdfs, other }

enum DriveSort { recent, name }

const _gdoc = 'application/vnd.google-apps.document';
const _gsheet = 'application/vnd.google-apps.spreadsheet';
const _gslides = 'application/vnd.google-apps.presentation';
const _pdf = 'application/pdf';
const _docx =
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
const _xlsx =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
const _pptx =
    'application/vnd.openxmlformats-officedocument.presentationml.presentation';

/// Bundled logo of a Drive file's type (shown until, or instead of, the
/// icon Google serves for it).
AppIconData driveIcon(DriveFile f) => switch (f.mimeType) {
  _gdoc => DriveIcons.doc,
  _gsheet => DriveIcons.sheet,
  _gslides => DriveIcons.slides,
  _pdf => DriveIcons.pdf,
  _docx || 'application/msword' => DriveIcons.word,
  _xlsx || 'application/vnd.ms-excel' => DriveIcons.excel,
  _pptx || 'application/vnd.ms-powerpoint' => DriveIcons.powerpoint,
  final m when m.startsWith('image/') => DriveIcons.image,
  final m when m.startsWith('text/') => DriveIcons.text,
  _ => DriveIcons.other,
};

String driveKindLabel(DriveFile f) => switch (f.mimeType) {
  _gdoc => DriveStrings.kindDoc,
  _gsheet => DriveStrings.kindSheet,
  _gslides => DriveStrings.kindSlides,
  _pdf => DriveStrings.kindPdf,
  final m when m.startsWith('text/') => DriveStrings.kindText,
  _ => DriveStrings.kindOther,
};

bool driveMatches(DriveFile f, DriveFilter filter) => switch (filter) {
  DriveFilter.all => true,
  DriveFilter.docs => f.mimeType == _gdoc,
  DriveFilter.sheets => f.mimeType == _gsheet,
  DriveFilter.pdfs => f.mimeType == _pdf,
  DriveFilter.other => !{_gdoc, _gsheet, _pdf}.contains(f.mimeType),
};

/// Opens a Drive file in the unified preview (Original | sparky).
void openDriveFile(BuildContext context, DriveFile f) {
  final info = DriveRef.toFileInfo(f);
  openFilePreview(context, [info], info);
}

/// One file row: type icon, name, "Google Doc · 3h ago", chevron.
class DriveFileTile extends StatelessWidget {
  const DriveFileTile({super.key, required this.file, this.now});

  final DriveFile file;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final kind = driveKindLabel(file);
    final m = file.modified;
    return SettingsTile(
      icon: driveIcon(file),
      leading: ConnectorRowIcon(icon: driveIcon(file), imageUrl: file.iconLink),
      title: file.name,
      summary: m == null
          ? kind
          : '$kind · ${timeAgo(m, now ?? DateTime.now())}',
      trailing: AppIcon(
        AppIcons.chevronRight,
        size: AppIconSize.sm,
        color: scheme.onSurfaceVariant,
      ),
      onTap: () => openDriveFile(context, file),
    );
  }
}

/// "Your Drive files": every file sparky can see, with search, type
/// filters and sort. Shares the connector screen's [DriveController].
class DriveBrowseScreen extends StatefulWidget {
  const DriveBrowseScreen({super.key, required this.controller, this.now});

  final DriveController controller;
  final DateTime? now;

  @override
  State<DriveBrowseScreen> createState() => _DriveBrowseScreenState();
}

class _DriveBrowseScreenState extends State<DriveBrowseScreen> {
  late final TextEditingController _search = TextEditingController(
    text: widget.controller.query,
  );
  DriveFilter _filter = DriveFilter.all;
  DriveSort _sort = DriveSort.recent;

  DriveController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    if (!_c.loaded && !_c.loading) _c.load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  static String _filterLabel(DriveFilter f) => switch (f) {
    DriveFilter.all => DriveStrings.filterAll,
    DriveFilter.docs => DriveStrings.filterDocs,
    DriveFilter.sheets => DriveStrings.filterSheets,
    DriveFilter.pdfs => DriveStrings.filterPdfs,
    DriveFilter.other => DriveStrings.filterOther,
  };

  static String _sortLabel(DriveSort s) => switch (s) {
    DriveSort.recent => DriveStrings.sortRecent,
    DriveSort.name => DriveStrings.sortName,
  };

  List<DriveFile> get _shown {
    final list = [
      for (final f in _c.items ?? const <DriveFile>[])
        if (driveMatches(f, _filter)) f,
    ];
    if (_sort == DriveSort.name) {
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } else {
      final epoch = DateTime.fromMillisecondsSinceEpoch(0);
      list.sort((a, b) => (b.modified ?? epoch).compareTo(a.modified ?? epoch));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        final shown = _shown;
        final scheme = Theme.of(context).colorScheme;
        Widget? message;
        if (_c.items == null) {
          message = _c.error != null && !_c.loading
              ? M3Empty(
                  icon: _c.offline
                      ? ConnectorIcons.offline
                      : ConnectorIcons.warning,
                  title: _c.offline
                      ? ConnectorStrings.offline
                      : ConnectorStrings.loadFailed,
                  action: FilledButton.tonal(
                    onPressed: _c.load,
                    child: const Text(ConnectorStrings.retry),
                  ),
                )
              : const GhSkeletonCells(count: ConnectorSizes.skeletonRows);
        } else if (shown.isEmpty) {
          message = M3Empty(
            icon: DriveIcons.fallback,
            title: _c.query.isNotEmpty
                ? DriveStrings.noMatches
                : _filter == DriveFilter.all
                ? DriveStrings.noFiles
                : DriveStrings.noFilterMatches,
            hint: _c.query.isEmpty && _filter == DriveFilter.all
                ? DriveStrings.noFilesHint
                : null,
          );
        }
        return M3Page(
          title: DriveStrings.browseTitle,
          onRefresh: _c.load,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenPadding,
                AppSpacing.sm,
                AppSpacing.screenPadding,
                AppSpacing.md,
              ),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    GhPillSearch(
                      hint: DriveStrings.filter,
                      controller: _search,
                      onChanged: _c.setQuery,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          PopupMenuButton<DriveSort>(
                            tooltip: DriveStrings.sortLabel,
                            initialValue: _sort,
                            onSelected: (s) {
                              Haptics.tap();
                              setState(() => _sort = s);
                            },
                            itemBuilder: (_) => [
                              for (final s in DriveSort.values)
                                PopupMenuItem(
                                  value: s,
                                  child: Text(_sortLabel(s)),
                                ),
                            ],
                            child: Chip(
                              avatar: AppIcon(
                                AppIcons.sortDescending,
                                size: AppIconSize.sm,
                                color: scheme.onSurface,
                              ),
                              label: Text(_sortLabel(_sort)),
                            ),
                          ),
                          for (final f in DriveFilter.values) ...[
                            const SizedBox(width: AppSpacing.sm),
                            ChoiceChip(
                              label: Text(_filterLabel(f)),
                              selected: _filter == f,
                              showCheckmark: false,
                              onSelected: (_) {
                                Haptics.tap();
                                setState(() => _filter = f);
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (_c.offline || _c.rateLimited) ...[
                      const SizedBox(height: AppSpacing.md),
                      ConnectorBanner(
                        icon: _c.offline
                            ? ConnectorIcons.offline
                            : ConnectorIcons.warning,
                        text: _c.offline
                            ? ConnectorStrings.offline
                            : ConnectorStrings.rateLimited,
                        action: ConnectorStrings.retry,
                        onAction: _c.load,
                      ),
                    ],
                    if (message == null) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        DriveStrings.fileCount(shown.length),
                        style: context.text.caption.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenPadding,
              ),
              sliver: message != null
                  ? SliverToBoxAdapter(child: message)
                  : SliverList.builder(
                      itemCount: shown.length,
                      itemBuilder: (context, i) => M3Cell(
                        index: i,
                        count: shown.length,
                        child: DriveFileTile(file: shown[i], now: widget.now),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}
