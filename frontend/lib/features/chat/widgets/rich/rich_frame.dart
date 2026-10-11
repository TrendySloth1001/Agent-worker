import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_icons.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/constants/rich_cards.dart';
import '../../../../core/haptics.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/widgets/app_icon.dart';
import '../markdown/inline_icon.dart';

/// Card shell shared by the rich blocks: rounded 1px border, mono header bar,
/// optional action row along the bottom.
class RichCard extends StatelessWidget {
  const RichCard({
    super.key,
    required this.title,
    this.leading,
    this.trailing,
    required this.child,
    this.actions = const [],
  });

  final String title;
  final Widget? leading;
  final Widget? trailing;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: p.codeBackground,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: p.border, width: AppBorder.thin),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: AppSizes.codeHeaderHeight,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: p.border)),
            ),
            child: Row(
              children: [
                if (leading != null) ...[
                  leading!,
                  const SizedBox(width: AppSpacing.sm),
                ],
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.caption,
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
          child,
          if (actions.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: p.border)),
              ),
              child: Wrap(
                spacing: AppSpacing.lg,
                runSpacing: AppSpacing.xs,
                children: actions,
              ),
            ),
        ],
      ),
    );
  }
}

/// Mono caption action with an icon. Flips to [doneLabel] with an accent
/// check after a successful tap, like CopyAction.
class RichAction extends StatefulWidget {
  const RichAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.doneLabel,
    this.brandIcon,
    this.enabled = true,
  });

  final AppIconData icon;

  /// Dimmed and ignoring taps when false.
  final bool enabled;

  /// Iconify id of a brand logo (e.g. `logos:google-gmail`) shown in color
  /// instead of [icon].
  final String? brandIcon;
  final String label;
  final String? doneLabel;

  /// Returns true when the action worked (shows the done state).
  final Future<bool> Function() onTap;

  /// Copies [text] to the clipboard.
  factory RichAction.copy({
    Key? key,
    required String text,
    String label = AppStrings.copy,
  }) => RichAction(
    key: key,
    icon: AppIcons.copy,
    label: label,
    doneLabel: AppStrings.copied,
    onTap: () async {
      await Clipboard.setData(ClipboardData(text: text));
      return true;
    },
  );

  /// Opens [uri] in another app; shows a notice if nothing can handle it.
  factory RichAction.open({
    Key? key,
    required AppIconData icon,
    required String label,
    required Uri uri,
    String? brandIcon,
  }) => RichAction(
    key: key,
    icon: icon,
    brandIcon: brandIcon,
    label: label,
    onTap: () async {
      try {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        return false;
      }
    },
  );

  @override
  State<RichAction> createState() => _RichActionState();
}

class _RichActionState extends State<RichAction> {
  bool _done = false;

  Future<void> _run() async {
    Haptics.tap();
    final ok = await widget.onTap();
    if (!mounted) return;
    if (!ok) {
      Haptics.error();
      final p = context.palette;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: p.surfaceHigh,
          content: Text(RichStrings.cantOpen, style: context.text.label),
        ),
      );
      return;
    }
    if (widget.doneLabel == null) return;
    setState(() => _done = true);
    await Future<void>.delayed(AppDurations.copiedFeedback);
    if (mounted) setState(() => _done = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = _done ? p.accent : p.textTertiary;
    return Opacity(
      opacity: widget.enabled ? 1 : RichSizes.disabledAlpha,
      child: GestureDetector(
        onTap: widget.enabled ? _run : null,
        behavior: HitTestBehavior.opaque,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: RichSizes.actionMinTap),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!_done && widget.brandIcon != null)
                InlineIcon(
                  set: widget.brandIcon!.split(':').first,
                  name: widget.brandIcon!.split(':').last,
                  size: AppIconSize.sm,
                )
              else
                AppIcon(
                  _done ? AppIcons.check : widget.icon,
                  size: AppIconSize.sm,
                  color: color,
                ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                _done ? (widget.doneLabel ?? widget.label) : widget.label,
                style: context.text.caption.copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
