import 'package:flutter/widgets.dart';

import '../constants/app_icons.dart';
import '../constants/app_sizes.dart';
import 'app_icon.dart';

/// Small icon followed by text, both in [color]. Text truncates.
class IconLabel extends StatelessWidget {
  const IconLabel({
    super.key,
    required this.icon,
    required this.text,
    required this.style,
    this.color,
    this.iconSize = AppIconSize.xs,
    this.expand = false,
  });

  final AppIconData icon;
  final String text;
  final TextStyle style;
  final Color? color;
  final double iconSize;

  /// Fill the available width instead of hugging the content.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: color == null ? style : style.copyWith(color: color),
    );
    return Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      children: [
        AppIcon(icon, size: iconSize, color: color ?? style.color),
        const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
        expand ? Expanded(child: label) : Flexible(child: label),
      ],
    );
  }
}
