import 'package:flutter/material.dart';

import '../../../core/app_scope.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/settings_copy.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../settings_controller.dart';
import 'settings_kit.dart';

/// Text size ids in slider order.
const textSizeIds = ['small', 'normal', 'large', 'huge'];

const textSizeLabels = {
  'small': SettingsStrings.textSmall,
  'normal': SettingsStrings.textNormal,
  'large': SettingsStrings.textLarge,
  'huge': SettingsStrings.textHuge,
};

String themeLabel(ThemeMode m) => switch (m) {
  ThemeMode.system => SettingsStrings.themeSystem,
  ThemeMode.light => SettingsStrings.themeLight,
  ThemeMode.dark => SettingsStrings.themeDark,
};

/// Theme as an M3 segmented button in the regular font.
class ThemeTile extends StatelessWidget {
  const ThemeTile({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).settings;
    // Const instances are never rebuilt by the page, so listen here.
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => _body(context, s),
    );
  }

  Widget _body(BuildContext context, SettingsController s) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const SettingsIconCircle(SettingsIcons.theme),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Text(SettingsStrings.themeLabel, style: tt.titleMedium),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SegmentedButton<ThemeMode>(
            showSelectedIcon: false,
            segments: [
              for (final m in ThemeMode.values)
                ButtonSegment(value: m, label: Text(themeLabel(m))),
            ],
            selected: {s.themeMode},
            onSelectionChanged: (v) {
              Haptics.tap();
              s.setThemeMode(v.first);
            },
          ),
        ],
      ),
    );
  }
}

/// Android "Font size": a stepped slider with a live preview. The scale is
/// saved when the thumb is released.
class TextSizeTile extends StatefulWidget {
  const TextSizeTile({super.key});

  @override
  State<TextSizeTile> createState() => _TextSizeTileState();
}

class _TextSizeTileState extends State<TextSizeTile> {
  /// Slider index while dragging; null follows the saved setting.
  int? _drag;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).settings;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => _body(context, s),
    );
  }

  Widget _body(BuildContext context, SettingsController s) {
    final tt = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final saved = textSizeIds.indexOf(s.textScale);
    final index = _drag ?? (saved < 0 ? 1 : saved);
    final id = textSizeIds[index];
    // The whole app is already scaled by the saved factor; the preview only
    // applies the difference so it moves live while dragging.
    final media = MediaQuery.of(context);
    final relative = (SettingsSizes.textScales[id] ?? 1) / s.textScaleFactor;
    final preview = media.copyWith(
      textScaler: TextScaler.linear(media.textScaler.scale(1) * relative),
    );
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const SettingsIconCircle(SettingsIcons.textSize),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Text(
                  SettingsStrings.textSizeTitle,
                  style: tt.titleMedium,
                ),
              ),
              Text(
                textSizeLabels[id]!,
                style: tt.labelLarge!.copyWith(color: context.palette.accent),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          MediaQuery(
            data: preview,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: Text(SettingsStrings.textPreview, style: tt.bodyLarge),
            ),
          ),
          Row(
            children: [
              Text('A', style: tt.bodySmall),
              Expanded(
                child: Semantics(
                  label: SettingsStrings.textSizeTitle,
                  value: textSizeLabels[id],
                  child: Slider(
                    value: index.toDouble(),
                    min: 0,
                    max: (textSizeIds.length - 1).toDouble(),
                    divisions: textSizeIds.length - 1,
                    label: textSizeLabels[id],
                    onChanged: (v) {
                      final next = v.round();
                      if (next != _drag) Haptics.tap();
                      setState(() => _drag = next);
                    },
                    onChangeEnd: (v) {
                      s.setTextScale(textSizeIds[v.round()]);
                      setState(() => _drag = null);
                    },
                  ),
                ),
              ),
              Text('A', style: tt.headlineSmall),
            ],
          ),
          Text(
            SettingsStrings.textSizeHelp,
            style: tt.bodyMedium!.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
