import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_fonts.dart';
import '../constants/app_sizes.dart';
import '../constants/app_strings.dart';
import '../haptics.dart';
import '../theme/app_palette.dart';
import '../../core/constants/app_icons.dart';
import 'app_icon.dart';
import 'm3_kit_extras.dart' show sentenceCase;

/// Tappable COPY label that flips to COPIED for a moment.
class CopyAction extends StatefulWidget {
  const CopyAction({super.key, required this.text, this.label});

  final String text;

  /// Overrides the idle label (default COPY).
  final String? label;

  @override
  State<CopyAction> createState() => _CopyActionState();
}

class _CopyActionState extends State<CopyAction> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    Haptics.tap();
    if (!mounted) return;
    setState(() => _copied = true);
    await Future.delayed(AppDurations.copiedFeedback);
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = _copied ? p.accent : p.textTertiary;
    return GestureDetector(
      onTap: _copy,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(
              _copied ? AppIcons.check : AppIcons.copy,
              size: AppIconSize.sm,
              color: color,
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              sentenceCase(
                _copied ? AppStrings.copied : (widget.label ?? AppStrings.copy),
              ),
              style: context.text.caption.copyWith(
                fontFamily: AppFonts.body,
                letterSpacing: 0,
                fontSize: AppFontSize.label,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
