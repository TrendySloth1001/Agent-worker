import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../knowledge_controller.dart';
import 'source_tile.dart';
import '../../../core/constants/app_icons.dart';
import '../../../core/constants/m3_copy.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/m3_kit_extras.dart';

Future<void> showAddSourceSheet(
  BuildContext context,
  KnowledgeController controller,
) => showM3Sheet<void>(
  context,
  builder: (_) => _AddSourceSheet(controller: controller),
);

/// Best guess of the source type from what was pasted; null if unclear.
String? detectSourceType(String raw) {
  final input = raw.trim();
  if (input.isEmpty) return null;
  final lower = input.toLowerCase();
  if (lower.startsWith('r/') || lower.contains('reddit.com')) return 'reddit';
  if (lower.contains('news.ycombinator.com')) return 'hackernews';
  if (lower.contains('stackoverflow.com') ||
      lower.contains('stackexchange.com')) {
    return 'stackoverflow';
  }
  if (lower.contains('github.com')) return 'github';
  if (RegExp(r'^[\w.-]+/[\w.-]+$').hasMatch(input) && !input.contains('.com')) {
    return 'github';
  }
  if (lower.startsWith('http://') || lower.startsWith('https://')) return 'web';
  return null;
}

class _AddSourceSheet extends StatefulWidget {
  const _AddSourceSheet({required this.controller});

  final KnowledgeController controller;

  @override
  State<_AddSourceSheet> createState() => _AddSourceSheetState();
}

class _AddSourceSheetState extends State<_AddSourceSheet> {
  static const _types = [
    ('web', KnowledgeCopy.kindWeb),
    ('github', KnowledgeCopy.kindGithub),
    ('stackoverflow', KnowledgeCopy.kindStack),
    ('reddit', KnowledgeCopy.kindReddit),
    ('hackernews', KnowledgeCopy.kindHn),
  ];

  final _input = TextEditingController();

  /// Null means detect from the input.
  String? _override;
  int _limit = AppSizes.kbLimitDefault;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy) return;
    Haptics.send();
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.controller.add(
      text,
      type: _override ?? 'auto',
      limit: _limit,
    );
    if (!mounted) return;
    if (error == null) {
      Navigator.pop(context);
    } else {
      Haptics.error();
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }

  void _step(int delta) {
    final next = (_limit + delta).clamp(
      AppSizes.kbLimitStep,
      AppSizes.kbLimitMax,
    );
    if (next == _limit) return;
    Haptics.tap();
    setState(() => _limit = next);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tt = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final muted = tt.labelLarge!.copyWith(color: scheme.onSurfaceVariant);
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            0,
            AppSpacing.xl,
            AppSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(KnowledgeCopy.addSource, style: tt.titleLarge),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _input,
                autofocus: true,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() => _error = null),
                onSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  hintText: AppStrings.addSourceHint,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Text(KnowledgeCopy.kind, style: muted),
                  const SizedBox(width: AppSpacing.md),
                  if (_override == null)
                    Flexible(
                      child: Text(
                        detectSourceType(_input.text) == null
                            ? KnowledgeCopy.auto
                            : '${KnowledgeCopy.auto} · '
                                  '${kindLabel(detectSourceType(_input.text)!)}',
                        style: tt.labelLarge!.copyWith(color: p.accent),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  _Pill(
                    label: KnowledgeCopy.auto,
                    icon: AppIcons.sourceAuto,
                    selected: _override == null,
                    onTap: () => setState(() => _override = null),
                  ),
                  for (final (id, label) in _types)
                    _Pill(
                      label: label,
                      icon: AppIcons.sourceKind(id),
                      selected: _override == id,
                      onTap: () => setState(() => _override = id),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Text(KnowledgeCopy.limit, style: muted),
                  const Spacer(),
                  IconButton.filledTonal(
                    tooltip: '-${AppSizes.kbLimitStep}',
                    icon: const AppIcon(AppIcons.remove, size: AppIconSize.sm),
                    onPressed: () => _step(-AppSizes.kbLimitStep),
                  ),
                  SizedBox(
                    width: AppSizes.rowHeight,
                    child: Text(
                      '$_limit',
                      textAlign: TextAlign.center,
                      style: tt.titleMedium,
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: '+${AppSizes.kbLimitStep}',
                    icon: const AppIcon(AppIcons.add, size: AppIconSize.sm),
                    onPressed: () => _step(AppSizes.kbLimitStep),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(_error!, style: tt.bodySmall!.copyWith(color: p.accent)),
              ],
              const SizedBox(height: AppSpacing.lg),
              ListenableBuilder(
                listenable: _input,
                builder: (context, _) => FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: p.accent,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _input.text.trim().isEmpty || _busy
                      ? null
                      : _submit,
                  child: Text(_busy ? KnowledgeCopy.adding : KnowledgeCopy.add),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final AppIconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fg = selected
        ? p.textInverse
        : Theme.of(context).colorScheme.onSurface;
    return FilterChip(
      label: Text(label),
      avatar: AppIcon(icon, size: AppIconSize.sm, color: fg),
      selected: selected,
      showCheckmark: false,
      shape: const StadiumBorder(),
      side: BorderSide(color: selected ? Colors.transparent : p.borderStrong),
      backgroundColor: Colors.transparent,
      selectedColor: p.textPrimary,
      labelStyle: Theme.of(context).textTheme.labelLarge!.copyWith(color: fg),
      onSelected: (_) {
        if (selected) return;
        Haptics.tap();
        onTap();
      },
    );
  }
}
