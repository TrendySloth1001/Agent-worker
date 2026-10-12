import 'package:flutter/material.dart';

import '../../../core/app_scope.dart';
import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/settings_copy.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../data/ai_model.dart';

/// "Which AI answers": Auto / Fastest / Smartest, then the raw model list.
class ModelChoice extends StatelessWidget {
  const ModelChoice({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).settings;
    return Column(
      children: [
        _OptionRow(
          icon: SettingsIcons.modelAuto,
          title: SettingsStrings.modelAuto,
          help: SettingsStrings.modelAutoHelp,
          selected: s.modelChoice == 'auto',
          onTap: () => s.setModelChoice('auto'),
        ),
        _OptionRow(
          icon: SettingsIcons.modelFast,
          title: SettingsStrings.modelFast,
          help: SettingsStrings.modelFastHelp,
          selected: s.modelChoice == 'fast',
          onTap: () => s.setModelChoice('fast'),
        ),
        _OptionRow(
          icon: SettingsIcons.modelSmart,
          title: SettingsStrings.modelSmart,
          help: SettingsStrings.modelSmartHelp,
          selected: s.modelChoice == 'smart',
          onTap: () => s.setModelChoice('smart'),
        ),
        const _RawModels(),
      ],
    );
  }
}

class _RawModels extends StatefulWidget {
  const _RawModels();

  @override
  State<_RawModels> createState() => _RawModelsState();
}

class _RawModelsState extends State<_RawModels> {
  bool _open = false;
  Future<List<AiModel>>? _models;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final s = scope.settings;
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _OptionRow(
          icon: _open ? AppIcons.collapse : AppIcons.expand,
          title: SettingsStrings.allModels,
          help: SettingsStrings.allModelsHelp,
          selected: false,
          onTap: () => setState(() {
            _open = !_open;
            _models ??= scope.api.fetchModels();
          }),
        ),
        if (_open)
          FutureBuilder<List<AiModel>>(
            future: _models,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Text(
                    SettingsStrings.modelsLoading,
                    style: context.text.caption,
                  ),
                );
              }
              if (snap.hasError || snap.data == null) {
                return Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Text(
                    SettingsStrings.modelsFailed,
                    style: context.text.caption.copyWith(color: p.accent),
                  ),
                );
              }
              return Column(
                children: [
                  for (final m in snap.data!)
                    _OptionRow(
                      title: m.name,
                      help: m.provider.toUpperCase(),
                      selected: s.modelChoice == m.id,
                      onTap: () => s.setModelChoice(m.id),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.title,
    required this.help,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String title, help;
  final AppIconData? icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: () {
          Haptics.tap();
          onTap();
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: SettingsSizes.touchTarget,
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                AppIcon(
                  icon!,
                  size: AppIconSize.sm,
                  color: selected ? p.accent : p.textSecondary,
                ),
                const SizedBox(width: AppSpacing.md),
              ],
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: t.label.copyWith(
                          color: selected ? p.accent : null,
                        ),
                      ),
                      Text(help, style: t.caption),
                    ],
                  ),
                ),
              ),
              if (selected)
                AppIcon(AppIcons.check, size: AppIconSize.sm, color: p.accent),
            ],
          ),
        ),
      ),
    );
  }
}
