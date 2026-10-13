import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/settings_copy.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import 'settings_kit.dart';

/// Owner-only, collapsible group of developer details (server, usage numbers,
/// telemetry, build). Collapsed by default so it stays out of the way.
class DeveloperSection extends StatefulWidget {
  const DeveloperSection({
    super.key,
    required this.children,
    this.summary = SettingsStrings.developerHelp,
    this.initiallyExpanded = false,
  });

  /// Rows shown when expanded, each in its own group cell.
  final List<Widget> children;
  final String summary;
  final bool initiallyExpanded;

  @override
  State<DeveloperSection> createState() => _DeveloperSectionState();
}

class _DeveloperSectionState extends State<DeveloperSection> {
  late bool _open = widget.initiallyExpanded;

  void _toggle() {
    Haptics.tap();
    setState(() => _open = !_open);
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsGroupHeader(SettingsStrings.developer),
        SettingsGroup(
          entries: [
            GroupEntry(
              Semantics(
                expanded: _open,
                child: ListTile(
                  leading: SettingsIconCircle(
                    SettingsIcons.developer,
                    color: context.palette.accent,
                  ),
                  title: Text(
                    _open
                        ? SettingsStrings.developerHide
                        : SettingsStrings.developerShow,
                  ),
                  subtitle: Text(widget.summary),
                  trailing: AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: reduce ? Duration.zero : AppDurations.normal,
                    child: AppIcon(
                      SettingsIcons.expand,
                      size: AppIconSize.lg,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  onTap: _toggle,
                ),
              ),
            ),
            if (_open)
              for (final child in widget.children) GroupEntry(child),
          ],
        ),
      ],
    );
  }
}
