import 'package:flutter/material.dart';

import '../../../core/app_scope.dart';
import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/settings_copy.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import '../settings_controller.dart';

/// A reply style: shown as a card, stored as tone + length.
class ReplyPreset {
  const ReplyPreset({
    required this.id,
    required this.title,
    required this.sample,
    required this.icon,
    required this.tone,
    required this.length,
  });

  final String id, title, sample, tone, length;
  final AppIconData icon;
}

const replyPresets = [
  ReplyPreset(
    id: 'default',
    title: 'Default (recommended)',
    sample: '"A clear, thorough answer with all the details."',
    icon: AppIcons.lengthDetailed,
    tone: '',
    length: 'detailed',
  ),
  ReplyPreset(
    id: 'friendly',
    title: 'Friendly',
    sample: '"Happy to help! Here is an easy way to get that done."',
    icon: AppIcons.toneFriendly,
    tone: 'friendly',
    length: 'balanced',
  ),
  ReplyPreset(
    id: 'direct',
    title: 'Straight to the point',
    sample: '"Do this, then that. Done."',
    icon: AppIcons.toneDirect,
    tone: 'direct',
    length: 'concise',
  ),
  ReplyPreset(
    id: 'teacher',
    title: 'Teacher',
    sample: '"Let us go step by step, and I will explain why."',
    icon: SettingsIcons.presetTeacher,
    tone: 'friendly',
    length: 'detailed',
  ),
  ReplyPreset(
    id: 'professional',
    title: 'Professional',
    sample: '"Here is my recommendation, with the reasoning behind it."',
    icon: AppIcons.toneProfessional,
    tone: 'professional',
    length: 'balanced',
  ),
  ReplyPreset(
    id: 'fun',
    title: 'Fun',
    sample: '"Ooh, good one! Let us dive right in."',
    icon: SettingsIcons.presetFun,
    tone: 'enthusiastic',
    length: 'balanced',
  ),
];

/// The preset matching the current tone and length, if any.
ReplyPreset? presetFor(String tone, String length) =>
    replyPresets.where((p) => p.tone == tone && p.length == length).firstOrNull;

/// Selectable cards, one per reply style, each with a sample sentence.
class ReplyStyleCards extends StatelessWidget {
  const ReplyStyleCards({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).settings;
    // Const instances are never rebuilt by the page, so listen here.
    return ListenableBuilder(listenable: s, builder: (context, _) => _cards(s));
  }

  Widget _cards(SettingsController s) {
    final current = presetFor(s.tone, s.length);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        children: [
          for (var i = 0; i < replyPresets.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.sm),
            _PresetCard(
              preset: replyPresets[i],
              selected: replyPresets[i] == current,
              onTap: () {
                Haptics.tap();
                s.applyReplyStyle(replyPresets[i].tone, replyPresets[i].length);
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final ReplyPreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final scheme = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      side: BorderSide(
        color: selected ? p.accent : Colors.transparent,
        width: AppBorder.thick,
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      label: preset.title,
      child: Material(
        color: scheme.surfaceContainerHigh,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(
              minHeight: SettingsSizes.touchTarget,
            ),
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                AppIcon(
                  preset.icon,
                  size: AppIconSize.lg,
                  color: selected ? p.accent : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(preset.title, style: tt.titleMedium),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        preset.sample,
                        style: tt.bodyMedium!.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: AppSpacing.sm),
                  AppIcon(
                    AppIcons.check,
                    size: AppIconSize.lg,
                    color: p.accent,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
