import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/telemetry.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/icon_label.dart';
import '../widgets/section_header.dart';
import 'telemetry_screen.dart';

/// Settings card that opens the owner-only telemetry screen. The caller
/// shows it only to the owner; the backend refuses everyone else anyway.
class TelemetryEntry extends StatelessWidget {
  const TelemetryEntry({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    return FlatCard(
      onTap: () {
        Haptics.tap();
        Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => const TelemetryScreen()),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: IconLabel(
                  icon: TelemetryIcons.live,
                  text: TelemetryStrings.entryTitle.toUpperCase(),
                  style: t.label,
                  iconSize: AppIconSize.sm,
                  expand: true,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              const MetaChip(TelemetryStrings.ownerOnly, emphasis: true),
              const SizedBox(width: AppSpacing.sm),
              AppIcon(
                TelemetryIcons.chevron,
                size: AppIconSize.xs,
                color: p.textTertiary,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(TelemetryStrings.entryBody, style: t.bodySmall),
        ],
      ),
    );
  }
}
