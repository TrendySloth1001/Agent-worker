import 'package:flutter/material.dart';

import '../../../core/theme/app_text_styles.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';

/// Mono caption followed by a hairline.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.icon});

  final String title;
  final AppIconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl, bottom: AppSpacing.md),
      child: Row(
        children: [
          if (icon != null) ...[
            AppIcon(
              icon!,
              size: AppIconSize.sm,
              color: context.palette.textSecondary,
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          // Group headers stay in mono caps, even where rows use body text.
          Text(
            title,
            style: AppTextStyles.caption.copyWith(
              color: context.palette.textTertiary,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Divider(color: context.palette.border)),
        ],
      ),
    );
  }
}

/// Lets a parent that already draws the card surface (a settings group cell)
/// ask [FlatCard]s below it to drop their own border and radius.
class CardChrome extends InheritedWidget {
  const CardChrome({super.key, required super.child});

  static bool flat(BuildContext context) =>
      context.getInheritedWidgetOfExactType<CardChrome>() != null;

  @override
  bool updateShouldNotify(CardChrome oldWidget) => false;
}

/// Bordered flat surface shared by every card on the screen. Inside a
/// [CardChrome] it is just padded content.
class FlatCard extends StatelessWidget {
  const FlatCard({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final flat = CardChrome.flat(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: flat
              ? null
              : BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: p.border, width: AppBorder.thin),
                ),
          child: child,
        ),
      ),
    );
  }
}

/// Small outlined tag, e.g. PER MODEL.
class MetaChip extends StatelessWidget {
  const MetaChip(this.label, {super.key, this.emphasis = false});

  final String label;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = emphasis ? p.accent : p.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(
          color: emphasis ? p.accent : p.borderStrong,
          width: AppBorder.thin,
        ),
      ),
      child: Text(label, style: context.text.caption.copyWith(color: color)),
    );
  }
}

/// Filled dot for healthy, ring for idle, accent for attention.
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.color, this.hollow = false});

  final Color color;
  final bool hollow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppSizes.statusDot,
      height: AppSizes.statusDot,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: hollow ? Colors.transparent : color,
        border: hollow
            ? Border.all(color: color, width: AppSizes.statusRing)
            : null,
      ),
    );
  }
}

/// Label on the left, value on the right; value truncates, never overflows.
class InfoRow extends StatelessWidget {
  const InfoRow(
    this.label,
    this.value, {
    super.key,
    this.valueColor,
    this.icon,
  });

  final String label, value;
  final AppIconData? icon;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            AppIcon(icon!, size: AppIconSize.xs, color: t.caption.color),
            const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
          ],
          Text(label, style: t.caption),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: t.caption.copyWith(
                color: valueColor ?? context.palette.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
