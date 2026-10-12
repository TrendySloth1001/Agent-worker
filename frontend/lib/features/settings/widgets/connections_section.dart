import 'package:flutter/material.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/constants/connections.dart';
import '../../../core/constants/settings_copy.dart';
import '../../github/github_screen.dart';
import '../../connections/connections_controller.dart';
import 'settings_kit.dart';

/// Short status line for the GitHub connection, shared by the row and the
/// category summary.
String githubSummary(ConnectionsController c) {
  final g = c.github;
  if (g != null) return ConnectStrings.account(g.login);
  return switch (c.githubPhase) {
    GithubPhase.loading => SettingsStrings.connect,
    GithubPhase.waiting || GithubPhase.browser => SettingsStrings.waiting,
    GithubPhase.notConfigured when !c.isOwner => SettingsStrings.unavailable,
    _ => SettingsStrings.connect,
  };
}

/// GitHub row: opens the connect sheet; refreshes the link state on show.
class GithubConnectionTile extends StatefulWidget {
  const GithubConnectionTile({super.key});

  @override
  State<GithubConnectionTile> createState() => _GithubConnectionTileState();
}

class _GithubConnectionTileState extends State<GithubConnectionTile> {
  final _c = ConnectionsController.instance;

  @override
  void initState() {
    super.initState();
    _c.refresh();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _c,
    builder: (context, _) => SettingsTile(
      icon: ConnectIcons.github,
      title: ConnectStrings.github,
      summary: githubSummary(_c),
      onTap: () => Navigator.push(
        context,
        settingsRoute(const GithubScreen()),
      ),
    ),
  );
}

/// Google Drive / Photos placeholder row.
class SoonTile extends StatelessWidget {
  const SoonTile({super.key, required this.icon, required this.title});

  final AppIconData icon;
  final String title;

  @override
  Widget build(BuildContext context) => SettingsTile(
    icon: icon,
    title: title,
    summary: SettingsStrings.soon,
    titleColor: Theme.of(context).colorScheme.onSurfaceVariant,
  );
}
