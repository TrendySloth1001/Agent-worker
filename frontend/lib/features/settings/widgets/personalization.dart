import 'package:flutter/material.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/settings_copy.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../data/assist_api.dart';
import '../../../data/chat_api.dart';
import 'settings_kit.dart';

/// Tone ids to display labels.
const toneLabels = {
  'friendly': SettingsStrings.toneFriendly,
  'professional': SettingsStrings.toneProfessional,
  'casual': SettingsStrings.toneCasual,
  'direct': SettingsStrings.toneDirect,
  'enthusiastic': SettingsStrings.toneEnthusiastic,
};

/// Length ids to display labels.
const lengthLabels = {
  'concise': SettingsStrings.lengthConcise,
  'balanced': SettingsStrings.lengthBalanced,
  'detailed': SettingsStrings.lengthDetailed,
};

/// A text profile field as a settings row: the current value is the
/// supporting text, tapping opens the editor sheet.
class ProfileFieldTile extends StatelessWidget {
  const ProfileFieldTile({
    super.key,
    required this.label,
    required this.icon,
    required this.value,
    required this.hint,
    required this.max,
    required this.onSave,
    this.multiline = false,
    this.aiField,
  });

  final String label, value, hint;
  final AppIconData icon;
  final int max;
  final bool multiline;

  /// Set for fields the AI can tidy up (see [ProfileAiStrings]).
  final String? aiField;
  final ValueChanged<String> onSave;

  @override
  Widget build(BuildContext context) {
    final oneLine = value.replaceAll(RegExp(r'\s+'), ' ');
    return ListTile(
      leading: SettingsIconCircle(icon),
      title: Text(label),
      subtitle: Text(
        value.isEmpty ? SettingsStrings.sumNotSet : oneLine,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () {
        Haptics.tap();
        _showEditor(context);
      },
    );
  }

  void _showEditor(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _EditorSheet(
        title: label,
        hint: hint,
        initial: value,
        max: max,
        multiline: multiline,
        aiField: aiField,
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
    this.aiField,
  });

  final String title, hint, initial;
  final int max;
  final bool multiline;
  final String? aiField;
  final ValueChanged<String> onSave;

  @override
  State<_EditorSheet> createState() => _EditorSheetState();
}

class _EditorSheetState extends State<_EditorSheet> {
  late final _input = TextEditingController(text: widget.initial)
    ..addListener(_onChanged);
  bool _formatting = false;

  /// Text before the last AI format, for UNDO.
  String? _before;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  bool get _canFormat =>
      widget.aiField != null &&
      _input.text.trim().length >= ProfileAiSizes.minChars;

  void _onChanged() => setState(() {});

  Future<void> _format() async {
    Haptics.tap();
    final before = _input.text;
    setState(() => _formatting = true);
    try {
      final text = await AssistApi.formatProfile(
        field: widget.aiField!,
        text: before.trim(),
        max: widget.max,
      );
      if (!mounted) return;
      if (text.trim().isNotEmpty) {
        _before = before;
        _input.text = text;
        Haptics.received();
      }
    } on ApiException {
      Haptics.error();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text(ProfileAiStrings.failed)));
      }
    } finally {
      if (mounted) setState(() => _formatting = false);
    }
  }

  void _undo() {
    Haptics.tap();
    final before = _before;
    if (before == null) return;
    _before = null;
    _input.text = before;
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
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.screenPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.title, style: tt.titleLarge),
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
              if (_canFormat || _before != null || _formatting) ...[
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    if (_before != null && !_formatting)
                      _AiChip(
                        icon: AppIcons.undo,
                        label: ProfileAiStrings.undo,
                        onTap: _undo,
                      ),
                    const Spacer(),
                    _AiChip(
                      icon: AppIcons.aiFormat,
                      label: _formatting
                          ? ProfileAiStrings.formatting
                          : ProfileAiStrings.format,
                      busy: _formatting,
                      onTap: _formatting || !_canFormat ? null : _format,
                    ),
                  ],
                ),
              ],
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

/// M3 assist chip used for FORMAT WITH AI and UNDO.
class _AiChip extends StatelessWidget {
  const _AiChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.busy = false,
  });

  final AppIconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = onTap == null && !busy
        ? scheme.onSurfaceVariant
        : scheme.onSurface;
    return ActionChip(
      onPressed: onTap,
      avatar: busy
          ? SizedBox.square(
              dimension: AppIconSize.sm,
              child: CircularProgressIndicator(
                strokeWidth: AppBorder.thick,
                color: context.palette.accent,
              ),
            )
          : AppIcon(icon, size: AppIconSize.md, color: color),
      label: Text(label),
      side: BorderSide(color: busy ? context.palette.accent : scheme.outline),
    );
  }
}
