import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../knowledge_controller.dart';
import 'source_tile.dart';
import '../../../core/constants/app_icons.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/icon_label.dart';

Future<void> showAddSourceSheet(
  BuildContext context,
  KnowledgeController controller,
) {
  final p = context.palette;
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: p.surface,
    shape: RoundedRectangleBorder(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppRadius.lg),
      ),
      side: BorderSide(color: p.border),
    ),
    builder: (_) => _AddSourceSheet(controller: controller),
  );
}

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
    ('web', AppStrings.kindWeb),
    ('github', AppStrings.kindGithub),
    ('stackoverflow', AppStrings.kindStack),
    ('reddit', AppStrings.kindReddit),
    ('hackernews', AppStrings.kindHn),
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
    final t = context.text;
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.screenPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(AppStrings.addSource, style: t.label),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _input,
                autofocus: true,
                style: t.body,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() => _error = null),
                onSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  hintText: AppStrings.addSourceHint,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Text(AppStrings.addSourceKind, style: t.caption),
                  const SizedBox(width: AppSpacing.md),
                  if (_override == null)
                    Text(
                      detectSourceType(_input.text) == null
                          ? AppStrings.kindAuto
                          : '${AppStrings.kindAuto} · '
                                '${kindLabel(detectSourceType(_input.text)!)}',
                      style: t.caption.copyWith(color: p.accent),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  _Pill(
                    label: AppStrings.kindAuto,
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
                  Text(AppStrings.addSourceLimit, style: t.caption),
                  const Spacer(),
                  _StepButton(
                    icon: AppIcons.remove,
                    onTap: () => _step(-AppSizes.kbLimitStep),
                  ),
                  SizedBox(
                    width: AppSizes.rowHeight,
                    child: Text(
                      '$_limit',
                      textAlign: TextAlign.center,
                      style: t.label,
                    ),
                  ),
                  _StepButton(
                    icon: AppIcons.add,
                    onTap: () => _step(AppSizes.kbLimitStep),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(_error!, style: t.caption.copyWith(color: p.accent)),
              ],
              const SizedBox(height: AppSpacing.lg),
              ListenableBuilder(
                listenable: _input,
                builder: (context, _) => FilledButton(
                  onPressed: _input.text.trim().isEmpty || _busy
                      ? null
                      : _submit,
                  child: Text(_busy ? AppStrings.adding : AppStrings.add),
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (selected) return;
        Haptics.tap();
        onTap();
      },
      child: AnimatedContainer(
        duration: AppDurations.fast,
        height: AppSizes.chipHeight + AppSpacing.xs,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.chipHorizontalPadding,
        ),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          color: selected ? p.textPrimary : Colors.transparent,
          border: Border.all(
            color: selected ? p.textPrimary : p.borderStrong,
            width: AppBorder.thin,
          ),
        ),
        child: IconLabel(
          icon: icon,
          text: label,
          style: context.text.caption,
          color: selected ? p.textInverse : p.textSecondary,
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final AppIconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: AppSizes.stepperButton,
        height: AppSizes.stepperButton,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: p.borderStrong, width: AppBorder.thin),
        ),
        child: AppIcon(icon, size: AppIconSize.sm, color: p.textPrimary),
      ),
    );
  }
}
