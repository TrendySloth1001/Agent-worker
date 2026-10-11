import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/app_icons.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/constants/app_strings.dart';
import '../../core/constants/storage.dart';
import '../../core/haptics.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/system_chrome.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/icon_label.dart';
import '../../data/files_api.dart';
import 'storage_actions.dart';
import 'storage_controller.dart';
import 'widgets/storage_tiles.dart';
import 'widgets/storage_usage_card.dart';

/// The user's stored files: usage, filters, search, sort, grid of media,
/// list of documents and audio, multi-select delete and per-file actions.
class StorageScreen extends StatefulWidget {
  const StorageScreen({super.key, this.api});

  /// Defaults to [FilesApi.instance]; tests pass a fake.
  final FilesApi? api;

  static Future<void> open(BuildContext context) {
    Haptics.tap();
    return Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const StorageScreen()));
  }

  @override
  State<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends State<StorageScreen> {
  late final _c = StorageController(api: widget.api);
  final _search = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _c.reload();
    _scroll.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _c.dispose();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    final pos = _scroll.position;
    if (pos.extentAfter < StorageSizes.loadMoreExtent) _c.loadMore();
  }

  void _onTap(FileInfo f) {
    if (_c.selecting) {
      Haptics.tap();
      _c.toggle(f.id);
    } else {
      openStorageFile(context, _c, f);
    }
  }

  void _onLongPress(FileInfo f) {
    if (_c.selecting) {
      Haptics.tap();
      _c.toggle(f.id);
    } else {
      showStorageActions(context, _c, f);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: systemOverlayFor(context),
      child: ListenableBuilder(
        listenable: _c,
        builder: (context, _) => PopScope(
          canPop: !_c.selecting,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _c.clearSelection();
          },
          child: Scaffold(
            appBar: _appBar(context, p),
            body: RefreshIndicator(
              color: p.accent,
              backgroundColor: p.surface,
              onRefresh: _c.reload,
              child: CustomScrollView(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screenPadding,
                      AppSpacing.lg,
                      AppSpacing.screenPadding,
                      0,
                    ),
                    sliver: SliverList.list(
                      children: [
                        StorageUsageCard(usage: _c.usage, loading: _c.loading),
                        const SizedBox(height: AppSpacing.lg),
                        _searchField(context, p),
                        const SizedBox(height: AppSpacing.md),
                        _filters(context, p),
                        const SizedBox(height: AppSpacing.md),
                      ],
                    ),
                  ),
                  ..._content(context, p),
                  SliverPadding(
                    padding: EdgeInsets.only(
                      bottom:
                          MediaQuery.paddingOf(context).bottom + AppSpacing.xl,
                    ),
                    sliver: SliverToBoxAdapter(child: _footer(context, p)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _appBar(BuildContext context, AppPalette p) {
    final selecting = _c.selecting;
    final n = _c.selected.length;
    return AppBar(
      leading: IconButton(
        icon: AppIcon(
          selecting ? AppIcons.close : AppIcons.back,
          size: AppIconSize.md,
        ),
        tooltip: selecting ? StorageStrings.clearSelection : AppStrings.back,
        onPressed: () {
          Haptics.tap();
          selecting ? _c.clearSelection() : Navigator.pop(context);
        },
      ),
      title: Text(
        selecting ? StorageStrings.selected(n) : StorageStrings.title,
      ),
      actions: selecting
          ? [
              IconButton(
                icon: const AppIcon(StorageIcons.select, size: AppIconSize.md),
                tooltip: StorageStrings.selectAll,
                onPressed: () {
                  Haptics.tap();
                  _c.selectAll();
                },
              ),
              IconButton(
                icon: AppIcon(
                  StorageIcons.delete,
                  size: AppIconSize.md,
                  color: n == 0 ? p.disabled : p.accent,
                ),
                tooltip: StorageStrings.delete,
                onPressed: n == 0
                    ? null
                    : () => confirmStorageDelete(
                        context,
                        _c,
                        _c.selected.toList(),
                      ),
              ),
            ]
          : [
              IconButton(
                icon: const AppIcon(StorageIcons.select, size: AppIconSize.md),
                tooltip: StorageStrings.select,
                onPressed: _c.files.isEmpty
                    ? null
                    : () {
                        Haptics.tap();
                        _c.startSelecting();
                      },
              ),
            ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(AppBorder.thin),
        child: Divider(color: p.border),
      ),
    );
  }

  Widget _searchField(BuildContext context, AppPalette p) => TextField(
    controller: _search,
    onChanged: _c.setQuery,
    style: context.text.body,
    textInputAction: TextInputAction.search,
    decoration: InputDecoration(
      isDense: true,
      hintText: StorageStrings.searchHint,
      prefixIcon: AppIcon(
        AppIcons.search,
        size: AppIconSize.md,
        color: p.textTertiary,
      ),
    ),
  );

  Widget _filters(BuildContext context, AppPalette p) {
    final sortLabel = switch (_c.sort) {
      StorageSort.newest => StorageStrings.newest,
      StorageSort.largest => StorageStrings.largest,
      StorageSort.name => StorageStrings.name,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: StorageSizes.chipHeight,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final k in <FileKind?>[null, ...FileKind.values]) ...[
                StorageChip(
                  label: kindLabel(k),
                  active: _c.kind == k,
                  onTap: () {
                    Haptics.tap();
                    _c.setKind(k);
                  },
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Align(
          alignment: Alignment.centerRight,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            onTap: () {
              Haptics.tap();
              final all = StorageSort.values;
              _c.setSort(all[(all.indexOf(_c.sort) + 1) % all.length]);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              child: IconLabel(
                icon: StorageIcons.sort,
                text: '${StorageStrings.sort}: $sortLabel',
                style: context.text.caption,
                color: p.textSecondary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _content(BuildContext context, AppPalette p) {
    if (_c.files.isEmpty) return const [];
    final visual = _c.files
        .where((f) => f.kind == FileKind.image || f.kind == FileKind.video)
        .toList();
    final rows = _c.files
        .where((f) => f.kind == FileKind.document || f.kind == FileKind.audio)
        .toList();
    const pad = EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding);
    return [
      if (visual.isNotEmpty)
        SliverPadding(
          padding: pad,
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: StorageSizes.gridColumns,
              mainAxisSpacing: StorageSizes.gridGap,
              crossAxisSpacing: StorageSizes.gridGap,
            ),
            itemCount: visual.length,
            itemBuilder: (context, i) {
              final f = visual[i];
              return StorageGridTile(
                key: ValueKey(f.id),
                file: f,
                selecting: _c.selecting,
                selected: _c.selected.contains(f.id),
                onTap: () => _onTap(f),
                onLongPress: () => _onLongPress(f),
              );
            },
          ),
        ),
      if (visual.isNotEmpty && rows.isNotEmpty)
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
      if (rows.isNotEmpty)
        SliverPadding(
          padding: pad,
          sliver: SliverList.builder(
            itemCount: rows.length,
            itemBuilder: (context, i) {
              final f = rows[i];
              return StorageListRow(
                key: ValueKey(f.id),
                file: f,
                selecting: _c.selecting,
                selected: _c.selected.contains(f.id),
                onTap: () => _onTap(f),
                onLongPress: () => _onLongPress(f),
                onMore: () => showStorageActions(context, _c, f),
              );
            },
          ),
        ),
    ];
  }

  Widget _footer(BuildContext context, AppPalette p) {
    final t = context.text;
    if (_c.loading && _c.files.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.xxl),
        child: Center(child: StorageSpinner()),
      );
    }
    if (_c.error != null && _c.files.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          children: [
            Text(
              _c.error!,
              textAlign: TextAlign.center,
              style: t.label.copyWith(color: p.error),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: () {
                Haptics.tap();
                _c.reload();
              },
              child: Text(
                AppStrings.retry,
                style: t.label.copyWith(color: p.accent),
              ),
            ),
          ],
        ),
      );
    }
    if (_c.files.isEmpty) {
      final filtered = _c.kind != null || _c.query.trim().isNotEmpty;
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          children: [
            AppIcon(
              StorageIcons.empty,
              size: AppIconSize.empty,
              color: p.textTertiary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              filtered ? StorageStrings.noMatch : StorageStrings.empty,
              style: t.label,
            ),
            if (!filtered) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                StorageStrings.emptyHint,
                textAlign: TextAlign.center,
                style: t.caption,
              ),
            ],
          ],
        ),
      );
    }
    if (_c.loadingMore) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Center(child: StorageSpinner()),
      );
    }
    if (_c.hasMore) {
      return Center(
        child: TextButton(
          onPressed: () {
            Haptics.tap();
            _c.loadMore();
          },
          child: Text(StorageStrings.loadMore, style: t.label),
        ),
      );
    }
    return const SizedBox(height: AppSpacing.lg);
  }
}
