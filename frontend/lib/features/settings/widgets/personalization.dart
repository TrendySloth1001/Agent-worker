import 'package:flutter/material.dart';

import '../../../core/app_scope.dart';
import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/icon_label.dart';
import '../../../core/widgets/segmented.dart';
import '../settings_controller.dart';

/// Rows for the PERSONALIZATION section of Settings.
class PersonalizationRows extends StatelessWidget {
  const PersonalizationRows({super.key});

  static const _toneLabels = {
    'friendly': AppStrings.toneFriendly,
    'professional': AppStrings.toneProfessional,
    'casual': AppStrings.toneCasual,
    'direct': AppStrings.toneDirect,
    'enthusiastic': AppStrings.toneEnthusiastic,
  };

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FieldRow(
          label: AppStrings.profileName,
          icon: AppIcons.profileName,
          value: s.name,
          hint: AppStrings.nameHint,
          max: AppSizes.profileNameMax,
          onSave: s.setName,
        ),
        _FieldRow(
          label: AppStrings.profileRole,
          icon: AppIcons.profileRole,
          value: s.role,
          hint: AppStrings.roleHint,
          max: AppSizes.profileRoleMax,
          onSave: s.setRole,
        ),
        _FieldRow(
          label: AppStrings.profileAbout,
          icon: AppIcons.profileAbout,
          value: s.about,
          hint: AppStrings.aboutHint,
          max: AppSizes.profileAboutMax,
          multiline: true,
          onSave: s.setAbout,
        ),
        _FieldRow(
          label: AppStrings.profileLanguage,
          icon: AppIcons.profileLanguage,
          value: s.language,
          hint: AppStrings.languageHint,
          max: AppSizes.profileLanguageMax,
          onSave: s.setLanguage,
        ),
        _FieldRow(
          label: AppStrings.profileInstructions,
          icon: AppIcons.profileInstructions,
          value: s.customInstructions,
          hint: AppStrings.instructionsHint,
          max: AppSizes.profileInstructionsMax,
          multiline: true,
          onSave: s.setCustomInstructions,
        ),
        _FieldRow(
          label: AppStrings.profileSignature,
          icon: AppIcons.profileSignature,
          value: s.signature,
          hint: AppStrings.signatureHint,
          max: AppSizes.profileSignatureMax,
          multiline: true,
          onSave: s.setSignature,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(AppStrings.profileTone, style: context.text.label),
        const SizedBox(height: AppSpacing.sm),
        _toneChips(context, s),
        const SizedBox(height: AppSpacing.lg),
        Text(AppStrings.profileLength, style: context.text.label),
        const SizedBox(height: AppSpacing.sm),
        Segmented<String>(
          value: s.length,
          onChanged: s.setLength,
          icons: const {
            'concise': AppIcons.lengthConcise,
            'balanced': AppIcons.lengthBalanced,
            'detailed': AppIcons.lengthDetailed,
          },
          options: const [
            ('concise', AppStrings.lengthConcise),
            ('balanced', AppStrings.lengthBalanced),
            ('detailed', AppStrings.lengthDetailed),
          ],
        ),
      ],
    );
  }

  /// Tapping the selected tone again clears it.
  Widget _toneChips(BuildContext context, SettingsController s) {
    final p = context.palette;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final id in SettingsController.tones)
          GestureDetector(
            onTap: () {
              Haptics.tap();
              s.setTone(s.tone == id ? '' : id);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                color: s.tone == id ? p.textPrimary : Colors.transparent,
                border: Border.all(
                  color: s.tone == id ? p.textPrimary : p.borderStrong,
                  width: AppBorder.thin,
                ),
              ),
              child: IconLabel(
                icon: AppIcons.tone(id),
                text: _toneLabels[id]!,
                style: context.text.caption,
                color: s.tone == id ? p.textInverse : p.textSecondary,
              ),
            ),
          ),
      ],
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.label,
    required this.icon,
    required this.value,
    required this.hint,
    required this.max,
    required this.onSave,
    this.multiline = false,
  });

  final String label, value, hint;
  final AppIconData icon;
  final int max;
  final bool multiline;
  final ValueChanged<String> onSave;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final empty = value.isEmpty;
    final oneLine = value.replaceAll(RegExp(r'\s+'), ' ');
    return InkWell(
      onTap: () {
        Haptics.tap();
        _showEditor(context);
      },
      child: SizedBox(
        height: AppSizes.sourceRowHeight,
        child: Row(
          children: [
            AppIcon(icon, size: AppIconSize.xs, color: p.textSecondary),
            const SizedBox(width: AppSpacing.sm),
            Text(label, style: t.label),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Text(
                empty ? AppStrings.notSet : oneLine,
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.caption.copyWith(
                  color: empty ? p.textTertiary : p.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            AppIcon(
              AppIcons.chevronRight,
              size: AppIconSize.xs,
              color: p.textTertiary,
            ),
          ],
        ),
      ),
    );
  }

  void _showEditor(BuildContext context) {
    final p = context.palette;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.surface,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius.lg),
        ),
        side: BorderSide(color: p.border),
      ),
      builder: (_) => _EditorSheet(
        title: label,
        hint: hint,
        initial: value,
        max: max,
        multiline: multiline,
        onSave: onSave,
      ),
    );
  }
}

class _EditorSheet extends StatefulWidget {
  const _EditorSheet({
    required this.title,
    required this.hint,
    required this.initial,
    required this.max,
    required this.multiline,
    required this.onSave,
  });

  final String title, hint, initial;
  final int max;
  final bool multiline;
  final ValueChanged<String> onSave;

  @override
  State<_EditorSheet> createState() => _EditorSheetState();
}

class _EditorSheetState extends State<_EditorSheet> {
  late final _input = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _save(String value) {
    Haptics.tap();
    widget.onSave(value);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.screenPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.title, style: t.label),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _input,
                autofocus: true,
                style: t.body,
                maxLength: widget.max,
                minLines: widget.multiline ? AppSizes.profileEditorLines : 1,
                maxLines: widget.multiline ? AppSizes.profileEditorLines : 1,
                keyboardType: widget.multiline
                    ? TextInputType.multiline
                    : TextInputType.text,
                textInputAction: widget.multiline
                    ? TextInputAction.newline
                    : TextInputAction.done,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: widget.multiline ? null : _save,
                buildCounter:
                    (
                      _, {
                      required currentLength,
                      required isFocused,
                      maxLength,
                    }) => Text(
                      '$currentLength / $maxLength',
                      style: t.caption.copyWith(
                        color: currentLength >= (maxLength ?? 0)
                            ? p.accent
                            : p.textTertiary,
                      ),
                    ),
                decoration: InputDecoration(hintText: widget.hint),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  TextButton(
                    onPressed: () => _save(''),
                    child: const Text(AppStrings.clear),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _save(_input.text),
                      child: const Text(AppStrings.save),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
