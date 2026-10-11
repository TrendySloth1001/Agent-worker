import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_scope.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/constants/app_strings.dart';
import '../../core/constants/connections.dart';
import '../../core/haptics.dart';
import '../../core/platform/browsers.dart';
import '../../core/widgets/browser_picker.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/system_chrome.dart';
import '../../core/widgets/segmented.dart';
import '../../core/widgets/toggle_row.dart';
import '../../data/usage.dart';
import '../knowledge/knowledge_screen.dart';
import 'settings_controller.dart';
import 'widgets/connections_section.dart';
import 'widgets/personalization.dart';
import 'widgets/provider_card.dart';
import 'widgets/section_header.dart';
import 'widgets/service_cards.dart';
import 'widgets/status_strip.dart';
import 'widgets/usage_states.dart';
import '../../core/constants/app_icons.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/icon_label.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    AppScope.of(context).usage.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final p = context.palette;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: systemOverlayFor(context),
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const AppIcon(AppIcons.back, size: AppIconSize.md),
            tooltip: AppStrings.back,
            onPressed: () {
              Haptics.tap();
              Navigator.pop(context);
            },
          ),
          title: const Text(AppStrings.settings),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(AppBorder.thin),
            child: Divider(color: p.border),
          ),
        ),
        body: ListenableBuilder(
          listenable: Listenable.merge([scope.settings, scope.usage]),
          builder: (context, _) => RefreshIndicator(
            color: p.accent,
            backgroundColor: p.surface,
            onRefresh: scope.usage.refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                AppSpacing.screenPadding,
                AppSpacing.sm,
                AppSpacing.screenPadding,
                MediaQuery.paddingOf(context).bottom + AppSpacing.xl,
              ),
              children: [
                ..._summary(scope),
                const SectionHeader(
                  AppStrings.modelsSection,
                  icon: AppIcons.models,
                ),
                ..._providers(scope),
                const SectionHeader(
                  AppStrings.dataToolsSection,
                  icon: AppIcons.dataTools,
                ),
                ..._services(context, scope),
                const SectionHeader(
                  ConnectStrings.section,
                  icon: ConnectIcons.connect,
                ),
                const ConnectionsSection(),
                const SectionHeader(
                  AppStrings.personalization,
                  icon: AppIcons.personalization,
                ),
                const PersonalizationRows(),
                const SectionHeader(
                  AppStrings.appearance,
                  icon: AppIcons.appearance,
                ),
                _themePicker(scope),
                const SectionHeader(AppStrings.chat, icon: AppIcons.chat),
                ToggleRow(
                  label: AppStrings.haptics,
                  icon: AppIcons.haptics,
                  value: scope.settings.hapticsOn,
                  onChanged: scope.settings.setHaptics,
                ),
                ToggleRow(
                  label: AppStrings.webSearchDefault,
                  icon: AppIcons.web,
                  value: scope.settings.defaultWebSearch,
                  onChanged: scope.settings.setDefaultWebSearch,
                ),
                ToggleRow(
                  label: AppStrings.knowledgeDefault,
                  icon: AppIcons.knowledge,
                  value: scope.settings.defaultKnowledge,
                  onChanged: scope.settings.setDefaultKnowledge,
                ),
                ToggleRow(
                  label: TableStrings.byDefault,
                  icon: AppIcons.roundTable,
                  value: scope.settings.defaultRoundTable,
                  onChanged: scope.settings.setDefaultRoundTable,
                ),
                ToggleRow(
                  label: TableWaitStrings.notifySetting,
                  icon: TableIcons.notify,
                  value: scope.settings.notifyRoundTable,
                  onChanged: scope.settings.setNotifyRoundTable,
                ),
                if (Browsers.supported) _browserRow(context, scope),
                const SizedBox(height: AppSpacing.sm),
                _modeChips(context, scope),
                const SectionHeader(AppStrings.about, icon: AppIcons.about),
                _aboutRows(context, scope),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _browserRow(BuildContext context, AppScope scope) {
    final p = context.palette;
    final label = scope.settings.browserLabel;
    return InkWell(
      onTap: () => showBrowserPicker(context, forSettings: true),
      child: SizedBox(
        height: AppSizes.rowHeight,
        child: Row(
          children: [
            AppIcon(
              AppIcons.browser,
              size: AppIconSize.sm,
              color: p.textSecondary,
            ),
            const SizedBox(width: AppSpacing.md),
            Text(BrowserStrings.rowLabel, style: context.text.label),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Text(
                label.isEmpty
                    ? BrowserStrings.systemDefault
                    : label.toUpperCase(),
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.caption.copyWith(
                  color: label.isEmpty ? p.textTertiary : p.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            AppIcon(
              AppIcons.chevronRight,
              size: AppIconSize.xs,
              color: p.textTertiary,
            ),
          ],
        ),
      ),
    );
  }

  /// Blank gap between stacked cards.
  static const _gap = SizedBox(height: AppSpacing.md);

  List<Widget> _summary(AppScope scope) {
    final c = scope.usage;
    final u = c.usage;
    if (u == null) {
      return [
        if (c.loading)
          const SkeletonCard(height: AppSizes.statusStripSkeletonHeight)
        else
          UsageError(onRetry: c.refresh, loading: c.loading),
      ];
    }
    return [
      if (c.offline) ...[
        UsageError(onRetry: c.refresh, stale: true, loading: c.loading),
        _gap,
      ],
      StatusStrip(usage: u, health: c.health),
    ];
  }

  List<Widget> _providers(AppScope scope) {
    final u = scope.usage.usage;
    if (u == null) {
      return [
        if (scope.usage.loading)
          for (var i = 0; i < AppSizes.skeletonCards; i++) ...[
            if (i > 0) _gap,
            const SkeletonCard(),
          ],
      ];
    }
    return [
      for (var i = 0; i < u.providers.length; i++) ...[
        if (i > 0) _gap,
        ProviderCard(
          key: ValueKey(u.providers[i].id),
          provider: u.providers[i],
        ),
      ],
    ];
  }

  List<Widget> _services(BuildContext context, AppScope scope) {
    final u = scope.usage.usage;
    if (u == null) {
      return [if (scope.usage.loading) const SkeletonCard()];
    }
    final cards = <Widget>[
      if (u.github != null) GithubCard(github: u.github!),
      if (u.embeddings != null) EmbeddingsCard(embeddings: u.embeddings!),
      if (u.search != null) SearchCard(search: u.search!),
      KnowledgeCard(
        kb: u.kb,
        onOpen: () {
          Haptics.tap();
          Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => const KnowledgeScreen()),
          );
        },
      ),
    ];
    return [
      for (var i = 0; i < cards.length; i++) ...[if (i > 0) _gap, cards[i]],
    ];
  }

  Widget _themePicker(AppScope scope) {
    return Segmented<ThemeMode>(
      value: scope.settings.themeMode,
      onChanged: scope.settings.setThemeMode,
      icons: const {
        ThemeMode.system: AppIcons.themeSystem,
        ThemeMode.light: AppIcons.themeLight,
        ThemeMode.dark: AppIcons.themeDark,
      },
      options: const [
        (ThemeMode.system, AppStrings.themeSystem),
        (ThemeMode.light, AppStrings.themeLight),
        (ThemeMode.dark, AppStrings.themeDark),
      ],
    );
  }

  Widget _modeChips(BuildContext context, AppScope scope) {
    const labels = {
      'default': AppStrings.modeEngineer,
      'debug': AppStrings.modeDebug,
      'review': AppStrings.modeReview,
      'design': AppStrings.modeArchitect,
      'explain': AppStrings.modeExplain,
    };
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(AppStrings.mode, style: context.text.label),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final id in SettingsController.modes)
              GestureDetector(
                onTap: () {
                  Haptics.tap();
                  scope.settings.setMode(id);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    color: scope.settings.mode == id
                        ? p.textPrimary
                        : Colors.transparent,
                    border: Border.all(
                      color: scope.settings.mode == id
                          ? p.textPrimary
                          : p.borderStrong,
                      width: AppBorder.thin,
                    ),
                  ),
                  child: IconLabel(
                    icon: AppIcons.mode(id),
                    text: labels[id]!,
                    style: context.text.caption,
                    color: scope.settings.mode == id
                        ? p.textInverse
                        : p.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _aboutRows(BuildContext context, AppScope scope) {
    final p = context.palette;
    final h = scope.usage.health;
    final (label, color) = switch (h) {
      null => (AppStrings.dash, p.textTertiary),
      HealthStatus(online: false) => (AppStrings.offline, p.accent),
      HealthStatus(ok: true) => (AppStrings.online, p.textPrimary),
      _ => (AppStrings.degraded, p.accent),
    };
    String up(String? v) => v == null ? AppStrings.dash : v.toUpperCase();
    return Column(
      children: [
        _line(context, AppStrings.backend, scope.baseUrl),
        _line(context, AppStrings.status, label, color: color),
        if (h?.online ?? false) ...[
          _line(context, AppStrings.database, up(h!.db)),
          _line(context, AppStrings.embeddings, up(h.embeddings)),
        ],
      ],
    );
  }

  Widget _line(
    BuildContext context,
    String label,
    String value, {
    Color? color,
  }) {
    return SizedBox(
      height: AppSizes.sourceRowHeight,
      child: Row(
        children: [
          Text(label, style: context.text.label),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.caption.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
