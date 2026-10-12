import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_scope.dart';
import '../../core/constants/about.dart';
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
import '../auth/widgets/auth_widgets.dart';
import '../chat/widgets/open_url.dart';
import '../onboarding/onboarding_screen.dart';
import '../settings/widgets/section_header.dart';
import '../settings/widgets/settings_kit.dart';

/// About sparky: hero, what it does, privacy, backend, credits, licenses
/// and feedback.
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
    if (_healthRequested) return;
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
    final usage = _scope?.usage;
    return M3Page(
      title: AboutCopy.title,
      slivers: [
        M3Body(
          children: [
            Builder(builder: _hero),
            const SettingsGroupHeader(AboutCopy.whatItDoes),
            _ItemGroup(items: AboutStrings.features),
            const SettingsGroupHeader(AboutCopy.privacy),
            _ItemGroup(items: AboutStrings.privacyItems(_host)),
            const SettingsGroupHeader(AboutCopy.backend),
            if (usage == null)
              _BackendCard(url: _baseUrl, health: null, onTap: _copyUrl)
            else
              ListenableBuilder(
                listenable: usage,
                builder: (context, _) => _BackendCard(
                  url: _baseUrl,
                  health: usage.health,
                  onTap: _copyUrl,
                ),
              ),
            const SettingsGroupHeader(AboutCopy.credits),
            const _Credits(),
            const SizedBox(height: AppSpacing.xl),
            _ActionButton(
              label: OnboardingStrings.takeTour,
              icon: OnboardingIcons.tour,
              onTap: () => OnboardingScreen.open(context),
            ),
            const SizedBox(height: AppSpacing.md),
            _ActionButton(
              label: AboutCopy.licenses,
              icon: AboutIcons.licenses,
              onTap: _openLicenses,
            ),
            const SizedBox(height: AppSpacing.md),
            _ActionButton(
              label: AboutCopy.feedback,
              icon: AboutIcons.feedback,
              onTap: _sendFeedback,
            ),
            const SizedBox(height: AppSpacing.xxl),
            const _Footer(),
          ],
        ),
      ],
    );
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
                    AboutStrings.versionLine(_version, _build, _platform),
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

/// API base URL and live health; tap copies the URL.
class _BackendCard extends StatelessWidget {
  const _BackendCard({
    required this.url,
    required this.health,
    required this.onTap,
  });

  final String url;
  final HealthStatus? health;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final scheme = Theme.of(context).colorScheme;
    final (label, color) = switch (health) {
      null => (AppStrings.dash, p.textTertiary),
      HealthStatus(online: false) => (AppStrings.offline, p.accent),
      HealthStatus(ok: true) => (AppStrings.online, p.textPrimary),
      _ => (AppStrings.degraded, p.accent),
    };
    return SettingsGroup(
      entries: [
        GroupEntry(
          SettingsTile(
            icon: AboutIcons.backend,
            title: url,
            summary: AboutCopy.urlHint,
            trailing: AppIcon(
              AboutIcons.copy,
              size: AppIconSize.sm,
              color: scheme.onSurfaceVariant,
            ),
            onTap: onTap,
          ),
        ),
        GroupEntry(
          ListTile(
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
          ),
        ),
      ],
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

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final AppIconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(AppSizes.buttonHeight),
      ),
      onPressed: onTap,
      icon: AppIcon(icon, size: AppIconSize.sm),
      label: Text(label),
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
