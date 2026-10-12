import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/constants/app_icons.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/constants/settings_copy.dart';
import '../../core/haptics.dart';
import '../../core/theme/app_palette.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/user_avatar.dart';
import '../auth/auth_controller.dart';
import '../connections/connections_controller.dart';
import '../profile/profile_screen.dart';
import 'settings_pages.dart';
import 'widgets/settings_kit.dart';

/// Settings root in the Android 16 style: a collapsing large title, a search
/// bar that finds items on every page, an account card and grouped category
/// entries with a one-line summary of their current values.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _started = false;
  final _search = SearchController();
  String _query = '';

  /// Category groups, in order.
  static const _groups = [
    [
      SettingsCategory.profile,
      SettingsCategory.replies,
      SettingsCategory.privacy,
      SettingsCategory.search,
    ],
    [
      SettingsCategory.apps,
      SettingsCategory.storage,
      SettingsCategory.notifications,
      SettingsCategory.appearance,
    ],
    [
      SettingsCategory.models,
      SettingsCategory.telemetry,
      SettingsCategory.server,
    ],
    [SettingsCategory.about],
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final usage = AppScope.of(context).usage;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      usage.refresh();
      ConnectionsController.instance.refresh();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _setQuery(String v) => setState(() => _query = v.trim());

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([
        scope.settings,
        scope.usage,
        AuthController.instance,
        ConnectionsController.instance,
      ]),
      builder: (context, _) => SettingsScaffold(
        title: SettingsStrings.title,
        onRefresh: scope.usage.refresh,
        children: [
          _SearchField(controller: _search, onChanged: _setQuery),
          if (_query.isEmpty) ..._home(context, scope) else ..._results(scope),
        ],
      ),
    );
  }

  List<Widget> _home(BuildContext context, AppScope scope) {
    final owner = isOwner();
    return [
      const SizedBox(height: SettingsSizes.groupSpacing),
      SettingsGroup(entries: [GroupEntry(_AccountCard())]),
      for (final group in _groups) ...[
        const SizedBox(height: SettingsSizes.groupSpacing),
        SettingsGroup(
          entries: [
            for (final c in group)
              if (!c.ownerOnly || owner)
                GroupEntry(_CategoryTile(category: c, scope: scope)),
          ],
        ),
      ],
      const SizedBox(height: SettingsSizes.groupSpacing),
      SettingsGroup(entries: [GroupEntry(_ResetTile(onTap: _confirmReset))]),
    ];
  }

  List<Widget> _results(AppScope scope) {
    final hits = searchSettings(_query, scope);
    final resetHit = SettingsStrings.resetKeywords.contains(
      _query.toLowerCase(),
    );
    if (hits.isEmpty && !resetHit) {
      return [const SettingsEmptyState(SettingsStrings.noResults)];
    }
    return [
      const SettingsGroupHeader(SettingsStrings.searchResults),
      SettingsGroup(
        entries: [
          for (final h in hits)
            GroupEntry(
              SettingsTile(
                icon: h.category.icon,
                title: h.title,
                summary: h.itemId == null ? null : h.category.title,
                onTap: () => openSettingsCategory(
                  context,
                  h.category,
                  focusId: h.itemId,
                ),
              ),
            ),
          if (resetHit) GroupEntry(_ResetTile(onTap: _confirmReset)),
        ],
      ),
    ];
  }

  Future<void> _confirmReset() async {
    Haptics.tap();
    final scope = AppScope.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: AppIcon(
          SettingsIcons.reset,
          size: AppIconSize.lg,
          color: Theme.of(ctx).colorScheme.error,
        ),
        title: const Text(SettingsStrings.resetConfirmTitle),
        content: const Text(SettingsStrings.resetConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(SettingsStrings.cancel),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(SettingsStrings.reset),
          ),
        ],
      ),
    );
    if (ok != true) return;
    scope.settings.resetToDefaults();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text(SettingsStrings.resetDone)));
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final SearchController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => SearchBar(
        controller: controller,
        hintText: SettingsStrings.searchHint,
        onChanged: onChanged,
        leading: const AppIcon(AppIcons.search, size: AppIconSize.lg),
        trailing: [
          if (controller.text.isNotEmpty)
            IconButton(
              tooltip: SettingsStrings.searchClear,
              icon: const AppIcon(AppIcons.close, size: AppIconSize.lg),
              onPressed: () {
                Haptics.tap();
                controller.clear();
                onChanged('');
              },
            ),
        ],
      ),
    );
  }
}

/// Avatar, name and email; opens Profile.
class _AccountCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final user = AuthController.instance.user;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      leading: UserAvatar(user: user, size: SettingsSizes.avatar),
      title: Text(user?.displayName ?? SettingsStrings.accountFallback),
      subtitle: Text(user?.email ?? SettingsStrings.accountHelp),
      onTap: () {
        Haptics.tap();
        Navigator.push(context, settingsRoute(const ProfileScreen()));
      },
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, required this.scope});

  final SettingsCategory category;
  final AppScope scope;

  @override
  Widget build(BuildContext context) {
    return SettingsTile(
      icon: category.icon,
      title: category.title,
      summary: categorySummary(category, scope),
      iconColor: category.ownerOnly ? context.palette.accent : null,
      onTap: () => openSettingsCategory(context, category),
    );
  }
}

/// Destructive action at the bottom, in the error colour.
class _ResetTile extends StatelessWidget {
  const _ResetTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return SettingsTile(
      icon: SettingsIcons.reset,
      title: SettingsStrings.reset,
      summary: SettingsStrings.resetHelp,
      iconColor: error,
      titleColor: error,
      onTap: onTap,
    );
  }
}
