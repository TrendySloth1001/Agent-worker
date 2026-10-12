import 'package:flutter/material.dart';

import '../../../core/app_scope.dart';
import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/settings_copy.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import '../settings_controller.dart';
import 'settings_kit.dart';

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
    sample: '“A clear, thorough answer with all the details.”',
    icon: AppIcons.lengthDetailed,
    tone: '',
    length: 'detailed',
  ),
  ReplyPreset(
    id: 'friendly',
    title: 'Friendly',
    sample: '“Happy to help! Here is an easy way to get that done.”',
    icon: AppIcons.toneFriendly,
    tone: 'friendly',
    length: 'balanced',
  ),
  ReplyPreset(
    id: 'direct',
    title: 'Straight to the point',
    sample: '“Do this, then that. Done.”',
    icon: AppIcons.toneDirect,
    tone: 'direct',
    length: 'concise',
  ),
  ReplyPreset(
    id: 'teacher',
    title: 'Teacher',
    sample: '“Let us go step by step, and I will explain why.”',
    icon: SettingsIcons.presetTeacher,
    tone: 'friendly',
    length: 'detailed',
  ),
  ReplyPreset(
    id: 'professional',
    title: 'Professional',
    sample: '“Here is my recommendation, with the reasoning behind it.”',
    icon: AppIcons.toneProfessional,
    tone: 'professional',
    length: 'balanced',
  ),
  ReplyPreset(
    id: 'fun',
    title: 'Fun',
    sample: '“Ooh, good one! Let us dive right in.”',
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
    // Plain rows inside the group cell (no card inside a card): tonal icon
    // circle, title, sample, and a check on the active style.
    return Column(
      children: [
        for (final preset in replyPresets)
          _PresetRow(
            preset: preset,
            selected: preset == current,
            onTap: () {
              Haptics.tap();
              s.applyReplyStyle(preset.tone, preset.length);
            },
          ),
      ],
    );
  }
}

class _PresetRow extends StatelessWidget {
  const _PresetRow({
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
    return Semantics(
      button: true,
      selected: selected,
      label: preset.title,
      child: ListTile(
        onTap: onTap,
        selected: selected,
        selectedColor: scheme.onSurface,
        leading: SettingsIconCircle(
          preset.icon,
          color: selected ? p.accent : null,
        ),
        title: Text(preset.title),
        subtitle: Text(preset.sample),
        trailing: selected
            ? AppIcon(AppIcons.check, size: AppIconSize.lg, color: p.accent)
            : null,
      ),
    );
  }
}
