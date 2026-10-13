import 'package:flutter/material.dart';

import '../../../core/constants/settings_copy.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../data/usage.dart';
import '../usage_controller.dart';
import 'settings_kit.dart';

/// Plain-language connection status for everyone. Draws nothing while sparky
/// is reachable; when it is not, one row says so and offers a retry. The
/// technical details (URL, database, providers) stay in the owner's
/// Developer section.
class ConnectionNotice extends StatelessWidget {
  const ConnectionNotice({super.key, required this.usage, this.leading});

  final UsageController usage;

  /// Space above the notice, only drawn when the notice shows.
  final Widget? leading;

  /// True when the last health check found a problem.
  static bool hasProblem(HealthStatus? h) => h != null && !(h.online && h.ok);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: usage,
      builder: (context, _) {
        final h = usage.health;
        if (!hasProblem(h)) return const SizedBox.shrink();
        final offline = !h!.online;
        final accent = context.palette.accent;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ?leading,
            SettingsGroup(
              entries: [
                GroupEntry(
                  SettingsTile(
                    icon: SettingsIcons.unreachable,
                    iconColor: accent,
                    title: offline
                        ? SettingsStrings.unreachableTitle
                        : SettingsStrings.troubleTitle,
                    summary: offline
                        ? SettingsStrings.unreachableHelp
                        : SettingsStrings.troubleHelp,
                    trailing: TextButton(
                      onPressed: usage.loading
                          ? null
                          : () {
                              Haptics.tap();
                              usage.refresh();
                            },
                      child: const Text(SettingsStrings.tryAgain),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
