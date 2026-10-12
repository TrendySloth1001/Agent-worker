import 'package:flutter/material.dart';

import '../../core/constants/app_icons.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/constants/app_strings.dart';
import '../../core/constants/storage.dart';
import '../../core/haptics.dart';
import '../../core/theme/app_palette.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/m3_kit_extras.dart';
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
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        final selecting = _c.selecting;
        final n = _c.selected.length;
        return PopScope(
          canPop: !selecting,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _c.clearSelection();
          },
          child: M3Page(
            title: StorageStrings.title,
            controller: _scroll,
            onRefresh: _c.reload,
            contextual: selecting,
            leading: selecting
                ? IconButton(
                    icon: const AppIcon(AppIcons.close, size: AppIconSize.lg),
                    tooltip: StorageStrings.clearSelection,
                    onPressed: () {
                      Haptics.tap();
                      _c.clearSelection();
                    },
                  )
                : null,
            titleWidget: selecting ? Text(StorageStrings.selected(n)) : null,
            actions: selecting ? _selectionActions(n) : _actions(),
            slivers: [
              M3Body(
                children: [
                  Builder(
                    builder: (context) =>
                        StorageHero(usage: _c.usage, loading: _c.loading),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Builder(builder: _searchField),
                  const SizedBox(height: AppSpacing.md),
                  Builder(builder: _filters),
                ],
              ),
              ..._content(),
              SliverToBoxAdapter(child: Builder(builder: _footer)),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _actions() => [
    Builder(
      builder: (context) => IconButton(
        icon: const AppIcon(StorageIcons.select, size: AppIconSize.md),
        tooltip: StorageStrings.select,
        onPressed: _c.files.isEmpty
            ? null
            : () {
                Haptics.tap();
                _c.startSelecting();
              },
      ),
    ),
  ];

  List<Widget> _selectionActions(int n) => [
    IconButton(
      icon: const AppIcon(StorageIcons.select, size: AppIconSize.md),
      tooltip: StorageStrings.selectAll,
      onPressed: () {
        Haptics.tap();
        _c.selectAll();
      },
    ),
    Builder(
      builder: (context) => IconButton(
        icon: AppIcon(
          StorageIcons.delete,
          size: AppIconSize.md,
          color: n == 0 ? context.palette.disabled : context.palette.accent,
        ),
        tooltip: StorageStrings.delete,
        onPressed: n == 0
            ? null
            : () => confirmStorageDelete(context, _c, _c.selected.toList()),
      ),
    ),
  ];

  Widget _searchField(BuildContext context) => SearchBar(
    controller: _search,
    onChanged: _c.setQuery,
    hintText: StorageStrings.searchHint,
    textInputAction: TextInputAction.search,
    leading: AppIcon(
      AppIcons.search,
      size: AppIconSize.md,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );

  Widget _filters(BuildContext context) {
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
        const SizedBox(height: AppSpacing.xs),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () {
              Haptics.tap();
              final all = StorageSort.values;
              _c.setSort(all[(all.indexOf(_c.sort) + 1) % all.length]);
            },
            icon: const AppIcon(StorageIcons.sort, size: AppIconSize.sm),
            label: Text('${StorageStrings.sort}: $sortLabel'),
          ),
        ),
      ],
    );
  }

  List<Widget> _content() {
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
              final selected = _c.selected.contains(f.id);
              return M3Cell(
                key: ValueKey(f.id),
                index: i,
                count: rows.length,
                selected: selected,
                child: StorageListRow(
                  file: f,
                  selecting: _c.selecting,
                  selected: selected,
                  onTap: () => _onTap(f),
                  onLongPress: () => _onLongPress(f),
                  onMore: () => showStorageActions(context, _c, f),
                ),
              );
            },
          ),
        ),
    ];
  }

  Widget _footer(BuildContext context) {
    final p = context.palette;
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
              style: Theme.of(
                context,
              ).textTheme.bodyMedium!.copyWith(color: p.error),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: () {
                Haptics.tap();
                _c.reload();
              },
              child: const Text(AppStrings.retry),
            ),
          ],
        ),
      );
    }
    if (_c.files.isEmpty) {
      final filtered = _c.kind != null || _c.query.trim().isNotEmpty;
      return M3Empty(
        icon: StorageIcons.empty,
        title: filtered ? StorageStrings.noMatch : StorageStrings.empty,
        hint: filtered ? null : StorageStrings.emptyHint,
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
          child: const Text(StorageStrings.loadMore),
        ),
      );
    }
    return const SizedBox(height: AppSpacing.lg);
  }
}
