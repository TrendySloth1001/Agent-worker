import 'package:flutter/material.dart';

import '../../core/constants/app_icons.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/constants/app_strings.dart';
import '../../core/constants/memory.dart';
import '../../core/haptics.dart';
import '../../core/theme/app_palette.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/m3_kit_extras.dart';
import '../../data/memory_api.dart';
import '../settings/widgets/settings_kit.dart';
import '../storage/storage_actions.dart';
import '../storage/widgets/storage_tiles.dart';
import 'memory_controller.dart';

/// What the assistant remembers about the user: switch, search, add, edit,
/// pin, delete and clear all.
class MemoryScreen extends StatefulWidget {
  const MemoryScreen({super.key, this.controller});

  /// Test seam; defaults to a controller on the real API.
  final MemoryController? controller;

  static Future<void> open(BuildContext context) {
    Haptics.tap();
    return Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const MemoryScreen()));
  }

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> {
  late final _c = widget.controller ?? MemoryController();
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _c.reload();
  }

  @override
  void dispose() {
    _c.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<String?> _ask(String title, String confirm, String initial) async {
    final text = await showM3Sheet<String>(
      context,
      builder: (_) =>
          _MemoryEditSheet(title: title, confirm: confirm, initial: initial),
    );
    return text == null || text.length < 2 ? null : text;
  }

  Future<void> _add() async {
    final text = await _ask(MemoryStrings.addTitle, MemoryStrings.add, '');
    if (text == null || !mounted) return;
    final ok = await _c.add(text);
    if (mounted && !ok) {
      storageNotice(context, MemoryStrings.saveFailed, error: true);
    }
  }

  Future<void> _edit(MemoryItem m) async {
    final text = await _ask(MemoryStrings.editTitle, AppStrings.save, m.text);
    if (text == null || text == m.text || !mounted) return;
    final ok = await _c.edit(m, text);
    if (mounted && !ok) {
      storageNotice(context, MemoryStrings.saveFailed, error: true);
    }
  }

  Future<void> _toggle(bool value) async {
    final ok = await _c.setEnabled(value);
    if (mounted && !ok) {
      storageNotice(context, MemoryStrings.saveFailed, error: true);
    }
  }

  Future<void> _toggleRecall(bool value) async {
    final ok = await _c.setChatRecall(value);
    if (mounted && !ok) {
      storageNotice(context, MemoryStrings.saveFailed, error: true);
    }
  }

  Future<void> _delete(MemoryItem m) async {
    Haptics.tap();
    final ok = await _c.delete(m);
    if (!mounted) return;
    storageNotice(
      context,
      ok ? MemoryStrings.deleted : MemoryStrings.deleteFailed,
      error: !ok,
    );
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => StorageDialog(
        title: MemoryStrings.clearTitle,
        confirm: MemoryStrings.clearAll,
        destructive: true,
        onConfirm: () => Navigator.pop(dialog, true),
        child: Text(MemoryStrings.clearBody, style: dialog.text.bodySmall),
      ),
    );
    if (ok != true || !mounted) return;
    final done = await _c.clearAll();
    if (!mounted) return;
    storageNotice(
      context,
      done ? MemoryStrings.cleared : MemoryStrings.deleteFailed,
      error: !done,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) => M3Page(
        title: MemoryStrings.title,
        onRefresh: _c.reload,
        actions: [_clearAction()],
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () {
            Haptics.tap();
            _add();
          },
          icon: const AppIcon(MemoryIcons.add, size: AppIconSize.md),
          label: const Text(MemoryStrings.add),
        ),
        slivers: [
          M3Body(
            children: [
              SettingsGroup(
                entries: [
                  GroupEntry(
                    SettingsSwitchTile(
                      icon: MemoryIcons.section,
                      title: MemoryStrings.toggle,
                      summary: MemoryStrings.toggleHint,
                      value: _c.enabled,
                      onChanged: _toggle,
                    ),
                  ),
                  GroupEntry(
                    SettingsSwitchTile(
                      icon: AppIcons.chat,
                      title: MemoryStrings.recallToggle,
                      summary: MemoryStrings.recallHint,
                      value: _c.chatRecall,
                      onChanged: _toggleRecall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Builder(
                builder: (context) => SearchBar(
                  controller: _search,
                  onChanged: _c.setQuery,
                  hintText: MemoryStrings.searchHint,
                  textInputAction: TextInputAction.search,
                  leading: AppIcon(
                    AppIcons.search,
                    size: AppIconSize.md,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (_c.items.isNotEmpty) ...[
                SettingsGroupHeader(MemoryStrings.count(_c.total)),
                SettingsGroup(
                  entries: [
                    for (final m in _c.items)
                      GroupEntry(
                        _MemoryRow(
                          key: ValueKey(m.id),
                          item: m,
                          onEdit: () {
                            Haptics.tap();
                            _edit(m);
                          },
                          onPin: () {
                            Haptics.tap();
                            _c.togglePin(m);
                          },
                          onDelete: () => _delete(m),
                        ),
                      ),
                  ],
                ),
              ],
              Builder(builder: _footer),
            ],
          ),
        ],
      ),
    );
  }

  Widget _clearAction() => Builder(
    builder: (context) => IconButton(
      icon: AppIcon(
        MemoryIcons.delete,
        size: AppIconSize.md,
        color: _c.total == 0
            ? context.palette.disabled
            : Theme.of(context).colorScheme.onSurface,
      ),
      tooltip: MemoryStrings.clearAll,
      onPressed: _c.total == 0
          ? null
          : () {
              Haptics.tap();
              _clear();
            },
    ),
  );

  Widget _footer(BuildContext context) {
    final p = context.palette;
    if (_c.items.isNotEmpty) return const SizedBox.shrink();
    if (_c.loading) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.xxl),
        child: Center(child: StorageSpinner()),
      );
    }
    if (_c.error != null) {
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
    final searching = _c.query.trim().isNotEmpty;
    return M3Empty(
      icon: MemoryIcons.empty,
      title: searching
          ? MemoryStrings.noMatch
          : _c.enabled
          ? MemoryStrings.empty
          : MemoryStrings.emptyOff,
      hint: searching
          ? null
          : _c.enabled
          ? MemoryStrings.emptyHint
          : MemoryStrings.emptyOffHint,
    );
  }
}

/// Add / edit form in a modal bottom sheet.
class _MemoryEditSheet extends StatefulWidget {
  const _MemoryEditSheet({
    required this.title,
    required this.confirm,
    required this.initial,
  });

  final String title, confirm, initial;

  @override
  State<_MemoryEditSheet> createState() => _MemoryEditSheetState();
}

class _MemoryEditSheetState extends State<_MemoryEditSheet> {
  late final _field = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              M3SheetTitle(widget.title),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                child: TextField(
                  controller: _field,
                  autofocus: true,
                  minLines: 2,
                  maxLines: MemorySizes.textLines,
                  maxLength: MemorySizes.maxTextLength,
                  decoration: const InputDecoration(
                    hintText: MemoryStrings.addHint,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.sm,
                  AppSpacing.xl,
                  AppSpacing.lg,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () {
                        Haptics.tap();
                        Navigator.pop(context);
                      },
                      child: const Text(AppStrings.cancel),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    FilledButton(
                      onPressed: () {
                        Haptics.tap();
                        Navigator.pop(context, _field.text.trim());
                      },
                      child: Text(widget.confirm),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MemoryRow extends StatelessWidget {
  const _MemoryRow({
    super.key,
    required this.item,
    required this.onEdit,
    required this.onPin,
    required this.onDelete,
  });

  final MemoryItem item;
  final VoidCallback onEdit, onPin, onDelete;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final scheme = Theme.of(context).colorScheme;
    return Dismissible(
      key: ValueKey('dismiss-${item.id}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete(),
      background: Container(
        color: scheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.xl),
        child: AppIcon(
          MemoryIcons.delete,
          size: AppIconSize.md,
          color: p.error,
        ),
      ),
      child: ListTile(
        onTap: onEdit,
        title: Text(item.text),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              M3Tag(MemoryStrings.kind(item.kind)),
              if (item.pinned) const M3Tag(MemoryStrings.pinned, accent: true),
            ],
          ),
        ),
        trailing: IconButton(
          tooltip: item.pinned ? MemoryStrings.unpin : MemoryStrings.pin,
          onPressed: onPin,
          icon: AppIcon(
            item.pinned ? MemoryIcons.unpin : MemoryIcons.pin,
            size: AppIconSize.sm,
            color: item.pinned ? p.accent : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
