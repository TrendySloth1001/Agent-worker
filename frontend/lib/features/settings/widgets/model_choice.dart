import 'package:flutter/material.dart';

import '../../../core/app_scope.dart';
import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/settings_copy.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../data/ai_model.dart';
import 'settings_kit.dart';

/// One of the Auto / Fastest / Smartest radio rows. Must sit under a
/// `RadioGroup<String>` bound to the model choice.
class ModelRadioTile extends StatelessWidget {
  const ModelRadioTile({
    super.key,
    required this.value,
    required this.icon,
    required this.title,
    required this.help,
  });

  final String value, title, help;
  final AppIconData icon;

  @override
  Widget build(BuildContext context) {
    return RadioListTile<String>(
      value: value,
      controlAffinity: ListTileControlAffinity.trailing,
      secondary: SettingsIconCircle(icon),
      title: Text(title),
      subtitle: Text(help),
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
    );
  }
}

/// Wraps the model rows so a pick saves the choice.
Widget modelChoiceGroup(BuildContext context, Widget child) {
  final s = AppScope.of(context).settings;
  return RadioGroup<String>(
    groupValue: s.modelChoice,
    onChanged: (v) {
      if (v == null) return;
      Haptics.tap();
      s.setModelChoice(v);
    },
    child: child,
  );
}

/// "Choose a specific model": the summary shows the pick, tapping opens a
/// bottom sheet with every model the server offers.
class SpecificModelTile extends StatelessWidget {
  const SpecificModelTile({super.key});

  static const _presets = {'auto', 'fast', 'smart'};

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).settings;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final raw = !_presets.contains(s.modelChoice);
        return SettingsTile(
          icon: SettingsIcons.listModels,
          title: SettingsStrings.allModels,
          summary: raw ? s.modelChoice : SettingsStrings.allModelsHelp,
          trailing: raw
              ? AppIcon(
                  AppIcons.check,
                  size: AppIconSize.lg,
                  color: context.palette.accent,
                )
              : null,
          onTap: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            builder: (_) => const _ModelSheet(),
          ),
        );
      },
    );
  }
}

class _ModelSheet extends StatefulWidget {
  const _ModelSheet();

  @override
  State<_ModelSheet> createState() => _ModelSheetState();
}

class _ModelSheetState extends State<_ModelSheet> {
  Future<List<AiModel>>? _models;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _models ??= AppScope.of(context).api.fetchModels();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).settings;
    final tt = Theme.of(context).textTheme;
    final p = context.palette;
    return FutureBuilder<List<AiModel>>(
      future: _models,
      builder: (context, snap) {
        final Widget body;
        if (snap.connectionState != ConnectionState.done) {
          body = Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Text(SettingsStrings.modelsLoading, style: tt.bodyMedium),
          );
        } else if (snap.hasError || snap.data == null) {
          body = Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Text(
              SettingsStrings.modelsFailed,
              style: tt.bodyMedium!.copyWith(color: p.accent),
            ),
          );
        } else {
          body = ListenableBuilder(
            listenable: s,
            builder: (context, child) => RadioGroup<String>(
              groupValue: s.modelChoice,
              onChanged: (v) {
                if (v == null) return;
                Haptics.tap();
                s.setModelChoice(v);
                Navigator.pop(context);
              },
              child: child!,
            ),
            child: Column(
              children: [
                for (final m in snap.data!)
                  RadioListTile<String>(
                    value: m.id,
                    title: Text(m.name),
                    subtitle: Text(m.provider),
                  ),
              ],
            ),
          );
        }
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    0,
                    AppSpacing.xl,
                    AppSpacing.sm,
                  ),
                  child: Text(SettingsStrings.allModels, style: tt.titleLarge),
                ),
                body,
              ],
            ),
          ),
        );
      },
    );
  }
}
