import 'package:flutter/material.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/connections.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import '../../chat/widgets/github/github_connect_card.dart';
import '../../connections/connections_controller.dart';
import 'section_header.dart';

/// Settings → CONNECTIONS: the user's linked accounts. GitHub opens the
/// connect sheet; the others are placeholders for now.
class ConnectionsSection extends StatefulWidget {
  const ConnectionsSection({super.key});

  @override
  State<ConnectionsSection> createState() => _ConnectionsSectionState();
}

class _ConnectionsSectionState extends State<ConnectionsSection> {
  final _c = ConnectionsController.instance;

  @override
  void initState() {
    super.initState();
    _c.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: p.border, width: AppBorder.thin),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            _Row(
              icon: ConnectIcons.github,
              label: ConnectStrings.github,
              trailing: _githubTrailing(context),
              onTap: () => showGithubConnectSheet(context),
            ),
            Divider(height: AppBorder.thin, color: p.border),
            const _Row(
              icon: ConnectIcons.googleDrive,
              label: ConnectStrings.googleDrive,
              trailing: MetaChip(ConnectStrings.soon),
            ),
            Divider(height: AppBorder.thin, color: p.border),
            const _Row(
              icon: ConnectIcons.googlePhotos,
              label: ConnectStrings.googlePhotos,
              trailing: MetaChip(ConnectStrings.soon),
            ),
          ],
        ),
      ),
    );
  }

  Widget _githubTrailing(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final g = _c.github;
    if (g != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusDot(color: p.textPrimary),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              ConnectStrings.account(g.login),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.caption.copyWith(color: p.textPrimary),
            ),
          ),
        ],
      );
    }
    return switch (_c.githubPhase) {
      GithubPhase.loading => const SizedBox.shrink(),
      GithubPhase.waiting => const MetaChip(
        ConnectStrings.waiting,
        emphasis: true,
      ),
      GithubPhase.notConfigured when !_c.isOwner => const MetaChip(
        ConnectStrings.unavailable,
      ),
      _ => const MetaChip(ConnectStrings.connect, emphasis: true),
    };
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    required this.trailing,
    this.onTap,
  });

  final AppIconData icon;
  final String label;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final enabled = onTap != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: SizedBox(
            height: AppSizes.rowHeight,
            child: Row(
              children: [
                AppIcon(
                  icon,
                  size: AppIconSize.sm,
                  color: enabled ? p.textPrimary : p.textTertiary,
                ),
                const SizedBox(width: AppSpacing.md),
                Text(
                  label,
                  style: context.text.label.copyWith(
                    color: enabled ? p.textPrimary : p.textTertiary,
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: trailing,
                  ),
                ),
                if (enabled) ...[
                  const SizedBox(width: AppSpacing.sm),
                  AppIcon(
                    ConnectIcons.chevron,
                    size: AppIconSize.xs,
                    color: p.textTertiary,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
