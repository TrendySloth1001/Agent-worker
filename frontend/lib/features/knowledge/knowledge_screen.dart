import '../../core/widgets/mascot.dart';
import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/constants/app_icons.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/constants/app_strings.dart';
import '../../core/constants/m3_copy.dart';
import '../../core/constants/settings_copy.dart';
import '../../core/haptics.dart';
import '../../core/theme/app_palette.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/m3_kit_extras.dart';
import '../../data/kb_source.dart';
import '../../data/knowledge_api.dart';
import '../settings/widgets/settings_kit.dart';
import 'knowledge_controller.dart';
import 'widgets/add_source_sheet.dart';
import 'widgets/source_tile.dart';

class KnowledgeScreen extends StatefulWidget {
  const KnowledgeScreen({super.key, this.controller, this.imageFor});

  /// Test seam; defaults to a controller on the app's API.
  final KnowledgeController? controller;

  /// Test seam for source icon images.
  final ImageProvider Function(String url)? imageFor;

  @override
  State<KnowledgeScreen> createState() => _KnowledgeScreenState();
}

class _KnowledgeScreenState extends State<KnowledgeScreen> {
  KnowledgeController? _controller;
  final _search = TextEditingController();
  String _query = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    _controller =
        widget.controller ??
        KnowledgeController(KnowledgeApi(AppScope.of(context).baseUrl));
    _controller!.load();
  }

  @override
  void dispose() {
    _search.dispose();
    _controller?.dispose();
    super.dispose();
  }

  Future<bool> _confirmDelete() async {
    Haptics.tap();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => M3Themed(
        child: Builder(
          builder: (context) => AlertDialog(
            title: const Text(KnowledgeCopy.deleteTitle),
            content: const Text(AppStrings.deleteSourceBody),
            actions: [
              TextButton(
                onPressed: () {
                  Haptics.tap();
                  Navigator.pop(context, false);
                },
                child: const Text(AppStrings.cancel),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: context.palette.accent,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  Haptics.tap();
                  Navigator.pop(context, true);
                },
                child: const Text(KnowledgeCopy.deleteSource),
              ),
            ],
          ),
        ),
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller!;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => M3Page(
        title: KnowledgeCopy.title,
        onRefresh: controller.load,
        floatingActionButton: controller.sources.isEmpty
            ? null
            : FloatingActionButton.extended(
                onPressed: () {
                  Haptics.tap();
                  showAddSourceSheet(context, controller);
                },
                icon: const AppIcon(AppIcons.add, size: AppIconSize.md),
                label: const Text(KnowledgeCopy.addSource),
              ),
        slivers: [M3Body(children: _body(controller))],
      ),
    );
  }

  List<Widget> _body(KnowledgeController controller) {
    if (controller.loading) return const [];
    if (controller.sources.isEmpty) {
      final failed = controller.loadError != null;
      return [
        Builder(
          builder: (context) {
            final p = context.palette;
            return Column(
              children: [
                const SizedBox(height: AppSpacing.xl),
                M3Empty(
                  icon: failed ? AppIcons.alert : AppIcons.sourceWeb,
                  mascot: failed ? MascotState.error : MascotState.searching,
                  title: failed
                      ? controller.loadError!
                      : KnowledgeCopy.emptyTitle,
                  hint: failed ? null : KnowledgeCopy.emptyHint,
                  action: failed
                      ? FilledButton.tonal(
                          onPressed: () {
                            Haptics.tap();
                            controller.load();
                          },
                          child: const Text(KnowledgeCopy.retry),
                        )
                      : FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: p.accent,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () {
                            Haptics.tap();
                            showAddSourceSheet(context, controller);
                          },
                          icon: const AppIcon(
                            AppIcons.add,
                            size: AppIconSize.md,
                          ),
                          label: const Text(KnowledgeCopy.addSource),
                        ),
                ),
              ],
            );
          },
        ),
      ];
    }
    final query = _query.trim().toLowerCase();
    final shown = [
      for (final s in controller.sources)
        if (query.isEmpty || _matches(s, query)) s,
    ];
    return [
      _SearchField(
        controller: _search,
        onChanged: (v) => setState(() => _query = v),
      ),
      if (shown.isEmpty)
        Builder(
          builder: (context) => Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xl),
            child: M3Empty(
              icon: AppIcons.search,
              title: KnowledgeCopy.noMatches,
              hint: KnowledgeCopy.noMatchesHint,
            ),
          ),
        ),
      for (final group in SourceGroup.values)
        ..._group(controller, group, [
          for (final s in shown)
            if (SourceGroup.of(s.type) == group) s,
        ]),
      if (shown.isNotEmpty)
        Builder(
          builder: (context) => Padding(
            padding: const EdgeInsets.all(SettingsSizes.headerInset),
            child: Text(
              KnowledgeCopy.swipeHint,
              style: Theme.of(context).textTheme.bodySmall!.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
    ];
  }

  bool _matches(KbSource s, String q) =>
      (s.title ?? '').toLowerCase().contains(q) ||
      s.uri.toLowerCase().contains(q) ||
      kindLabel(s.type).toLowerCase().contains(q);

  List<Widget> _group(
    KnowledgeController controller,
    SourceGroup group,
    List<KbSource> items,
  ) {
    if (items.isEmpty) return const [];
    return [
      SettingsGroupHeader(group.title),
      SettingsGroup(
        entries: [
          for (final source in items)
            GroupEntry(
              Dismissible(
                key: ValueKey(source.id),
                direction: DismissDirection.endToStart,
                confirmDismiss: (_) => _confirmDelete(),
                onDismissed: (_) => controller.delete(source.id),
                background: Builder(
                  builder: (context) => Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: AppSpacing.xl),
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: AppIcon(
                      AppIcons.delete,
                      size: AppIconSize.md,
                      color: context.palette.error,
                    ),
                  ),
                ),
                child: SourceTile(
                  source: source,
                  imageFor: widget.imageFor,
                  onRefresh: () {
                    Haptics.tap();
                    controller.refresh(source.id);
                  },
                  onDelete: () async {
                    if (await _confirmDelete()) controller.delete(source.id);
                  },
                ),
              ),
            ),
        ],
      ),
    ];
  }
}

/// Filled, pill shaped search field (M3 search bar look).
class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: SizedBox(
        height: KnowledgeSizes.searchHeight,
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: KnowledgeCopy.searchHint,
            filled: true,
            fillColor: scheme.surfaceContainerHigh,
            contentPadding: EdgeInsets.zero,
            prefixIcon: AppIcon(
              AppIcons.search,
              size: AppIconSize.md,
              color: scheme.onSurfaceVariant,
            ),
            suffixIcon: ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, v, _) => v.text.isEmpty
                  ? const SizedBox.shrink()
                  : IconButton(
                      tooltip: KnowledgeCopy.clearSearch,
                      icon: const AppIcon(AppIcons.close, size: AppIconSize.md),
                      onPressed: () {
                        Haptics.tap();
                        controller.clear();
                        onChanged('');
                      },
                    ),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              borderSide: BorderSide(
                color: context.palette.accent,
                width: AppBorder.thick,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
