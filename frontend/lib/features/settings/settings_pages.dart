import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/constants/app_icons.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/constants/about.dart';
import '../../core/constants/app_strings.dart';
import '../../core/constants/connections.dart';
import '../../core/constants/memory.dart';
import '../../core/constants/settings_copy.dart';
import '../../core/constants/storage.dart';
import '../../core/constants/telemetry.dart';
import '../../core/constants/voice.dart';
import '../../core/platform/browsers.dart';
import '../../core/theme/app_palette.dart';
import '../../core/widgets/browser_picker.dart';
import '../../data/usage.dart';
import '../about/about_screen.dart';
import '../auth/auth_controller.dart';
import '../connections/connections_controller.dart';
import '../knowledge/knowledge_screen.dart';
import '../memory/memory_screen.dart';
import '../profile/profile_screen.dart';
import '../storage/storage_screen.dart';
import '../storage/widgets/storage_usage_card.dart';
import 'settings_controller.dart';
import 'telemetry/telemetry_screen.dart';
import 'widgets/appearance_tiles.dart';
import 'widgets/connections_section.dart';
import 'widgets/model_choice.dart';
import 'widgets/personalization.dart';
import 'widgets/provider_card.dart';
import 'widgets/reply_style_cards.dart';
import 'widgets/service_cards.dart';
import 'widgets/settings_kit.dart';
import 'widgets/status_strip.dart';
import 'widgets/usage_states.dart';

/// The entries on the Settings root, in display order within their groups.
enum SettingsCategory {
  profile,
  replies,
  privacy,
  search,
  apps,
  storage,
  notifications,
  appearance,
  models,
  telemetry,
  server,
  about;

  String get title => switch (this) {
    profile => SettingsStrings.catProfile,
    replies => SettingsStrings.catReplies,
    privacy => SettingsStrings.catPrivacy,
    search => SettingsStrings.catSearch,
    apps => SettingsStrings.catApps,
    storage => SettingsStrings.catStorage,
    notifications => SettingsStrings.catNotifications,
    appearance => SettingsStrings.catAppearance,
    models => SettingsStrings.catModels,
    telemetry => SettingsStrings.catTelemetry,
    server => SettingsStrings.catServer,
    about => SettingsStrings.catAbout,
  };

  AppIconData get icon => switch (this) {
    profile => AppIcons.personalization,
    replies => AppIcons.chat,
    privacy => SettingsIcons.privacy,
    search => AppIcons.web,
    apps => SettingsIcons.apps,
    storage => StorageIcons.section,
    notifications => SettingsIcons.notifications,
    appearance => AppIcons.appearance,
    models => AppIcons.models,
    telemetry => TelemetryIcons.live,
    server => AppIcons.server,
    about => AppIcons.about,
  };

  /// Only the owner sees this entry.
  bool get ownerOnly => this == telemetry;

  /// Opens an existing screen instead of a settings page.
  bool get isDirect => this == telemetry || this == about;
}

/// Opens [c]: a sub-page (optionally scrolled to [focusId]) or, for Telemetry
/// and About, their own screens.
Future<void> openSettingsCategory(
  BuildContext context,
  SettingsCategory c, {
  String? focusId,
}) {
  switch (c) {
    case SettingsCategory.telemetry:
      return Navigator.push(context, settingsRoute(const TelemetryScreen()));
    case SettingsCategory.about:
      return AboutScreen.open(context);
    default:
      return Navigator.push(
        context,
        settingsRoute(SettingsCategoryPage(category: c, focusId: focusId)),
      );
  }
}

bool isOwner() => AuthController.instance.user?.isOwner ?? false;

String modelChoiceLabel(String choice) => switch (choice) {
  'auto' => SettingsStrings.modelAuto,
  'fast' => SettingsStrings.modelFast,
  'smart' => SettingsStrings.modelSmart,
  final raw => raw,
};

String _toneLabel(String tone) => toneLabels[tone] ?? SettingsStrings.toneNone;

String _modeLabel(String mode) => switch (mode) {
  'debug' => SettingsStrings.modeDebug,
  'review' => SettingsStrings.modeReview,
  'design' => SettingsStrings.modeArchitect,
  'explain' => SettingsStrings.modeExplain,
  _ => SettingsStrings.modeEngineer,
};

String serverStatusLabel(HealthStatus? h, {required bool loading}) {
  if (h == null) {
    return loading ? SettingsStrings.checking : SettingsStrings.unknown;
  }
  if (!h.online) return SettingsStrings.offline;
  return h.ok ? SettingsStrings.online : SettingsStrings.degraded;
}

/// The one-line value summary shown under a category on the root.
String categorySummary(SettingsCategory c, AppScope scope) {
  final s = scope.settings;
  const sep = SettingsStrings.separator;
  switch (c) {
    case SettingsCategory.profile:
      final name = s.name.isEmpty ? SettingsStrings.saveFirstProfile : s.name;
      return s.role.isEmpty ? name : '$name$sep${s.role}';
    case SettingsCategory.replies:
      final tone = s.tone.isEmpty
          ? SettingsStrings.defaultReply
          : _toneLabel(s.tone);
      return '$tone$sep${lengthLabels[s.length] ?? s.length}';
    case SettingsCategory.privacy:
      return SettingsStrings.sumPrivacy;
    case SettingsCategory.search:
      final on = [
        if (s.defaultWebSearch) SettingsStrings.sumWeb,
        if (s.defaultKnowledge) SettingsStrings.sumKnowledge,
        if (s.defaultRoundTable) SettingsStrings.sumRoundTable,
      ];
      return on.isEmpty ? SettingsStrings.sumAllOff : on.join(sep);
    case SettingsCategory.apps:
      final g = ConnectionsController.instance.github;
      return g == null
          ? SettingsStrings.sumApps
          : '${ConnectStrings.github} ${ConnectStrings.account(g.login)}';
    case SettingsCategory.storage:
      return SettingsStrings.sumStorage;
    case SettingsCategory.notifications:
      return s.notifyRoundTable ? SettingsStrings.on : SettingsStrings.off;
    case SettingsCategory.appearance:
      return '${themeLabel(s.themeMode)}$sep'
          '${textSizeLabels[s.textScale] ?? SettingsStrings.textNormal}';
    case SettingsCategory.models:
      final n = scope.usage.usage?.activeProviders;
      final model = modelChoiceLabel(s.modelChoice);
      return n == null
          ? model
          : '$model$sep$n ${SettingsStrings.providersActive}';
    case SettingsCategory.telemetry:
      return SettingsStrings.sumTelemetry;
    case SettingsCategory.server:
      return serverStatusLabel(
        scope.usage.health,
        loading: scope.usage.loading,
      );
    case SettingsCategory.about:
      return AboutStrings.tagline;
  }
}

/// The content of a sub-page. Telemetry and About have none.
List<SettingsSection> sectionsFor(SettingsCategory c, AppScope scope) {
  final s = scope.settings;
  switch (c) {
    case SettingsCategory.profile:
      return [
        SettingsSection(
          title: SettingsStrings.secAbout,
          items: [
            SettingItem(
              id: 'name',
              title: SettingsStrings.nameLabel,
              keywords: 'name profile who you call me',
              build: (_) => ProfileFieldTile(
                label: SettingsStrings.nameLabel,
                icon: AppIcons.profileName,
                value: s.name,
                hint: AppStrings.nameHint,
                max: AppSizes.profileNameMax,
                onSave: s.setName,
              ),
            ),
            SettingItem(
              id: 'role',
              title: SettingsStrings.roleLabel,
              keywords: 'role job work profession profile',
              build: (_) => ProfileFieldTile(
                label: SettingsStrings.roleLabel,
                icon: AppIcons.profileRole,
                value: s.role,
                hint: AppStrings.roleHint,
                max: AppSizes.profileRoleMax,
                onSave: s.setRole,
              ),
            ),
            SettingItem(
              id: 'about',
              title: SettingsStrings.aboutYouLabel,
              keywords: 'about you bio profile format with ai',
              build: (_) => ProfileFieldTile(
                label: SettingsStrings.aboutYouLabel,
                icon: AppIcons.profileAbout,
                value: s.about,
                hint: AppStrings.aboutHint,
                max: AppSizes.profileAboutMax,
                multiline: true,
                aiField: ProfileAiStrings.fieldAbout,
                onSave: s.setAbout,
              ),
            ),
            SettingItem(
              id: 'signature',
              title: SettingsStrings.signatureLabel,
              keywords: 'sign-off signature email closing',
              build: (_) => ProfileFieldTile(
                label: SettingsStrings.signatureLabel,
                icon: AppIcons.profileSignature,
                value: s.signature,
                hint: AppStrings.signatureHint,
                max: AppSizes.profileSignatureMax,
                multiline: true,
                onSave: s.setSignature,
              ),
            ),
          ],
        ),
        SettingsSection(
          title: SettingsStrings.secAccount,
          items: [
            SettingItem(
              id: 'account',
              title: SettingsStrings.accountTitle,
              keywords:
                  'account email password sessions devices photo avatar '
                  'sign out profile',
              build: (c) => SettingsTile(
                icon: SettingsIcons.account,
                title: SettingsStrings.accountTitle,
                summary: SettingsStrings.accountHelp,
                onTap: () =>
                    Navigator.push(c, settingsRoute(const ProfileScreen())),
              ),
            ),
          ],
        ),
      ];
    case SettingsCategory.replies:
      return [
        SettingsSection(
          title: SettingsStrings.secStyle,
          items: [
            const SettingItem(
              id: 'style',
              title: SettingsStrings.replyStyleTitle,
              keywords:
                  'style preset friendly straight point teacher '
                  'professional fun tone short long sound',
              build: _replyCards,
            ),
            SettingItem(
              id: 'tone',
              title: SettingsStrings.toneLabel,
              keywords:
                  'tone casual direct enthusiastic friendly professional '
                  'customise customize',
              build: (c) => SettingsTile(
                icon: SettingsIcons.tone,
                title: SettingsStrings.toneLabel,
                summary: _toneLabel(s.tone),
                onTap: () async {
                  final v = await showChoiceDialog<String>(
                    c,
                    title: SettingsStrings.toneLabel,
                    current: s.tone,
                    options: [
                      const ChoiceOption('', SettingsStrings.toneNone),
                      for (final t in SettingsController.tones)
                        ChoiceOption(t, toneLabels[t]!),
                    ],
                  );
                  if (v != null) s.setTone(v);
                },
              ),
            ),
            SettingItem(
              id: 'length',
              title: SettingsStrings.lengthLabel,
              keywords:
                  'length concise balanced detailed short long answers '
                  'customise customize',
              build: (c) => SettingsTile(
                icon: SettingsIcons.length,
                title: SettingsStrings.lengthLabel,
                summary: lengthLabels[s.length] ?? s.length,
                onTap: () async {
                  final v = await showChoiceDialog<String>(
                    c,
                    title: SettingsStrings.lengthLabel,
                    current: s.length,
                    options: [
                      for (final l in SettingsController.lengths)
                        ChoiceOption(l, lengthLabels[l]!),
                    ],
                  );
                  if (v != null) s.setLength(v);
                },
              ),
            ),
            SettingItem(
              id: 'mode',
              title: SettingsStrings.modeTitle,
              keywords: 'mode engineer debug review architect explain focus',
              build: (c) => SettingsTile(
                icon: AppIcons.mode(s.mode),
                title: SettingsStrings.modeTitle,
                summary: _modeLabel(s.mode),
                onTap: () async {
                  final v = await showChoiceDialog<String>(
                    c,
                    title: SettingsStrings.modeTitle,
                    current: s.mode,
                    options: [
                      for (final m in SettingsController.modes)
                        ChoiceOption(m, _modeLabel(m)),
                    ],
                  );
                  if (v != null) s.setMode(v);
                },
              ),
            ),
          ],
        ),
        SettingsSection(
          title: SettingsStrings.secLanguage,
          items: [
            SettingItem(
              id: 'language',
              title: SettingsStrings.languageLabel,
              keywords: 'language translate reply english',
              build: (_) => ProfileFieldTile(
                label: SettingsStrings.languageLabel,
                icon: AppIcons.profileLanguage,
                value: s.language,
                hint: SettingsStrings.languageHint,
                max: AppSizes.profileLanguageMax,
                onSave: s.setLanguage,
              ),
            ),
            SettingItem(
              id: 'instructions',
              title: SettingsStrings.instructionsLabel,
              keywords: 'instructions anything else know custom format with ai',
              build: (_) => ProfileFieldTile(
                label: SettingsStrings.instructionsLabel,
                icon: AppIcons.profileInstructions,
                value: s.customInstructions,
                hint: AppStrings.instructionsHint,
                max: AppSizes.profileInstructionsMax,
                multiline: true,
                aiField: ProfileAiStrings.fieldInstructions,
                onSave: s.setCustomInstructions,
              ),
            ),
          ],
        ),
        SettingsSection(
          title: SettingsStrings.secTyping,
          items: [
            SettingItem(
              id: 'autocomplete',
              title: SettingsStrings.autocompleteLabel,
              keywords:
                  'autocomplete suggest words type typing keyboard '
                  'predict',
              build: (_) => SettingsSwitchTile(
                icon: AppIcons.aiFormat,
                title: SettingsStrings.autocompleteLabel,
                summary: SettingsStrings.autocompleteHelp,
                value: s.autocompleteOn,
                onChanged: s.setAutocomplete,
              ),
            ),
            SettingItem(
              id: 'voice-send',
              title: VoiceStrings.autoSendLabel,
              keywords: 'voice dictate microphone speech send automatically',
              build: (_) => SettingsSwitchTile(
                icon: AppIcons.mic,
                title: VoiceStrings.autoSendLabel,
                summary: VoiceStrings.autoSendHelp,
                value: s.voiceAutoSend,
                onChanged: s.setVoiceAutoSend,
              ),
            ),
            SettingItem(
              id: 'voice-accuracy',
              title: VoiceStrings.accuracyLabel,
              keywords:
                  'voice dictate microphone speech accuracy whisper '
                  'transcription',
              build: (_) => SettingsSwitchTile(
                icon: AppIcons.mic,
                title: VoiceStrings.accuracyLabel,
                summary: VoiceStrings.accuracyHelp,
                value: s.voiceHighAccuracy,
                onChanged: s.setVoiceHighAccuracy,
              ),
            ),
          ],
        ),
      ];
    case SettingsCategory.privacy:
      return [
        SettingsSection(
          title: SettingsStrings.secMemory,
          items: [
            SettingItem(
              id: 'memory',
              title: SettingsStrings.memoryLabel,
              keywords:
                  'memory remember facts forget manage memories '
                  'personal',
              build: (c) => SettingsTile(
                icon: MemoryIcons.section,
                title: SettingsStrings.memoryLabel,
                summary: SettingsStrings.memoryHelp,
                onTap: () => MemoryScreen.open(c),
              ),
            ),
            SettingItem(
              id: 'knowledge',
              title: SettingsStrings.knowledgeTitle,
              keywords: 'knowledge base notes files saved sources',
              build: (c) => SettingsTile(
                icon: AppIcons.knowledge,
                title: SettingsStrings.knowledgeTitle,
                summary: SettingsStrings.knowledgeHelp,
                onTap: () =>
                    Navigator.push(c, settingsRoute(const KnowledgeScreen())),
              ),
            ),
          ],
        ),
      ];
    case SettingsCategory.search:
      return [
        SettingsSection(
          title: SettingsStrings.secDefaults,
          items: [
            SettingItem(
              id: 'web',
              title: SettingsStrings.webLabel,
              keywords: 'web search online internet look up',
              build: (_) => SettingsSwitchTile(
                icon: AppIcons.web,
                title: SettingsStrings.webLabel,
                summary: SettingsStrings.webHelp,
                value: s.defaultWebSearch,
                onChanged: s.setDefaultWebSearch,
              ),
            ),
            SettingItem(
              id: 'kb',
              title: SettingsStrings.kbLabel,
              keywords: 'knowledge base notes files saved memory remember',
              build: (_) => SettingsSwitchTile(
                icon: AppIcons.knowledge,
                title: SettingsStrings.kbLabel,
                summary: SettingsStrings.kbHelp,
                value: s.defaultKnowledge,
                onChanged: s.setDefaultKnowledge,
              ),
            ),
            SettingItem(
              id: 'table',
              title: SettingsStrings.tableLabel,
              keywords: 'round table several models ai cross-check',
              build: (_) => SettingsSwitchTile(
                icon: AppIcons.roundTable,
                title: SettingsStrings.tableLabel,
                summary: SettingsStrings.tableHelp,
                value: s.defaultRoundTable,
                onChanged: s.setDefaultRoundTable,
              ),
            ),
          ],
        ),
      ];
    case SettingsCategory.apps:
      return [
        SettingsSection(
          title: SettingsStrings.secAccounts,
          items: [
            const SettingItem(
              id: 'github',
              title: ConnectStrings.github,
              keywords: 'connections github accounts link code repositories',
              build: _githubTile,
            ),
            const SettingItem(
              id: 'drive',
              title: ConnectStrings.googleDrive,
              keywords: 'google drive files connections soon',
              build: _driveTile,
            ),
            const SettingItem(
              id: 'photos',
              title: ConnectStrings.googlePhotos,
              keywords: 'google photos pictures connections soon',
              build: _photosTile,
            ),
          ],
        ),
        if (Browsers.supported)
          SettingsSection(
            title: SettingsStrings.secLinks,
            items: [
              SettingItem(
                id: 'browser',
                title: SettingsStrings.browserTitle,
                keywords: 'browser links open default chrome',
                build: (c) => SettingsTile(
                  icon: AppIcons.browser,
                  title: SettingsStrings.browserTitle,
                  summary: s.browserLabel.isEmpty
                      ? SettingsStrings.systemDefault
                      : s.browserLabel,
                  onTap: () => showBrowserPicker(c, forSettings: true),
                ),
              ),
            ],
          ),
      ];
    case SettingsCategory.storage:
      return [
        SettingsSection(
          items: [
            SettingItem(
              id: 'storage',
              title: SettingsStrings.catStorage,
              keywords: 'storage files uploads space delete clean',
              build: (c) =>
                  StorageEntryCard(onOpen: () => StorageScreen.open(c)),
            ),
          ],
        ),
      ];
    case SettingsCategory.notifications:
      return [
        SettingsSection(
          items: [
            SettingItem(
              id: 'table-notify',
              title: SettingsStrings.tableNotifyLabel,
              keywords: 'notify notification alert round table done background',
              build: (_) => SettingsSwitchTile(
                icon: TableIcons.notify,
                title: SettingsStrings.tableNotifyLabel,
                summary: SettingsStrings.tableNotifyHelp,
                value: s.notifyRoundTable,
                onChanged: s.setNotifyRoundTable,
              ),
            ),
          ],
        ),
      ];
    case SettingsCategory.appearance:
      return [
        const SettingsSection(
          title: SettingsStrings.secTheme,
          items: [
            SettingItem(
              id: 'theme',
              title: SettingsStrings.themeLabel,
              keywords: 'theme dark light mode night system',
              build: _themeTile,
            ),
          ],
        ),
        const SettingsSection(
          title: SettingsStrings.secText,
          items: [
            SettingItem(
              id: 'text-size',
              title: SettingsStrings.textSizeLabel,
              keywords:
                  'text size font bigger larger smaller accessibility '
                  'zoom',
              build: _textSizeTile,
            ),
          ],
        ),
        SettingsSection(
          title: SettingsStrings.secFeedback,
          items: [
            SettingItem(
              id: 'haptics',
              title: SettingsStrings.hapticsLabel,
              keywords: 'vibrate haptics buzz feedback touch',
              build: (_) => SettingsSwitchTile(
                icon: AppIcons.haptics,
                title: SettingsStrings.hapticsLabel,
                summary: SettingsStrings.hapticsHelp,
                value: s.hapticsOn,
                onChanged: s.setHaptics,
              ),
            ),
          ],
        ),
      ];
    case SettingsCategory.models:
      return _modelSections(scope);
    case SettingsCategory.server:
      return _serverSections(scope);
    case SettingsCategory.telemetry:
    case SettingsCategory.about:
      return const [];
  }
}

Widget _replyCards(BuildContext _) => const ReplyStyleCards();
Widget _githubTile(BuildContext _) => const GithubConnectionTile();
Widget _driveTile(BuildContext _) => const SoonTile(
  icon: ConnectIcons.googleDrive,
  title: ConnectStrings.googleDrive,
);
Widget _photosTile(BuildContext _) => const SoonTile(
  icon: ConnectIcons.googlePhotos,
  title: ConnectStrings.googlePhotos,
);
Widget _themeTile(BuildContext _) => const ThemeTile();
Widget _textSizeTile(BuildContext _) => const TextSizeTile();

List<SettingsSection> _modelSections(AppScope scope) {
  final c = scope.usage;
  final u = c.usage;
  const usageWords =
      'usage limits quota providers status server health data tools '
      'embeddings search knowledge';
  final providers = <SettingItem>[
    if (u != null)
      for (final p in u.providers)
        SettingItem(
          id: 'provider-${p.id}',
          title: p.name,
          keywords: usageWords,
          build: (_) => ProviderCard(key: ValueKey(p.id), provider: p),
        )
    else if (c.loading)
      for (var i = 0; i < AppSizes.skeletonCards; i++)
        SettingItem(
          id: 'provider-skeleton-$i',
          title: '',
          build: (_) => const SkeletonCard(),
        ),
  ];
  final services = <SettingItem>[
    if (u != null) ...[
      if (u.github != null)
        SettingItem(
          id: 'service-github',
          title: ConnectStrings.github,
          keywords: usageWords,
          build: (_) => GithubCard(github: u.github!),
        ),
      if (u.embeddings != null)
        SettingItem(
          id: 'service-embeddings',
          title: AppStrings.embeddings,
          keywords: usageWords,
          build: (_) => EmbeddingsCard(embeddings: u.embeddings!),
        ),
      if (u.search != null)
        SettingItem(
          id: 'service-search',
          title: SettingsStrings.searchService,
          keywords: usageWords,
          build: (_) => SearchCard(search: u.search!),
        ),
      SettingItem(
        id: 'service-kb',
        title: SettingsStrings.knowledgeTitle,
        keywords: usageWords,
        build: (ctx) => KnowledgeCard(
          kb: u.kb,
          onOpen: () =>
              Navigator.push(ctx, settingsRoute(const KnowledgeScreen())),
        ),
      ),
    ] else if (c.loading)
      SettingItem(
        id: 'service-skeleton',
        title: '',
        build: (_) => const SkeletonCard(),
      ),
  ];
  return [
    SettingsSection(
      title: SettingsStrings.secModel,
      wrap: modelChoiceGroup,
      items: [
        const SettingItem(
          id: 'model-auto',
          title: SettingsStrings.modelAuto,
          keywords: 'model ai auto choose gpt recommended',
          build: _modelAuto,
        ),
        const SettingItem(
          id: 'model-fast',
          title: SettingsStrings.modelFast,
          keywords: 'model ai fastest fast choose quick',
          build: _modelFast,
        ),
        const SettingItem(
          id: 'model-smart',
          title: SettingsStrings.modelSmart,
          keywords: 'model ai smartest smart choose best',
          build: _modelSmart,
        ),
        const SettingItem(
          id: 'model-specific',
          title: SettingsStrings.allModels,
          keywords: 'model ai specific choose pick list',
          build: _modelSpecific,
        ),
      ],
    ),
    SettingsSection(
      title: SettingsStrings.secUsage,
      items: [
        SettingItem(
          id: 'usage',
          title: SettingsStrings.secUsage,
          keywords: usageWords,
          build: (_) => _usageSummary(scope),
        ),
      ],
    ),
    if (providers.isNotEmpty)
      SettingsSection(title: SettingsStrings.secProviders, items: providers),
    if (services.isNotEmpty)
      SettingsSection(title: SettingsStrings.secServices, items: services),
  ];
}

Widget _modelAuto(BuildContext _) => const ModelRadioTile(
  value: 'auto',
  icon: SettingsIcons.modelAuto,
  title: SettingsStrings.modelAuto,
  help: SettingsStrings.modelAutoHelp,
);
Widget _modelFast(BuildContext _) => const ModelRadioTile(
  value: 'fast',
  icon: SettingsIcons.modelFast,
  title: SettingsStrings.modelFast,
  help: SettingsStrings.modelFastHelp,
);
Widget _modelSmart(BuildContext _) => const ModelRadioTile(
  value: 'smart',
  icon: SettingsIcons.modelSmart,
  title: SettingsStrings.modelSmart,
  help: SettingsStrings.modelSmartHelp,
);
Widget _modelSpecific(BuildContext _) => const SpecificModelTile();

/// Status strip, or the offline / loading state when there is no data.
Widget _usageSummary(AppScope scope) {
  final c = scope.usage;
  final u = c.usage;
  if (u == null) {
    return c.loading
        ? const SkeletonCard(height: AppSizes.statusStripSkeletonHeight)
        : UsageError(onRetry: c.refresh, loading: c.loading);
  }
  return Column(
    children: [
      if (c.offline)
        UsageError(onRetry: c.refresh, stale: true, loading: c.loading),
      StatusStrip(usage: u, health: c.health),
    ],
  );
}

List<SettingsSection> _serverSections(AppScope scope) {
  final c = scope.usage;
  final h = c.health;
  final status = serverStatusLabel(h, loading: c.loading);
  return [
    SettingsSection(
      title: SettingsStrings.secHealth,
      items: [
        SettingItem(
          id: 'server-status',
          title: SettingsStrings.status,
          keywords: 'server status health online offline backend',
          build: (ctx) => SettingsTile(
            icon: AppIcons.ok,
            title: SettingsStrings.status,
            summary: status,
            iconColor: h != null && !(h.online && h.ok) ? _accentOf(ctx) : null,
            trailing: c.loading
                ? const SizedBox.square(
                    dimension: AppIconSize.lg,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
            onTap: c.refresh,
          ),
        ),
        SettingItem(
          id: 'server-backend',
          title: SettingsStrings.backend,
          keywords: 'server backend url address api',
          build: (_) => SettingsTile(
            icon: AppIcons.server,
            title: SettingsStrings.backend,
            summary: scope.baseUrl,
          ),
        ),
        if (h?.online ?? false) ...[
          SettingItem(
            id: 'server-db',
            title: SettingsStrings.database,
            keywords: 'server database db postgres',
            build: (_) => SettingsTile(
              icon: AppIcons.dataTools,
              title: SettingsStrings.database,
              summary: h!.db ?? AppStrings.dash,
            ),
          ),
          SettingItem(
            id: 'server-embeddings',
            title: SettingsStrings.embeddings,
            keywords: 'server embeddings vectors',
            build: (_) => SettingsTile(
              icon: AppIcons.models,
              title: SettingsStrings.embeddings,
              summary: h!.embeddings ?? AppStrings.dash,
            ),
          ),
        ],
      ],
    ),
  ];
}

Color _accentOf(BuildContext c) => c.palette.accent;

/// A search hit: a page, or an item on a page.
class SettingsHit {
  const SettingsHit({required this.title, required this.category, this.itemId});

  final String title;
  final SettingsCategory category;

  /// Null opens the page at the top.
  final String? itemId;
}

/// Matches [query] against every page and item. Owner-only pages are left out
/// for everyone else.
List<SettingsHit> searchSettings(String query, AppScope scope) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  final owner = isOwner();
  final hits = <SettingsHit>[];
  for (final c in SettingsCategory.values) {
    if (c.ownerOnly && !owner) continue;
    if (c.title.toLowerCase().contains(q)) {
      hits.add(SettingsHit(title: c.title, category: c));
    }
    for (final section in sectionsFor(c, scope)) {
      for (final item in section.items) {
        if (item.title.isEmpty) continue;
        if (item.title.toLowerCase().contains(q) || item.keywords.contains(q)) {
          hits.add(
            SettingsHit(title: item.title, category: c, itemId: item.id),
          );
        }
      }
    }
  }
  return hits;
}

// ---------------------------------------------------------------------------

/// A settings sub-page: large app bar and the category's grouped sections.
class SettingsCategoryPage extends StatefulWidget {
  const SettingsCategoryPage({super.key, required this.category, this.focusId});

  final SettingsCategory category;

  /// Item to scroll to and flash (from search).
  final String? focusId;

  @override
  State<SettingsCategoryPage> createState() => _SettingsCategoryPageState();
}

class _SettingsCategoryPageState extends State<SettingsCategoryPage> {
  final _focusKey = GlobalKey();
  bool _flash = false;
  bool _started = false;
  Timer? _flashTimer;

  @override
  void dispose() {
    _flashTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final scope = AppScope.of(context);
    final cat = widget.category;
    if (cat == SettingsCategory.models || cat == SettingsCategory.server) {
      // refresh() notifies at once, which is not allowed while building.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => scope.usage.refresh(),
      );
    }
    if (widget.focusId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final target = _focusKey.currentContext;
        if (!mounted || target == null) return;
        final reduce = MediaQuery.disableAnimationsOf(context);
        await Scrollable.ensureVisible(
          target,
          alignment: 0.3,
          duration: reduce ? Duration.zero : AppDurations.normal,
          curve: Curves.easeOutCubic,
        );
        if (!mounted) return;
        setState(() => _flash = true);
        _flashTimer = Timer(SettingsSizes.highlightMs, () {
          if (mounted) setState(() => _flash = false);
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final cat = widget.category;
    final usageBacked =
        cat == SettingsCategory.models || cat == SettingsCategory.server;
    return ListenableBuilder(
      listenable: Listenable.merge([
        scope.settings,
        scope.usage,
        AuthController.instance,
      ]),
      builder: (context, _) => SettingsScaffold(
        title: cat.title,
        onRefresh: usageBacked ? scope.usage.refresh : null,
        children: [
          for (final section in sectionsFor(cat, scope))
            _SectionView(
              section: section,
              focusId: widget.focusId,
              focusKey: _focusKey,
              flash: _flash,
            ),
        ],
      ),
    );
  }
}

class _SectionView extends StatelessWidget {
  const _SectionView({
    required this.section,
    required this.focusId,
    required this.focusKey,
    required this.flash,
  });

  final SettingsSection section;
  final String? focusId;
  final GlobalKey focusKey;
  final bool flash;

  @override
  Widget build(BuildContext context) {
    final group = SettingsGroup(
      entries: [
        for (final item in section.items)
          GroupEntry(
            item.build(context),
            anchor: item.id == focusId ? focusKey : null,
            highlight: item.id == focusId && flash,
          ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (section.title != null)
          SettingsGroupHeader(section.title!)
        else
          const SizedBox(height: SettingsSizes.groupSpacing),
        section.wrap == null ? group : section.wrap!(context, group),
      ],
    );
  }
}
