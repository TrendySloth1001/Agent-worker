import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_scope.dart';
import '../../core/constants/about.dart';
import '../../core/constants/app_config.dart';
import '../../core/constants/app_icons.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/constants/app_strings.dart';
import '../../core/haptics.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/system_chrome.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/dot_grid_background.dart';
import '../../core/widgets/illustration.dart';
import '../../data/usage.dart';
import '../auth/widgets/auth_widgets.dart';
import '../chat/widgets/open_url.dart';
import '../settings/widgets/section_header.dart';

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
    final name = defaultTargetPlatform.name.toUpperCase();
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
    final p = context.palette;
    final usage = _scope?.usage;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: systemOverlayFor(context),
      child: Scaffold(
        backgroundColor: p.background,
        appBar: AppBar(
          leading: IconButton(
            icon: const AppIcon(AppIcons.back, size: AppIconSize.md),
            tooltip: AppStrings.back,
            onPressed: () {
              Haptics.tap();
              Navigator.pop(context);
            },
          ),
          title: const Text(AboutStrings.title),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(AppBorder.thin),
            child: Divider(color: p.border),
          ),
        ),
        body: Stack(
          children: [
            const Positioned.fill(child: DotGridBackground()),
            ListView(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.screenPadding,
                AppSpacing.xl,
                AppSpacing.screenPadding,
                MediaQuery.paddingOf(context).bottom + AppSpacing.xl,
              ),
              children: [
                _hero(context),
                const SectionHeader(
                  AboutStrings.whatItDoes,
                  icon: AboutIcons.whatItDoes,
                ),
                const _Panel(child: _ItemList(items: AboutStrings.features)),
                const SectionHeader(
                  AboutStrings.privacy,
                  icon: AboutIcons.privacy,
                ),
                _Panel(
                  child: _ItemList(
                    items: AboutStrings.privacyItems(_host),
                    compact: true,
                  ),
                ),
                const SectionHeader(
                  AboutStrings.backend,
                  icon: AboutIcons.backend,
                ),
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
                const SectionHeader(
                  AboutStrings.credits,
                  icon: AboutIcons.credits,
                ),
                const _Panel(padded: false, child: _Credits()),
                const SizedBox(height: AppSpacing.xl),
                _ActionPill(
                  label: AboutStrings.licenses,
                  icon: AboutIcons.licenses,
                  onTap: _openLicenses,
                ),
                const SizedBox(height: AppSpacing.md),
                _ActionPill(
                  label: AboutStrings.feedback,
                  icon: AboutIcons.feedback,
                  onTap: _sendFeedback,
                ),
                const SizedBox(height: AppSpacing.xxl),
                const _Footer(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _hero(BuildContext context) {
    final p = context.palette;
    return Column(
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
          style: context.text.body.copyWith(color: p.textSecondary),
        ),
        const SizedBox(height: AppSpacing.lg),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: p.background,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: p.borderStrong, width: AppBorder.thin),
          ),
          child: Text(
            AboutStrings.versionLine(_version, _build, _platform),
            textAlign: TextAlign.center,
            style: context.text.caption.copyWith(color: p.textSecondary),
          ),
        ),
      ],
    );
  }
}

/// Opaque bordered surface so text reads over the dot grid.
class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.padded = true});

  final Widget child;
  final bool padded;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: double.infinity,
      padding: padded ? const EdgeInsets.all(AppSpacing.lg) : EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: p.border, width: AppBorder.thin),
      ),
      child: child,
    );
  }
}

/// Icon + title + one-line detail, stacked.
class _ItemList extends StatelessWidget {
  const _ItemList({required this.items, this.compact = false});

  final List<AboutItem> items;

  /// Smaller icons for plain-language bullets.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : AppSpacing.lg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppIcon(
                  items[i].icon,
                  size: compact ? AppIconSize.sm : AppIconSize.md,
                  color: compact ? p.textSecondary : p.textPrimary,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        items[i].title,
                        style: context.text.bodySmall.copyWith(
                          color: p.textPrimary,
                          fontVariations: const [FontVariation.weight(600)],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(items[i].detail, style: context.text.bodySmall),
                    ],
                  ),
                ),
              ],
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
    final (label, color) = switch (health) {
      null => (AppStrings.dash, p.textTertiary),
      HealthStatus(online: false) => (AppStrings.offline, p.accent),
      HealthStatus(ok: true) => (AppStrings.online, p.textPrimary),
      _ => (AppStrings.degraded, p.accent),
    };
    return Material(
      color: p.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(color: p.border, width: AppBorder.thin),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(AboutStrings.url, style: context.text.caption),
                  const Spacer(),
                  AppIcon(
                    AboutIcons.copy,
                    size: AppIconSize.xs,
                    color: p.textTertiary,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(AboutStrings.tapToCopy, style: context.text.caption),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                url,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.text.label,
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Text(AboutStrings.status, style: context.text.caption),
                  const Spacer(),
                  StatusDot(color: color, hollow: health == null),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    label,
                    style: context.text.caption.copyWith(color: color),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Credits extends StatelessWidget {
  const _Credits();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    const credits = AboutStrings.creditList;
    return Column(
      children: [
        for (var i = 0; i < credits.length; i++) ...[
          if (i > 0) Divider(height: AppBorder.thin, color: p.border),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: credits[i].url == null
                  ? null
                  : () => openUrl(context, credits[i].url!),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                child: Row(
                  children: [
                    AppIcon(
                      credits[i].icon,
                      size: AppIconSize.sm,
                      color: p.textSecondary,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(credits[i].label, style: context.text.caption),
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            credits[i].value,
                            style: context.text.bodySmall.copyWith(
                              color: p.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (credits[i].url != null) ...[
                      const SizedBox(width: AppSpacing.sm),
                      AppIcon(
                        AboutIcons.open,
                        size: AppIconSize.sm,
                        color: p.textTertiary,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ActionPill extends StatelessWidget {
  const _ActionPill({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final AppIconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SizedBox(
      height: AppSizes.buttonHeight,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          backgroundColor: p.background,
          foregroundColor: p.textPrimary,
          shape: const StadiumBorder(),
          side: BorderSide(color: p.borderStrong, width: AppBorder.thin),
        ),
        onPressed: onTap,
        icon: AppIcon(icon, size: AppIconSize.sm, color: p.textPrimary),
        label: Text(
          label,
          style: context.text.button.copyWith(color: p.textPrimary),
        ),
      ),
    );
  }
}

/// MADE WITH [heart] — © 2026 sparky.
class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.xs,
      children: [
        Text(AboutStrings.madeWith, style: context.text.caption),
        AppIcon(
          AboutIcons.heart,
          size: AppIconSize.xs,
          color: p.accent,
          semanticLabel: AboutStrings.love,
        ),
        Text(AboutStrings.footerRest, style: context.text.caption),
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
