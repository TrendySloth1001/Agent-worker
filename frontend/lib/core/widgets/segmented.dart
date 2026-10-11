import 'package:flutter/material.dart';

import '../constants/app_icons.dart';
import '../constants/app_sizes.dart';
import '../haptics.dart';
import '../theme/app_palette.dart';
import 'icon_label.dart';

/// Flat segmented control: thin border, selected segment inverted.
class Segmented<T> extends StatelessWidget {
  const Segmented({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.icons = const {},
  });

  final T value;

  /// Value to label, in display order.
  final List<(T, String)> options;

  /// Optional icon per value, shown before the label.
  final Map<T, AppIconData> icons;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      height: AppSizes.segmentHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: p.borderStrong, width: AppBorder.thin),
      ),
      child: Row(
        children: [
          for (final (v, label) in options)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (v == value) return;
                  Haptics.tap();
                  onChanged(v);
                },
                child: AnimatedContainer(
                  duration: AppDurations.fast,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    color: v == value ? p.textPrimary : Colors.transparent,
                  ),
                  child: icons[v] == null
                      ? Text(
                          label,
                          style: context.text.caption.copyWith(
                            color: v == value ? p.textInverse : p.textSecondary,
                          ),
                        )
                      : IconLabel(
                          icon: icons[v]!,
                          text: label,
                          style: context.text.caption,
                          color: v == value ? p.textInverse : p.textSecondary,
                        ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
