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
import '../github/widgets/gh_rows.dart';
import '../settings/widgets/settings_kit.dart';
import 'connector_controllers.dart';
import 'notion_screen.dart';
import 'widgets/connector_kit.dart';

enum NotionFilter { all, pages, databases }

Widget notionRowIcon(NotionItem i) => ConnectorRowIcon(
  icon: i.isDatabase ? NotionIcons.database : NotionIcons.page,
  emoji: i.iconIsImage ? null : i.icon,
  imageUrl: i.iconIsImage ? i.icon : null,
);

void openNotionItem(BuildContext context, NotionItem i) {
  Haptics.tap();
  Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => NotionPageScreen(item: i)));
}

/// One page / database row.
class NotionItemTile extends StatelessWidget {
  const NotionItemTile({super.key, required this.item, this.now});

  final NotionItem item;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SettingsTile(
      icon: item.isDatabase ? NotionIcons.database : NotionIcons.page,
      leading: notionRowIcon(item),
      title: item.title.isEmpty ? NotionStrings.untitled : item.title,
      summary: item.lastEdited == null
          ? null
          : timeAgo(item.lastEdited!, now ?? DateTime.now()),
      trailing: item.isDatabase
          ? const M3Tag(NotionStrings.database)
          : AppIcon(
              AppIcons.chevronRight,
              size: AppIconSize.sm,
              color: scheme.onSurfaceVariant,
            ),
      onTap: () => openNotionItem(context, item),
    );
  }
}

/// "Your Notion pages": search over everything shared with sparky.
class NotionBrowseScreen extends StatefulWidget {
  const NotionBrowseScreen({super.key, required this.controller, this.now});

  final NotionController controller;
  final DateTime? now;

  @override
  State<NotionBrowseScreen> createState() => _NotionBrowseScreenState();
}

class _NotionBrowseScreenState extends State<NotionBrowseScreen> {
  late final TextEditingController _search = TextEditingController(
    text: widget.controller.query,
  );
  NotionFilter _filter = NotionFilter.all;

  NotionController get _c => widget.controller;

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

  static String _label(NotionFilter f) => switch (f) {
    NotionFilter.all => NotionStrings.filterAll,
    NotionFilter.pages => NotionStrings.filterPages,
    NotionFilter.databases => NotionStrings.filterDatabases,
  };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        final all = _c.items ?? const <NotionItem>[];
        final shown = [
          for (final i in all)
            if (_filter == NotionFilter.all ||
                (_filter == NotionFilter.databases) == i.isDatabase)
              i,
        ];
        final q = _c.query;
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
            icon: q.isEmpty ? NotionIcons.fallback : AppIcons.search,
            title: q.isNotEmpty
                ? NotionStrings.noMatches
                : all.isEmpty
                ? NotionStrings.noPages
                : NotionStrings.noFilterMatches,
            hint: q.isNotEmpty
                ? NotionStrings.noMatchesHint(q)
                : all.isEmpty
                ? NotionStrings.noPagesHint
                : null,
          );
        }
        return M3Page(
          title: NotionStrings.browseTitle,
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
                      hint: NotionStrings.search,
                      controller: _search,
                      onChanged: _c.setQuery,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        for (final f in NotionFilter.values) ...[
                          if (f != NotionFilter.all)
                            const SizedBox(width: AppSpacing.sm),
                          ChoiceChip(
                            label: Text(_label(f)),
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
                        NotionStrings.pageCount(
                          shown.length,
                          more: all.length >= ConnectorSizes.searchPage,
                        ),
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
                        child: NotionItemTile(item: shown[i], now: widget.now),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}
