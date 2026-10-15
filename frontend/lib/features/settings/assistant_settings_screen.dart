import 'package:flutter/material.dart';

import '../../assist/assistant_setup.dart';
import '../../core/app_scope.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/constants/assist.dart';
import '../../core/constants/settings_copy.dart';
import '../../core/haptics.dart';
import '../../core/theme/app_palette.dart';
import '../../core/widgets/app_icon.dart';
import 'settings_controller.dart';
import 'widgets/settings_kit.dart';

/// Settings > Assistant: is sparky the default digital assistant, how to
/// make it one, how to open it, and what it may read from the screen.
class AssistantSettingsScreen extends StatefulWidget {
  const AssistantSettingsScreen({
    super.key,
    this.setup = const AssistantSetup(),
    this.settings,
  });

  final AssistantSetup setup;

  /// The app's settings (actions and Live switches); defaults to [AppScope].
  final SettingsController? settings;

  static Future<void> open(BuildContext context) =>
      Navigator.push(context, settingsRoute(const AssistantSettingsScreen()));

  @override
  State<AssistantSettingsScreen> createState() =>
      _AssistantSettingsScreenState();
}

class _AssistantSettingsScreenState extends State<AssistantSettingsScreen>
    with WidgetsBindingObserver {
  AssistantStatus? _status;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Back from the system's Default apps page: show the new state.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final s = await widget.setup.status();
    if (mounted) setState(() => _status = s);
  }

  Future<void> _setDefault() async {
    final result = await widget.setup.request();
    if (result == AssistSetupChannel.granted) Haptics.received();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final s = _status;
    final settings =
        widget.settings ??
        context.dependOnInheritedWidgetOfExactType<AppScope>()?.settings;
    return SettingsScaffold(
      title: AssistStrings.catTitle,
      onRefresh: _refresh,
      children: [
        const SizedBox(height: SettingsSizes.groupSpacing),
        SettingsGroup(
          entries: [
            GroupEntry(
              _StatusCard(
                status: s,
                onSetDefault: _setDefault,
                onTry: widget.setup.tryIt,
              ),
            ),
          ],
        ),
        const SettingsGroupHeader(AssistStrings.secHow),
        SettingsGroup(
          entries: [
            if (s?.isNothing ?? false)
              const GroupEntry(
                SettingsTile(
                  icon: AssistIcons.nothing,
                  title: AssistStrings.howNothingTitle,
                  summary: AssistStrings.howNothingBody,
                ),
              ),
            if (!(s?.isNothing ?? false))
              const GroupEntry(
                SettingsTile(
                  icon: AssistIcons.power,
                  title: AssistStrings.howPowerTitle,
                  summary: AssistStrings.howPowerBody,
                ),
              ),
            const GroupEntry(
              SettingsTile(
                icon: AssistIcons.gesture,
                title: AssistStrings.howGestureTitle,
                summary: AssistStrings.howGestureBody,
              ),
            ),
          ],
        ),
        if (settings != null) ...[
          const SettingsGroupHeader(AssistStrings.secDo),
          ListenableBuilder(
            listenable: settings,
            builder: (context, _) => SettingsGroup(
              entries: [
                GroupEntry(
                  SettingsSwitchTile(
                    icon: AssistIcons.actions,
                    title: AssistStrings.actionsTitle,
                    summary: AssistStrings.actionsBody,
                    value: settings.assistActions,
                    onChanged: settings.setAssistActions,
                  ),
                ),
                GroupEntry(
                  SettingsSwitchTile(
                    icon: AssistIcons.liveVoice,
                    title: AssistStrings.liveTitle,
                    summary: AssistStrings.liveBody,
                    value: settings.assistLive,
                    onChanged: settings.setAssistLive,
                  ),
                ),
                GroupEntry(
                  SettingsSwitchTile(
                    icon: AssistIcons.history,
                    title: AssistStrings.saveTitle,
                    summary: AssistStrings.saveBody,
                    value: settings.assistSaveHistory,
                    onChanged: settings.setAssistSaveHistory,
                  ),
                ),
                GroupEntry(
                  SettingsSwitchTile(
                    icon: AssistIcons.openSound,
                    title: AssistStrings.soundTitle,
                    summary: AssistStrings.soundBody,
                    value: settings.assistOpenSound,
                    onChanged: settings.setAssistOpenSound,
                  ),
                ),
              ],
            ),
          ),
        ],
        const SettingsGroupHeader(AssistStrings.secMore),
        const SettingsGroup(
          entries: [
            GroupEntry(
              SettingsTile(
                icon: AssistIcons.circle,
                title: AssistStrings.circleTitle,
                summary: AssistStrings.circleBody,
              ),
            ),
            GroupEntry(
              SettingsTile(
                icon: AssistIcons.tile,
                title: AssistStrings.tileTitle,
                summary: AssistStrings.tileBody,
              ),
            ),
            GroupEntry(
              SettingsTile(
                icon: AssistIcons.shareTo,
                title: AssistStrings.shareTitle,
                summary: AssistStrings.shareBody,
              ),
            ),
            GroupEntry(
              SettingsTile(
                icon: AssistIcons.shortcuts,
                title: AssistStrings.shortcutsTitle,
                summary: AssistStrings.shortcutsBody,
              ),
            ),
          ],
        ),
        const SettingsGroupHeader(AssistStrings.secScreen),
        SettingsGroup(
          entries: [
            GroupEntry(
              SettingsTile(
                icon: AssistIcons.screenText,
                title: AssistStrings.screenTextTitle,
                summary: _flag(s?.screenText),
              ),
            ),
            GroupEntry(
              SettingsTile(
                icon: AssistIcons.screenshot,
                title: AssistStrings.screenshotTitle,
                summary: _flag(s?.screenshot),
              ),
            ),
            GroupEntry(
              SettingsTile(
                icon: AssistIcons.settings,
                title: AssistStrings.openAssistantSettings,
                summary: AssistStrings.setDefaultHelp,
                onTap: widget.setup.openSettings,
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            SettingsSizes.headerInset,
            AppSpacing.md,
            SettingsSizes.headerInset,
            0,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppIcon(
                AssistIcons.privacy,
                size: AppIconSize.sm,
                color: context.palette.textTertiary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  AssistStrings.screenPrivacy,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _flag(bool? on) => switch (on) {
    true => AssistStrings.screenOn,
    false => AssistStrings.screenOff,
    null => AssistStrings.screenUnknown,
  };
}

/// Big status at the top: on (accent) or off, with the main action.
class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.status,
    required this.onSetDefault,
    required this.onTry,
  });

  final AssistantStatus? status;
  final VoidCallback onSetDefault, onTry;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final on = status?.isDefault ?? false;
    final loading = status == null;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: SettingsSizes.iconCircle,
                height: SettingsSizes.iconCircle,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: on ? p.accent : scheme.surfaceContainerHighest,
                ),
                child: Center(
                  child: AppIcon(
                    AssistIcons.assistant,
                    size: SettingsSizes.iconGlyph,
                    color: on ? p.textInverse : scheme.onSurface,
                  ),
                ),
              ),
              const Spacer(),
              SettingsMetaLabel(
                loading
                    ? AssistStrings.metaChecking
                    : on
                    ? AssistStrings.metaOn
                    : AssistStrings.metaOff,
                accent: on,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            loading
                ? AssistStrings.statusUnknown
                : on
                ? AssistStrings.statusOnTitle
                : AssistStrings.statusOffTitle,
            style: text.titleLarge,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            on ? AssistStrings.statusOnBody : AssistStrings.statusOffBody,
            style: text.bodyMedium?.copyWith(color: p.textSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              if (on)
                OutlinedButton(
                  onPressed: () {
                    Haptics.tap();
                    onSetDefault();
                  },
                  child: const Text(AssistStrings.changeDefault),
                )
              else
                FilledButton(
                  onPressed: loading
                      ? null
                      : () {
                          Haptics.tap();
                          onSetDefault();
                        },
                  child: const Text(AssistStrings.setDefault),
                ),
              OutlinedButton(
                onPressed: () {
                  Haptics.tap();
                  onTry();
                },
                child: const Text(AssistStrings.tryIt),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
