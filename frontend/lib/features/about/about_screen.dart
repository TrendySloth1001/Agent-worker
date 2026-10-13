import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_scope.dart';
import '../../core/constants/about.dart';
import '../../core/constants/changelog.dart';
import '../../core/constants/m3_copy.dart';
import '../../core/constants/onboarding.dart';
import '../../core/constants/app_config.dart';
import '../../core/constants/app_icons.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/constants/app_strings.dart';
import '../../core/haptics.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/dot_grid_background.dart';
import '../../core/widgets/m3_kit_extras.dart';
import '../../core/widgets/illustration.dart';
import '../../data/usage.dart';
import '../../core/constants/auth_constants.dart';
import '../auth/auth_controller.dart';
import '../auth/widgets/auth_widgets.dart';
import '../chat/widgets/open_url.dart';
import '../onboarding/onboarding_screen.dart';
import 'changelog_screen.dart';
import '../settings/widgets/section_header.dart';
import '../settings/telemetry/telemetry_screen.dart';
import '../settings/widgets/developer_section.dart';
import '../settings/widgets/settings_kit.dart';
import '../../core/constants/settings_copy.dart';

/// About sparky. Everyone gets the logo, version, what's new, the tour,
/// privacy and terms, licenses and feedback. The owner also sees what it
/// does, privacy details, credits and a collapsible Developer section with
/// the server address, status, build and Telemetry.
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  static Future<void> open(BuildContext context) {
    Haptics.tap();
    return Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const AboutScreen()));
  }

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _version = AboutStrings.fallbackVersion;
  String _build = AboutStrings.fallbackBuild;
  bool _healthRequested = false;

  /// Null in widget tests that pump the screen on its own.
  AppScope? _scope;

  static bool _licensesAdded = false;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    if (_healthRequested || !_owner) return;
    _healthRequested = true;
    // Opened from Profile, health may not be loaded yet.
    final usage = _scope?.usage;
    if (usage != null && usage.health == null && !usage.loading) {
      usage.refresh();
    }
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        if (info.version.isNotEmpty) _version = info.version;
        if (info.buildNumber.isNotEmpty) _build = info.buildNumber;
      });
    } catch (_) {
      // Keep the fallback from pubspec.
    }
  }

  String get _platform {
    final name = _titleCase(defaultTargetPlatform.name);
    return name.isEmpty ? AboutStrings.fallbackPlatform : name;
  }

  String get _baseUrl => _scope?.baseUrl ?? AppConfig.apiBaseUrl;

  bool get _owner => AuthController.instance.user?.isOwner ?? false;

  /// Privacy policy and terms are served by the sparky server.
  void _openLegal(String path) {
    Haptics.tap();
    openUrl(context, '$_baseUrl$path');
  }

  String get _host {
    final host = Uri.tryParse(_baseUrl)?.host ?? '';
    return host.isEmpty ? _baseUrl : host;
  }

  void _snack(String text) {
    final p = context.palette;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: p.surfaceHigh,
          content: Text(text, style: context.text.label),
        ),
      );
  }

  Future<void> _copyUrl() async {
    Haptics.tap();
    await Clipboard.setData(ClipboardData(text: _baseUrl));
    if (mounted) _snack(AboutStrings.urlCopied);
  }

  void _addLicenses() {
    if (_licensesAdded) return;
    _licensesAdded = true;
    LicenseRegistry.addLicense(
      () => Stream.fromIterable(const [
        LicenseEntryWithLineBreaks([
          AboutStrings.licensePeeps,
        ], AboutStrings.licensePeepsText),
        LicenseEntryWithLineBreaks([
          AboutStrings.licenseDoodles,
        ], AboutStrings.licenseDoodlesText),
        LicenseEntryWithLineBreaks([
          AboutStrings.licenseLobeIcons,
        ], AboutStrings.licenseLobeIconsText),
        LicenseEntryWithLineBreaks([
          AboutStrings.licenseIcons,
        ], AboutStrings.licenseIconsText),
        LicenseEntryWithLineBreaks([
          AboutStrings.licenseLogos,
        ], AboutStrings.licenseLogosText),
        LicenseEntryWithLineBreaks([
          AboutStrings.licenseFonts,
        ], AboutStrings.licenseFontsText),
      ]),
    );
  }

  void _openLicenses() {
    Haptics.tap();
    _addLicenses();
    showLicensePage(
      context: context,
      applicationName: AboutStrings.appName,
      applicationVersion: AboutStrings.versionShort(_version, _build),
      applicationLegalese: AboutStrings.legalese,
      applicationIcon: const Padding(
        padding: EdgeInsets.all(AppSpacing.sm),
        child: Wordmark(size: AboutSizes.licenseWordmark),
      ),
    );
  }

  Future<void> _sendFeedback() async {
    Haptics.tap();
    final subject = Uri.encodeComponent(AboutStrings.feedbackSubject(_version));
    final uri = Uri.parse(
      'mailto:${AboutStrings.feedbackEmail}?subject=$subject',
    );
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (opened || !mounted) return;
    Haptics.error();
    await Clipboard.setData(
      const ClipboardData(text: AboutStrings.feedbackEmail),
    );
    if (mounted) _snack(AboutStrings.noMailApp);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AuthController.instance,
      builder: (context, _) {
        final owner = _owner;
        return M3Page(
          title: AboutCopy.title,
          slivers: [
            M3Body(
              children: [
                Builder(builder: _hero),
                const SizedBox(height: SettingsSizes.groupSpacing),
                SettingsGroup(
                  entries: [
                    GroupEntry(
                      _LinkTile(
                        icon: ChangelogIcons.entry,
                        title: ChangelogStrings.entry,
                        onTap: () => ChangelogScreen.open(context),
                      ),
                    ),
                    GroupEntry(
                      _LinkTile(
                        icon: OnboardingIcons.tour,
                        title: OnboardingStrings.takeTour,
                        onTap: () => OnboardingScreen.open(context),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: SettingsSizes.groupSpacing),
                SettingsGroup(
                  entries: [
                    GroupEntry(
                      _LinkTile(
                        icon: AboutIcons.privacyPolicy,
                        title: AboutStrings.privacyPolicy,
                        external: true,
                        onTap: () => _openLegal(AuthLegal.privacyPath),
                      ),
                    ),
                    GroupEntry(
                      _LinkTile(
                        icon: AboutIcons.terms,
                        title: AboutStrings.terms,
                        external: true,
                        onTap: () => _openLegal(AuthLegal.termsPath),
                      ),
                    ),
                    GroupEntry(
                      _LinkTile(
                        icon: AboutIcons.licenses,
                        title: AboutCopy.licenses,
                        onTap: _openLicenses,
                      ),
                    ),
                    GroupEntry(
                      _LinkTile(
                        icon: AboutIcons.feedback,
                        title: AboutCopy.feedback,
                        onTap: _sendFeedback,
                      ),
                    ),
                  ],
                ),
                if (owner) ..._ownerSections(context),
                const SizedBox(height: AppSpacing.xxl),
                const _Footer(),
              ],
            ),
          ],
        );
      },
    );
  }

  /// What it does, privacy details, credits and the Developer section.
  List<Widget> _ownerSections(BuildContext context) {
    final usage = _scope?.usage;
    Widget status(HealthStatus? h) => _StatusTile(health: h);
    return [
      const SettingsGroupHeader(AboutCopy.whatItDoes),
      _ItemGroup(items: AboutStrings.features),
      const SettingsGroupHeader(AboutCopy.privacy),
      _ItemGroup(items: AboutStrings.privacyItems(_host)),
      const SettingsGroupHeader(AboutCopy.credits),
      const _Credits(),
      DeveloperSection(
        summary: AboutStrings.developerHelp,
        children: [
          _BackendTile(url: _baseUrl, onTap: _copyUrl),
          if (usage == null)
            status(null)
          else
            ListenableBuilder(
              listenable: usage,
              builder: (context, _) => status(usage.health),
            ),
          SettingsTile(
            icon: AboutIcons.build,
            title: AboutStrings.buildTitle,
            summary: AboutStrings.buildLine(_version, _build, _platform),
          ),
          SettingsTile(
            icon: AboutIcons.telemetry,
            title: AboutStrings.telemetry,
            summary: AboutStrings.telemetryHelp,
            onTap: () =>
                Navigator.push(context, settingsRoute(const TelemetryScreen())),
          ),
        ],
      ),
    ];
  }

  /// Hero card: dot-matrix field with the illustration, wordmark, tagline and
  /// a tiny mono version tag.
  Widget _hero(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return M3Card(
      padding: EdgeInsets.zero,
      child: Stack(
        children: [
          const Positioned.fill(child: DotGridBackground()),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                children: [
                  const Illustration(
                    kind: IllustrationKind.hello,
                    height: AboutSizes.illustration,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const Wordmark(size: AboutSizes.wordmark),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    AboutStrings.tagline,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  M3Tag(
                    _owner
                        ? AboutStrings.versionLine(_version, _build, _platform)
                        : AboutStrings.versionPlain(_version),
                    mono: false,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Icon circle, title and one-line detail per row, in one rounded group.
class _ItemGroup extends StatelessWidget {
  const _ItemGroup({required this.items});

  final List<AboutItem> items;

  @override
  Widget build(BuildContext context) {
    return SettingsGroup(
      entries: [
        for (final item in items)
          GroupEntry(
            ListTile(
              leading: SettingsIconCircle(item.icon),
              title: Text(item.title),
              subtitle: Text(item.detail),
            ),
          ),
      ],
    );
  }
}

/// API base URL; tap copies it. Owner only.
class _BackendTile extends StatelessWidget {
  const _BackendTile({required this.url, required this.onTap});

  final String url;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SettingsTile(
      icon: AboutIcons.backend,
      title: url,
      summary: AboutCopy.urlHint,
      trailing: AppIcon(
        AboutIcons.copy,
        size: AppIconSize.sm,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      onTap: onTap,
    );
  }
}

/// Live server health. Owner only.
class _StatusTile extends StatelessWidget {
  const _StatusTile({required this.health});

  final HealthStatus? health;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (label, color) = switch (health) {
      null => (AppStrings.dash, p.textTertiary),
      HealthStatus(online: false) => (AppStrings.offline, p.accent),
      HealthStatus(ok: true) => (AppStrings.online, p.textPrimary),
      _ => (AppStrings.degraded, p.accent),
    };
    return ListTile(
      leading: const SettingsIconCircle(AboutIcons.backend),
      title: const Text(AboutCopy.status),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusDot(color: color, hollow: health == null),
          const SizedBox(width: AppSpacing.sm),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelLarge!.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

/// One row of the About lists; [external] shows an open-in-browser mark.
class _LinkTile extends StatelessWidget {
  const _LinkTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.external = false,
  });

  final AppIconData icon;
  final String title;
  final VoidCallback onTap;
  final bool external;

  @override
  Widget build(BuildContext context) {
    return SettingsTile(
      icon: icon,
      title: title,
      trailing: AppIcon(
        external ? AboutIcons.open : AboutIcons.chevron,
        size: AppIconSize.sm,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      onTap: onTap,
    );
  }
}

class _Credits extends StatelessWidget {
  const _Credits();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const credits = AboutStrings.creditList;
    return SettingsGroup(
      entries: [
        for (final credit in credits)
          GroupEntry(
            ListTile(
              onTap: credit.url == null
                  ? null
                  : () => openUrl(context, credit.url!),
              leading: SettingsIconCircle(credit.icon),
              title: Text(credit.value),
              subtitle: Text(credit.label),
              trailing: credit.url == null
                  ? null
                  : AppIcon(
                      AboutIcons.open,
                      size: AppIconSize.sm,
                      color: scheme.onSurfaceVariant,
                    ),
            ),
          ),
      ],
    );
  }
}

/// MADE WITH [heart] - (c) 2026 sparky.
class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final style = AppTextStyles.caption.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.xs,
      children: [
        Text(AboutStrings.madeWith, style: style),
        AppIcon(
          AboutIcons.heart,
          size: AppIconSize.xs,
          color: p.accent,
          semanticLabel: AboutStrings.love,
        ),
        Text(AboutStrings.footerRest, style: style),
      ],
    );
  }
}

/// Chevron row that opens [AboutScreen]; used in Settings → ABOUT.
class AboutEntryRow extends StatelessWidget {
  const AboutEntryRow({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return InkWell(
      onTap: () => AboutScreen.open(context),
      child: SizedBox(
        height: AppSizes.rowHeight,
        child: Row(
          children: [
            AppIcon(
              AboutIcons.entry,
              size: AppIconSize.sm,
              color: p.textSecondary,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(AboutStrings.entry, style: context.text.label),
            ),
            AppIcon(
              AboutIcons.chevron,
              size: AppIconSize.xs,
              color: p.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

/// Small centered caption link for screen footers (Profile).
class AboutFooterLink extends StatelessWidget {
  const AboutFooterLink({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Center(
      child: TextButton.icon(
        onPressed: () => AboutScreen.open(context),
        icon: AppIcon(
          AboutIcons.entry,
          size: AppIconSize.xs,
          color: p.textTertiary,
        ),
        label: Text(AboutStrings.entry, style: context.text.caption),
      ),
    );
  }
}

String _titleCase(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
