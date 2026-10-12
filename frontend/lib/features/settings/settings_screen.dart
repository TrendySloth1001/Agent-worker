import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_scope.dart';
import '../../core/constants/voice.dart';
import '../../core/constants/app_icons.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/constants/app_strings.dart';
import '../../core/constants/memory.dart';
import '../../core/constants/settings_copy.dart';
import '../../core/constants/storage.dart';
import '../../core/haptics.dart';
import '../../core/platform/browsers.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/system_chrome.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/browser_picker.dart';
import '../../core/widgets/icon_label.dart';
import '../../core/widgets/segmented.dart';
import '../../core/widgets/toggle_row.dart';
import '../../data/usage.dart';
import '../about/about_screen.dart';
import '../auth/auth_controller.dart';
import '../knowledge/knowledge_screen.dart';
import '../memory/memory_screen.dart';
import '../storage/storage_screen.dart';
import '../storage/widgets/storage_usage_card.dart';
import 'settings_controller.dart';
import 'telemetry/telemetry_entry.dart';
import 'widgets/connections_section.dart';
import 'widgets/model_choice.dart';
import 'widgets/personalization.dart';
import 'widgets/provider_card.dart';
import 'widgets/reply_style_cards.dart';
import 'widgets/section_header.dart';
import 'widgets/service_cards.dart';
import 'widgets/status_strip.dart';
import 'widgets/usage_states.dart';

/// One searchable block of the screen. [keywords] is lowercase text the
/// search field matches against (labels, helper text and synonyms).
class _Item {
  const _Item(this.keywords, this.build);

  final String keywords;
  final Widget Function(BuildContext) build;
}

/// A titled group of items with a one-line helper.
class _Group {
  const _Group({
    required this.id,
    required this.title,
    required this.help,
    required this.icon,
    required this.items,
    this.collapsible = false,
  });

  final String id, title, help;
  final AppIconData icon;
  final List<_Item> items;

  /// Collapsed by default (Advanced).
  final bool collapsible;
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _started = false;
  final _search = TextEditingController();
  String _query = '';
  bool _advancedOpen = false;
  bool _customiseOpen = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    AppScope.of(context).usage.refresh();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _setQuery(String v) => setState(() => _query = v.trim().toLowerCase());

  @override
  Widget build(BuildContext context) {
    // Plain-language rows read better in the regular font than in mono caps.
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        extensions: [context.palette, context.text.readable()],
      ),
      child: Builder(builder: _build),
    );
  }

  Widget _build(BuildContext context) {
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
          listenable: Listenable.merge([
            scope.settings,
            scope.usage,
            AuthController.instance,
          ]),
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
              children: [_searchField(context), ..._body(context, scope)],
            ),
          ),
        ),
      ),
    );
  }

  Widget _searchField(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: TextField(
        controller: _search,
        onChanged: _setQuery,
        style: context.text.body,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: SettingsStrings.searchHint,
          prefixIcon: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: AppIcon(
              AppIcons.search,
              size: AppIconSize.sm,
              color: p.textSecondary,
            ),
          ),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  tooltip: SettingsStrings.searchClear,
                  icon: const AppIcon(AppIcons.close, size: AppIconSize.sm),
                  onPressed: () {
                    Haptics.tap();
                    _search.clear();
                    _setQuery('');
                  },
                ),
        ),
      ),
    );
  }

  bool _matches(String keywords, String title) =>
      _query.isEmpty ||
      keywords.contains(_query) ||
      title.toLowerCase().contains(_query);

  List<Widget> _body(BuildContext context, AppScope scope) {
    final searching = _query.isNotEmpty;
    final out = <Widget>[];
    for (final g in _groups(context, scope)) {
      final items = [
        for (final i in g.items)
          if (_matches(i.keywords, g.title)) i,
      ];
      if (items.isEmpty) continue;
      final open = !g.collapsible || searching || _advancedOpen;
      out.add(
        g.collapsible && !searching
            ? _collapsibleHeader(context, g)
            : _groupHeader(context, g),
      );
      if (open) {
        for (final i in items) {
          out.add(i.build(context));
        }
      }
    }
    if (out.isEmpty) {
      out.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
          child: Text(
            SettingsStrings.noResults,
            textAlign: TextAlign.center,
            style: context.text.caption,
          ),
        ),
      );
    }
    if (!searching || _matches('reset defaults restore', '')) {
      out.add(_resetRow(context, scope));
    }
    return out;
  }

  Widget _groupHeader(BuildContext context, _Group g) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SectionHeader(g.title, icon: g.icon),
      Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Text(g.help, style: context.text.caption),
      ),
    ],
  );

  Widget _collapsibleHeader(BuildContext context, _Group g) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: Semantics(
        button: true,
        expanded: _advancedOpen,
        child: InkWell(
          onTap: () {
            Haptics.tap();
            setState(() => _advancedOpen = !_advancedOpen);
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: SettingsSizes.touchTarget,
            ),
            child: Row(
              children: [
                AppIcon(g.icon, size: AppIconSize.sm, color: p.textSecondary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(g.title, style: context.text.caption),
                      Text(g.help, style: context.text.caption),
                    ],
                  ),
                ),
                AppIcon(
                  _advancedOpen ? AppIcons.collapse : AppIcons.expand,
                  size: AppIconSize.sm,
                  color: p.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<_Group> _groups(BuildContext context, AppScope scope) {
    final s = scope.settings;
    final isOwner = AuthController.instance.user?.isOwner ?? false;
    return [
      _Group(
        id: 'you',
        title: SettingsStrings.youTitle,
        help: SettingsStrings.youHelp,
        icon: SettingsIcons.you,
        items: [
          _Item(
            'name role about you profile sign-off signature email who',
            (_) => const ProfileRows(),
          ),
        ],
      ),
      _Group(
        id: 'replies',
        title: SettingsStrings.repliesTitle,
        help: SettingsStrings.repliesHelp,
        icon: AppIcons.chat,
        items: [
          _Item(
            'style preset friendly straight point teacher professional fun '
            'tone short long sound',
            (_) => const ReplyStyleCards(),
          ),
          _Item(
            'autocomplete suggest words type typing keyboard predict',
            (_) => ToggleRow(
              label: SettingsStrings.autocompleteLabel,
              subtitle: SettingsStrings.autocompleteHelp,
              icon: AppIcons.aiFormat,
              value: s.autocompleteOn,
              onChanged: s.setAutocomplete,
            ),
          ),
          _Item(
            'voice dictate microphone speech send automatically',
            (_) => ToggleRow(
              label: VoiceStrings.autoSendLabel,
              subtitle: VoiceStrings.autoSendHelp,
              icon: AppIcons.mic,
              value: s.voiceAutoSend,
              onChanged: s.setVoiceAutoSend,
            ),
          ),
          _Item(
            'voice dictate microphone speech accuracy whisper transcription',
            (_) => ToggleRow(
              label: VoiceStrings.accuracyLabel,
              subtitle: VoiceStrings.accuracyHelp,
              icon: AppIcons.mic,
              value: s.voiceHighAccuracy,
              onChanged: s.setVoiceHighAccuracy,
            ),
          ),
          _Item(
            'language translate reply instructions anything else know custom',
            (_) => const ReplyTextRows(),
          ),
          _Item(
            'customise customize tone length concise balanced detailed '
            'casual direct enthusiastic',
            _customise,
          ),
        ],
      ),
      _Group(
        id: 'privacy',
        title: SettingsStrings.privacyTitle,
        help: SettingsStrings.privacyHelp,
        icon: SettingsIcons.privacy,
        items: [
          _Item(
            'memory remember facts forget manage memories personal',
            (c) => InkWell(
              onTap: () => MemoryScreen.open(c),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: SettingsSizes.touchTarget,
                ),
                child: Row(
                  children: [
                    AppIcon(
                      MemoryIcons.section,
                      size: AppIconSize.sm,
                      color: c.palette.textSecondary,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.sm,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              SettingsStrings.memoryLabel,
                              style: c.text.label,
                            ),
                            Text(
                              SettingsStrings.memoryHelp,
                              style: c.text.caption,
                            ),
                          ],
                        ),
                      ),
                    ),
                    AppIcon(
                      AppIcons.chevronRight,
                      size: AppIconSize.xs,
                      color: c.palette.textTertiary,
                    ),
                  ],
                ),
              ),
            ),
          ),
          _Item(
            'web search online internet look up privacy',
            (_) => ToggleRow(
              label: SettingsStrings.webLabel,
              subtitle: SettingsStrings.webHelp,
              icon: AppIcons.web,
              value: s.defaultWebSearch,
              onChanged: s.setDefaultWebSearch,
            ),
          ),
          _Item(
            'knowledge base notes files saved memory remember',
            (_) => ToggleRow(
              label: SettingsStrings.kbLabel,
              subtitle: SettingsStrings.kbHelp,
              icon: AppIcons.knowledge,
              value: s.defaultKnowledge,
              onChanged: s.setDefaultKnowledge,
            ),
          ),
          _Item(
            'round table several models ai cross-check',
            (_) => ToggleRow(
              label: SettingsStrings.tableLabel,
              subtitle: SettingsStrings.tableHelp,
              icon: AppIcons.roundTable,
              value: s.defaultRoundTable,
              onChanged: s.setDefaultRoundTable,
            ),
          ),
        ],
      ),
      _Group(
        id: 'apps',
        title: SettingsStrings.appsTitle,
        help: SettingsStrings.appsHelp,
        icon: SettingsIcons.apps,
        items: [
          _Item(
            'connections github google drive photos accounts link',
            (_) => const ConnectionsSection(),
          ),
          if (Browsers.supported)
            _Item(
              'browser links open default chrome',
              (c) => _browserRow(c, scope),
            ),
        ],
      ),
      _Group(
        id: 'storage',
        title: SettingsStrings.storageTitle,
        help: SettingsStrings.storageHelp,
        icon: StorageIcons.section,
        items: [
          _Item(
            'storage files uploads space delete clean',
            (c) => StorageEntryCard(onOpen: () => StorageScreen.open(c)),
          ),
        ],
      ),
      _Group(
        id: 'notifications',
        title: SettingsStrings.notificationsTitle,
        help: SettingsStrings.notificationsHelp,
        icon: SettingsIcons.notifications,
        items: [
          _Item(
            'notify notification alert round table done background',
            (_) => ToggleRow(
              label: SettingsStrings.tableNotifyLabel,
              subtitle: SettingsStrings.tableNotifyHelp,
              icon: TableIcons.notify,
              value: s.notifyRoundTable,
              onChanged: s.setNotifyRoundTable,
            ),
          ),
        ],
      ),
      _Group(
        id: 'appearance',
        title: SettingsStrings.appearanceTitle,
        help: SettingsStrings.appearanceHelp,
        icon: AppIcons.appearance,
        items: [
          _Item(
            'theme dark light mode night system',
            (_) => _labelled(
              SettingsStrings.themeLabel,
              null,
              _themePicker(scope),
            ),
          ),
          _Item(
            'text size font bigger larger smaller accessibility zoom',
            (_) => _labelled(
              SettingsStrings.textSizeLabel,
              SettingsStrings.textSizeHelp,
              _textSizePicker(scope),
            ),
          ),
          _Item(
            'vibrate haptics buzz feedback touch',
            (_) => ToggleRow(
              label: SettingsStrings.hapticsLabel,
              subtitle: SettingsStrings.hapticsHelp,
              icon: AppIcons.haptics,
              value: s.hapticsOn,
              onChanged: s.setHaptics,
            ),
          ),
        ],
      ),
      _Group(
        id: 'advanced',
        title: SettingsStrings.advancedTitle,
        help: SettingsStrings.advancedHelp,
        icon: SettingsIcons.advanced,
        collapsible: true,
        items: [
          _Item(
            'model ai auto fastest smartest fast smart choose gpt',
            (_) => _labelled(
              SettingsStrings.modelTitle,
              null,
              const ModelChoice(),
            ),
          ),
          _Item(
            'mode engineer debug review architect explain focus',
            (c) => _labelled(
              SettingsStrings.modeTitle,
              SettingsStrings.modeHelp,
              _modeChips(c, scope),
            ),
          ),
          _Item(
            'usage limits quota providers status server health data tools '
            'embeddings search knowledge',
            (c) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                ..._services(c, scope),
                const SizedBox(height: AppSpacing.md),
                _aboutRows(c, scope),
              ],
            ),
          ),
          if (isOwner)
            const _Item('telemetry owner developer analytics', _telemetry),
        ],
      ),
      _Group(
        id: 'about',
        title: SettingsStrings.aboutTitle,
        help: '',
        icon: AppIcons.about,
        items: const [
          _Item('about version licenses feedback sparky', _aboutEntry),
        ],
      ),
    ];
  }

  static Widget _telemetry(BuildContext context) => const TelemetryEntry();

  static Widget _aboutEntry(BuildContext context) => const AboutEntryRow();

  Widget _labelled(String label, String? help, Widget child) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: context.text.label),
        if (help != null) Text(help, style: context.text.caption),
        const SizedBox(height: AppSpacing.sm),
        child,
      ],
    ),
  );

  Widget _customise(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: _customiseOpen,
          child: InkWell(
            onTap: () {
              Haptics.tap();
              setState(() => _customiseOpen = !_customiseOpen);
            },
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: SettingsSizes.touchTarget,
              ),
              child: Row(
                children: [
                  AppIcon(
                    SettingsIcons.customise,
                    size: AppIconSize.sm,
                    color: p.textSecondary,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          SettingsStrings.customise,
                          style: context.text.label,
                        ),
                        Text(
                          SettingsStrings.customiseHelp,
                          style: context.text.caption,
                        ),
                      ],
                    ),
                  ),
                  AppIcon(
                    _customiseOpen ? AppIcons.collapse : AppIcons.expand,
                    size: AppIconSize.sm,
                    color: p.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_customiseOpen) ...[
          const SizedBox(height: AppSpacing.sm),
          const ToneLengthControls(),
          const SizedBox(height: AppSpacing.md),
        ],
      ],
    );
  }

  Widget _resetRow(BuildContext context, AppScope scope) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: InkWell(
        onTap: () => _confirmReset(context, scope),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: SettingsSizes.touchTarget,
          ),
          child: Row(
            children: [
              AppIcon(
                SettingsIcons.reset,
                size: AppIconSize.sm,
                color: p.accent,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      SettingsStrings.reset,
                      style: context.text.label.copyWith(color: p.accent),
                    ),
                    Text(
                      SettingsStrings.resetHelp,
                      style: context.text.caption,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmReset(BuildContext context, AppScope scope) async {
    Haptics.tap();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(SettingsStrings.resetConfirmTitle),
        content: const Text(SettingsStrings.resetConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(SettingsStrings.cancel),
          ),
          TextButton(
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
      this.context,
    ).showSnackBar(const SnackBar(content: Text(SettingsStrings.resetDone)));
  }

  Widget _browserRow(BuildContext context, AppScope scope) {
    final p = context.palette;
    final label = scope.settings.browserLabel;
    return InkWell(
      onTap: () => showBrowserPicker(context, forSettings: true),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: SettingsSizes.touchTarget),
        child: Row(
          children: [
            AppIcon(
              AppIcons.browser,
              size: AppIconSize.sm,
              color: p.textSecondary,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(BrowserStrings.rowLabel, style: context.text.label),
                  Text(
                    SettingsStrings.browserHelp,
                    style: context.text.caption,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Flexible(
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

  Widget _textSizePicker(AppScope scope) {
    const labels = {
      'small': SettingsStrings.textSmall,
      'normal': SettingsStrings.textNormal,
      'large': SettingsStrings.textLarge,
      'huge': SettingsStrings.textHuge,
    };
    final p = context.palette;
    final current = scope.settings.textScale;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final id in labels.keys)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              Haptics.tap();
              scope.settings.setTextScale(id);
            },
            child: Semantics(
              button: true,
              selected: current == id,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: AppSizes.minTap),
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    color: current == id ? p.textPrimary : Colors.transparent,
                    border: Border.all(
                      color: current == id ? p.textPrimary : p.borderStrong,
                      width: AppBorder.thin,
                    ),
                  ),
                  child: Text(
                    labels[id]!,
                    style: context.text.caption.copyWith(
                      color: current == id ? p.textInverse : p.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
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
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final id in SettingsController.modes)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              Haptics.tap();
              scope.settings.setMode(id);
            },
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppSizes.minTap),
              child: Container(
                alignment: Alignment.center,
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
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppSizes.sourceRowHeight),
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
