import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/app_icons.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/constants/app_strings.dart';
import '../../core/constants/memory.dart';
import '../../core/haptics.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/system_chrome.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/toggle_row.dart';
import '../../data/memory_api.dart';
import '../storage/storage_actions.dart';
import '../storage/widgets/storage_tiles.dart';
import 'memory_controller.dart';

/// What the assistant remembers about the user: switch, search, add, edit,
/// pin, delete and clear all.
class MemoryScreen extends StatefulWidget {
  const MemoryScreen({super.key});

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
  final _c = MemoryController();
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
    final field = TextEditingController(text: initial);
    final text = await showDialog<String>(
      context: context,
      builder: (dialog) => StorageDialog(
        title: title,
        confirm: confirm,
        onConfirm: () => Navigator.pop(dialog, field.text.trim()),
        child: TextField(
          controller: field,
          autofocus: true,
          minLines: 2,
          maxLines: MemorySizes.textLines,
          maxLength: MemorySizes.maxTextLength,
          style: dialog.text.body,
          decoration: const InputDecoration(hintText: MemoryStrings.addHint),
        ),
      ),
    );
    field.dispose();
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
    final p = context.palette;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: systemOverlayFor(context),
      child: ListenableBuilder(
        listenable: _c,
        builder: (context, _) => Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const AppIcon(AppIcons.back, size: AppIconSize.md),
              tooltip: AppStrings.back,
              onPressed: () {
                Haptics.tap();
                Navigator.pop(context);
              },
            ),
            title: const Text(MemoryStrings.title),
            actions: [
              IconButton(
                icon: const AppIcon(MemoryIcons.add, size: AppIconSize.md),
                tooltip: MemoryStrings.add,
                onPressed: () {
                  Haptics.tap();
                  _add();
                },
              ),
              IconButton(
                icon: AppIcon(
                  MemoryIcons.delete,
                  size: AppIconSize.md,
                  color: _c.total == 0 ? p.disabled : p.accent,
                ),
                tooltip: MemoryStrings.clearAll,
                onPressed: _c.total == 0
                    ? null
                    : () {
                        Haptics.tap();
                        _clear();
                      },
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(AppBorder.thin),
              child: Divider(color: p.border),
            ),
          ),
          body: RefreshIndicator(
            color: p.accent,
            backgroundColor: p.surface,
            onRefresh: _c.reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                AppSpacing.screenPadding,
                AppSpacing.sm,
                AppSpacing.screenPadding,
                MediaQuery.paddingOf(context).bottom + AppSpacing.xl,
              ),
              children: [
                ToggleRow(
                  label: MemoryStrings.toggle,
                  icon: MemoryIcons.section,
                  value: _c.enabled,
                  onChanged: _toggle,
                ),
                Text(MemoryStrings.toggleHint, style: context.text.caption),
                const SizedBox(height: AppSpacing.md),
                ToggleRow(
                  label: MemoryStrings.recallToggle,
                  icon: AppIcons.chat,
                  value: _c.chatRecall,
                  onChanged: _toggleRecall,
                ),
                Text(MemoryStrings.recallHint, style: context.text.caption),
                const SizedBox(height: AppSpacing.lg),
                TextField(
                  controller: _search,
                  onChanged: _c.setQuery,
                  style: context.text.body,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: MemoryStrings.searchHint,
                    prefixIcon: AppIcon(
                      AppIcons.search,
                      size: AppIconSize.md,
                      color: p.textTertiary,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                if (_c.items.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: Text(
                      MemoryStrings.count(_c.total),
                      style: context.text.caption,
                    ),
                  ),
                for (final m in _c.items)
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
                _footer(context, p),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _footer(BuildContext context, AppPalette p) {
    final t = context.text;
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
              style: t.label.copyWith(color: p.error),
            ),
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
    final searching = _c.query.trim().isNotEmpty;
    final title = searching
        ? MemoryStrings.noMatch
        : _c.enabled
        ? MemoryStrings.empty
        : MemoryStrings.emptyOff;
    final hint = searching
        ? null
        : _c.enabled
        ? MemoryStrings.emptyHint
        : MemoryStrings.emptyOffHint;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        children: [
          AppIcon(
            MemoryIcons.empty,
            size: AppIconSize.empty,
            color: p.textTertiary,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(title, style: t.label),
          if (hint != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(hint, textAlign: TextAlign.center, style: t.caption),
          ],
        ],
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
    final t = context.text;
    return InkWell(
      onTap: onEdit,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: p.border)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.pinned
                        ? '${MemoryStrings.kind(item.kind)}'
                              '${MemoryStrings.separator}${MemoryStrings.pinned}'
                        : MemoryStrings.kind(item.kind),
                    style: t.caption.copyWith(
                      color: item.pinned ? p.accent : p.textTertiary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(item.text, style: t.body),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            InkResponse(
              onTap: onPin,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xs),
                child: AppIcon(
                  item.pinned ? MemoryIcons.unpin : MemoryIcons.pin,
                  size: AppIconSize.sm,
                  color: item.pinned ? p.accent : p.textSecondary,
                ),
              ),
            ),
            InkResponse(
              onTap: onDelete,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xs),
                child: AppIcon(
                  MemoryIcons.delete,
                  size: AppIconSize.sm,
                  color: p.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
