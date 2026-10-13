import 'package:flutter/material.dart';

import '../../../core/app_scope.dart';
import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/model_logos.dart';
import '../../../core/constants/settings_copy.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/icon_label.dart';
import '../../../data/ai_model.dart';
import '../../auth/auth_controller.dart';
import '../format.dart';
import '../telemetry/telemetry_format.dart' show providerLabel;
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
        final owner = AuthController.instance.user?.isOwner ?? false;
        // People see a friendly name; only the owner sees the raw id.
        final name = owner
            ? s.modelChoice
            : s.modelChoiceName.isNotEmpty
            ? s.modelChoiceName
            : friendlyModelName(s.modelChoice);
        return SettingsTile(
          icon: raw
              ? ModelLogos.forModelId(s.modelChoice)
              : SettingsIcons.listModels,
          title: SettingsStrings.allModels,
          summary: raw ? name : SettingsStrings.allModelsHelp,
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
    final owner = AuthController.instance.user?.isOwner ?? false;
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
          final models = snap.data!;
          body = ListenableBuilder(
            listenable: s,
            builder: (context, child) => RadioGroup<String>(
              groupValue: s.modelChoice,
              onChanged: (v) {
                if (v == null) return;
                Haptics.tap();
                final pick = models.where((m) => m.id == v).firstOrNull;
                s.setModelChoice(
                  v,
                  name: pick == null ? '' : friendlyModelLabel(pick.name),
                );
                Navigator.pop(context);
              },
              child: child!,
            ),
            child: Column(
              children: [
                for (final m in models)
                  RadioListTile<String>(
                    value: m.id,
                    controlAffinity: ListTileControlAffinity.trailing,
                    secondary: SettingsIconCircle(
                      ModelLogos.forModelId(m.id, provider: m.provider),
                    ),
                    title: Text(owner ? m.name : friendlyModelLabel(m.name)),
                    // Provider names are a developer detail.
                    subtitle: !owner
                        ? null
                        : Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: IconLabel(
                              icon: AppIcons.provider(m.provider),
                              text: providerLabel(m.provider),
                              style: tt.bodyMedium!.copyWith(
                                color: p.textSecondary,
                              ),
                              iconSize: AppIconSize.sm,
                            ),
                          ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
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
