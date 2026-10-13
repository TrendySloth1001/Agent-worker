import 'package:flutter/material.dart';

import '../../core/constants/app_sizes.dart';
import '../../core/constants/update.dart';
import '../../core/theme/app_palette.dart';
import '../../core/update/update_controller.dart';
import '../../core/widgets/app_icon.dart';
import '../settings/widgets/settings_kit.dart';
import 'update_parts.dart';
import 'update_sheet.dart';

/// What the "App updates" row says under its title.
String updateStatusText(UpdateController c) {
  final latest = c.latest;
  switch (c.phase) {
    case UpdatePhase.downloading:
      return UpdateStrings.statusDownloading((c.progress * 100).round());
    case UpdatePhase.installing:
      return UpdateStrings.statusInstalling;
    case UpdatePhase.ready || UpdatePhase.needsPermission:
      if (latest != null) return UpdateStrings.statusReady(latest.version);
    case UpdatePhase.idle || UpdatePhase.failed:
      break;
  }
  if (c.checking) return UpdateStrings.statusChecking;
  if (latest != null) return UpdateStrings.statusAvailable(latest.version);
  return c.everChecked
      ? UpdateStrings.statusUpToDate
      : UpdateStrings.statusUnknown;
}

/// Settings → About → APP UPDATES: status (with a dot when there is an
/// update), "Check for updates" and the Wi-Fi-only switch.
class UpdateSettingsGroup extends StatelessWidget {
  const UpdateSettingsGroup({super.key, this.controller});

  final UpdateController? controller;

  @override
  Widget build(BuildContext context) {
    final c = controller ?? UpdateController.instance;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final p = context.palette;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SettingsGroupHeader(UpdateStrings.section),
            SettingsGroup(
              entries: [
                GroupEntry(
                  SettingsTile(
                    icon: UpdateIcons.update,
                    title: UpdateStrings.rowTitle,
                    summary: updateStatusText(c),
                    trailing: c.hasUpdate
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const UpdateDot(),
                              const SizedBox(width: AppSpacing.sm),
                              AppIcon(
                                UpdateIcons.chevron,
                                size: AppIconSize.xs,
                                color: p.textTertiary,
                              ),
                            ],
                          )
                        : null,
                    onTap: c.hasUpdate
                        ? () => UpdateSheet.show(context, controller: c)
                        : null,
                  ),
                ),
                GroupEntry(
                  SettingsTile(
                    icon: UpdateIcons.refresh,
                    title: UpdateStrings.check,
                    summary: UpdateStrings.checkHint,
                    trailing: c.checking
                        ? SizedBox(
                            width: UpdateSizes.spinner,
                            height: UpdateSizes.spinner,
                            child: CircularProgressIndicator(
                              strokeWidth: UpdateSizes.spinnerStroke,
                              color: p.accent,
                            ),
                          )
                        : null,
                    onTap: c.checking ? null : () => _check(context, c),
                  ),
                ),
                GroupEntry(
                  SettingsSwitchTile(
                    icon: UpdateIcons.wifi,
                    title: UpdateStrings.wifiOnly,
                    summary: UpdateStrings.wifiOnlyHint,
                    value: c.wifiOnly,
                    onChanged: c.setWifiOnly,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Future<void> _check(BuildContext context, UpdateController c) async {
    final result = await c.check();
    if (!context.mounted) return;
    if (result == UpdateCheck.failed) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text(UpdateStrings.checkFailed)),
        );
    } else if (result == UpdateCheck.available) {
      await UpdateSheet.show(context, controller: c);
    }
  }
}
