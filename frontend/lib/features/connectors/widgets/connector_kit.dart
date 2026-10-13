import 'package:flutter/material.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/connectors.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/m3_kit_extras.dart';
import '../../apps/apps_registry.dart';
import '../../apps/apps_screen.dart';
import '../../../core/constants/brand_logos.dart';
import '../../settings/widgets/settings_kit.dart';
import '../connector_auth.dart';
import '../../../core/widgets/confirm_sheet.dart';
import '../../../core/widgets/illustration.dart';
import '../../../core/constants/confirm_copy.dart';

/// Shared pieces of the Google Drive and Notion screens, in the GitHub
/// screen's design: profile card, permission card, account actions.

/// A connected app's official logo. Given a [color] (e.g. on a filled
/// button) it draws the single-color version of the logo in that color.
class BrandGlyph extends StatelessWidget {
  const BrandGlyph(this.brand, {super.key, required this.size, this.color});

  final AppBrand brand;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurface;
    return AppIcon(
      color == null ? brand.logo : BrandLogos.mono(brand.logo),
      size: size,
      color: c,
    );
  }
}

/// Round avatar: the account picture, else an emoji (Notion workspace) or
/// the brand mark on a tonal circle.
class ConnectorAvatar extends StatelessWidget {
  const ConnectorAvatar({
    super.key,
    required this.url,
    required this.brand,
    this.emoji = '',
    this.size = ConnectorSizes.avatar,
  });

  final String url, emoji;
  final AppBrand brand;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = context.palette;
    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: scheme.surfaceContainerHighest,
        border: Border.all(color: p.border, width: AppBorder.thin),
      ),
      child: Center(
        child: emoji.isNotEmpty && !emoji.startsWith('http')
            ? Text(
                emoji,
                style: const TextStyle(fontSize: ConnectorSizes.workspaceEmoji),
              )
            : BrandGlyph(brand, size: size * ConnectorSizes.avatarGlyphRatio),
      ),
    );
    if (url.isEmpty) return placeholder;
    return ClipOval(
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
        errorBuilder: (_, _, _) => placeholder,
        frameBuilder: (_, child, frame, sync) =>
            frame == null && !sync ? placeholder : child,
      ),
    );
  }
}

/// Avatar | divider | name, detail line and CONNECTED (or RECONNECT) tag.
class ConnectorProfileCard extends StatelessWidget {
  const ConnectorProfileCard({
    super.key,
    required this.avatar,
    required this.name,
    required this.detail,
    this.needsReauth = false,
    this.extra,
  });

  final Widget avatar;
  final String name, detail;
  final bool needsReauth;

  /// A short caption next to the tag (e.g. the workspace).
  final String? extra;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return M3Card(
      child: IntrinsicHeight(
        child: Row(
          children: [
            avatar,
            const SizedBox(width: AppSpacing.lg),
            VerticalDivider(
              width: AppBorder.thin,
              thickness: AppBorder.thin,
              color: scheme.outlineVariant,
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.titleLarge,
                  ),
                  if (detail.isNotEmpty)
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.label.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      M3Tag(
                        needsReauth
                            ? ConnectorStrings.reconnectTag
                            : ConnectorStrings.connected,
                        accent: !needsReauth,
                      ),
                      if (extra != null && extra!.isNotEmpty) ...[
                        const SizedBox(width: AppSpacing.sm),
                        Flexible(
                          child: Text(
                            extra!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.caption.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Let sparky …?" in plain words and one button to the provider, with the
/// running flow's state underneath.
class ConnectorPermissionCard extends StatelessWidget {
  const ConnectorPermissionCard({
    super.key,
    required this.provider,
    required this.brand,
    required this.title,
    required this.body,
    required this.vendor,
    required this.onContinue,
    this.auth,
  });

  final String provider;
  final AppBrand brand;
  final String title, body, vendor;
  final VoidCallback onContinue;

  /// Test seam; defaults to the app's flow.
  final ConnectorAuth? auth;

  @override
  Widget build(BuildContext context) {
    final a = auth ?? ConnectorAuth.instance;
    return ListenableBuilder(
      listenable: a,
      builder: (context, _) {
        final tt = Theme.of(context).textTheme;
        final scheme = Theme.of(context).colorScheme;
        final active = a.activeFor(provider);
        final busy = a.busyFor(provider);
        final status = !active
            ? null
            : switch (a.phase) {
                ConnectorPhase.starting => ConnectorStrings.openingBrowser,
                ConnectorPhase.waiting => ConnectorStrings.waiting,
                ConnectorPhase.finishing => ConnectorStrings.finishing,
                ConnectorPhase.failed => a.error ?? ConnectorStrings.failed,
                ConnectorPhase.idle => null,
              };
        return M3Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppIcon(
                    ConnectorIcons.permission,
                    size: AppIconSize.md,
                    color: scheme.onSurface,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(title, style: tt.titleMedium)),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                body,
                style: tt.bodyMedium!.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: busy
                          ? null
                          : () {
                              Haptics.tap();
                              onContinue();
                            },
                      icon: busy
                          ? const SizedBox.square(
                              dimension: ConnectorSizes.brandOnButton,
                              child: CircularProgressIndicator(
                                strokeWidth: AppBorder.thick,
                              ),
                            )
                          : BrandGlyph(
                              brand,
                              size: ConnectorSizes.brandOnButton,
                              color: scheme.onPrimary,
                            ),
                      label: Text(ConnectorStrings.continueTo(vendor)),
                    ),
                  ),
                ],
              ),
              if (status != null) ...[
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        status,
                        style: tt.bodySmall!.copyWith(
                          color: a.phase == ConnectorPhase.failed
                              ? context.palette.accent
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (a.phase == ConnectorPhase.waiting)
                      TextButton(
                        onPressed: a.reopen,
                        child: const Text(ConnectorStrings.openAgain),
                      ),
                    TextButton(
                      onPressed: a.cancel,
                      child: const Text(ConnectorStrings.cancel),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Open in …, Reconnect, Disconnect (red).
class ConnectorAccountGroup extends StatelessWidget {
  const ConnectorAccountGroup({
    super.key,
    required this.brand,
    required this.openLabel,
    required this.onOpen,
    required this.onReconnect,
    required this.onDisconnect,
  });

  final AppBrand brand;
  final String openLabel;
  final VoidCallback onOpen, onReconnect, onDisconnect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = context.palette;
    return M3Group(
      children: [
        SettingsTile(
          icon: brand.logo,
          leading: AppMark(brand),
          title: openLabel,
          trailing: AppIcon(
            AppIcons.openExternal,
            size: AppIconSize.sm,
            color: scheme.onSurfaceVariant,
          ),
          onTap: onOpen,
        ),
        SettingsTile(
          icon: ConnectorIcons.reconnect,
          title: ConnectorStrings.reconnect,
          summary: ConnectorStrings.reconnectHint,
          onTap: onReconnect,
        ),
        SettingsTile(
          icon: ConnectorIcons.disconnect,
          title: ConnectorStrings.disconnect,
          iconColor: p.accent,
          titleColor: p.accent,
          onTap: onDisconnect,
        ),
      ],
    );
  }
}

/// A slim notice above content: offline, rate limited, access expired.
class ConnectorBanner extends StatelessWidget {
  const ConnectorBanner({
    super.key,
    required this.icon,
    required this.text,
    this.action,
    this.onAction,
  });

  final AppIconData icon;
  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return M3Card(
      high: true,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          AppIcon(icon, size: AppIconSize.sm, color: scheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              text,
              style: tt.bodySmall!.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          if (action != null)
            TextButton(onPressed: onAction, child: Text(action!)),
        ],
      ),
    );
  }
}

/// "Not set up on this server": the server lacks the app's keys.
class ConnectorNotSetUp extends StatelessWidget {
  const ConnectorNotSetUp({super.key});

  @override
  Widget build(BuildContext context) => const M3Empty(
    icon: ConnectorIcons.unavailable,
    title: ConnectorStrings.notSetUp,
    hint: ConnectorStrings.notSetUpBody,
  );
}

/// Leading tile of a file / page row: an icon or emoji on a tonal square.
class ConnectorRowIcon extends StatelessWidget {
  const ConnectorRowIcon({super.key, this.icon, this.emoji, this.imageUrl});

  final AppIconData? icon;
  final String? emoji, imageUrl;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final glyph = AppIcon(
      icon ?? AppIcons.file,
      size: ConnectorSizes.rowGlyph,
      color: scheme.onSurfaceVariant,
    );
    Widget child = glyph;
    if (emoji != null && emoji!.isNotEmpty) {
      child = Text(
        emoji!,
        style: const TextStyle(fontSize: ConnectorSizes.emojiIcon),
      );
    } else if (imageUrl != null && imageUrl!.isNotEmpty) {
      child = Image.network(
        imageUrl!,
        width: ConnectorSizes.rowGlyph,
        height: ConnectorSizes.rowGlyph,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) => glyph,
        frameBuilder: (_, image, frame, sync) =>
            sync || frame != null ? image : glyph,
      );
    }
    return Container(
      width: ConnectorSizes.rowIcon,
      height: ConnectorSizes.rowIcon,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Center(child: child),
    );
  }
}

/// Asks before a destructive account action.
Future<bool> confirmConnector(
  BuildContext context, {
  required String title,
  required String body,
  required String go,
}) async {
  return ConfirmSheet.show(
    context,
    illustration: IllustrationKind.homeRead,
    kicker: ConfirmCopy.kickerDisconnect,
    title: title,
    body: body,
    confirmLabel: go,
    cancelLabel: ConnectorStrings.disconnectKeep,
    destructive: true,
  );
}

void connectorToast(BuildContext context, String text) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(content: Text(text)));
}

/// What a list of "what you get" rows looks like before connecting.
class ConnectorPerks extends StatelessWidget {
  const ConnectorPerks({super.key, required this.title, required this.rows});

  final String title;
  final List<(AppIconData, String, String)> rows;

  @override
  Widget build(BuildContext context) => M3Group(
    title: title,
    children: [
      for (final r in rows)
        SettingsTile(icon: r.$1, title: r.$2, summary: r.$3),
    ],
  );
}

/// "Files sparky can see · 4 ›": opens the full browse page.
class ConnectorSummaryTile extends StatelessWidget {
  const ConnectorSummaryTile({
    super.key,
    required this.icon,
    required this.title,
    required this.count,
    required this.onTap,
  });

  final AppIconData icon;
  final String title;

  /// Null while loading.
  final String? count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SettingsTile(
      icon: icon,
      title: title,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (count != null) M3Tag(count!),
          const SizedBox(width: AppSpacing.sm),
          AppIcon(
            AppIcons.chevronRight,
            size: AppIconSize.sm,
            color: scheme.onSurfaceVariant,
          ),
        ],
      ),
      onTap: () {
        Haptics.tap();
        onTap();
      },
    );
  }
}
