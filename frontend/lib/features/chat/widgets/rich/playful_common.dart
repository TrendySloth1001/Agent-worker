import 'package:flutter/material.dart';

import '../../../../core/constants/app_icons.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/rich_cards.dart';
import '../../../../core/constants/widget_playful.dart';
import '../../../../core/haptics.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../chat_actions.dart';
import 'rich_frame.dart';

/// Raw-source card shown when a playful widget cannot parse its source.
class PlayfulFallback extends StatelessWidget {
  const PlayfulFallback({super.key, required this.title, required this.source});

  final String title, source;

  @override
  Widget build(BuildContext context) {
    return RichCard(
      title: title,
      child: Padding(
        padding: const EdgeInsets.all(PlayfulSizes.pad),
        child: Text(
          source,
          style: context.text.label.copyWith(
            color: context.palette.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// Splits a `key: value` line; null when it has no key.
(String, String)? playfulKeyValue(String line) {
  final idx = line.indexOf(':');
  if (idx <= 0) return null;
  return (
    line.substring(0, idx).trim().toLowerCase(),
    line.substring(idx + 1).trim(),
  );
}

/// Non-empty trimmed lines of [src].
List<String> playfulLines(String src) => [
  for (final l in src.replaceAll('\r\n', '\n').split('\n'))
    if (l.trim().isNotEmpty) l.trim(),
];

/// Stable (cross-run) hash used to seed shuffles.
int playfulSeed(String s) {
  var h = 17;
  for (final c in s.codeUnits) {
    h = (h * 31 + c) & 0x3fffffff;
  }
  return h;
}

/// True when this reply is the last one in the chat and a send is possible.
bool playfulCanSend(BuildContext context) {
  final actions = ChatActions.of(context);
  final reply = ReplyScope.of(context);
  return actions != null &&
      reply != null &&
      identical(reply, actions.latest) &&
      !actions.sending;
}

/// Sends [text] as the next user message when allowed. Returns success.
bool playfulSend(BuildContext context, String text) {
  if (!playfulCanSend(context)) return false;
  Haptics.send();
  ChatActions.of(context)!.send(text);
  return true;
}

/// Big dot-matrix figure; scales down instead of overflowing.
class DotNumber extends StatelessWidget {
  const DotNumber(
    this.text, {
    super.key,
    this.size = PlayfulSizes.bigNumberFont,
    this.color,
    this.align = Alignment.centerLeft,
  });

  final String text;
  final double size;
  final Color? color;
  final Alignment align;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: align,
      child: Text(
        text,
        maxLines: 1,
        style: context.text.headline.copyWith(
          fontSize: size,
          color: color ?? context.palette.textPrimary,
          height: 1.0,
        ),
      ),
    );
  }
}

/// 2px progress bar with an accent fill.
class PlayfulBar extends StatelessWidget {
  const PlayfulBar({super.key, required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SizedBox(
      height: PlayfulSizes.barHeight,
      child: LayoutBuilder(
        builder: (context, c) => Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: p.border)),
            AnimatedContainer(
              duration: PlayfulDurations.bar,
              width: c.maxWidth * value.clamp(0.0, 1.0),
              color: p.accent,
            ),
          ],
        ),
      ),
    );
  }
}

/// Mono caps button: filled accent (primary) or 1px outline.
class PlayfulButton extends StatelessWidget {
  const PlayfulButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.primary = false,
    this.enabled = true,
    this.expand = false,
  });

  final String label;
  final VoidCallback onTap;
  final AppIconData? icon;
  final bool primary, enabled, expand;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fg = primary ? p.textInverse : p.textPrimary;
    final child = Container(
      height: PlayfulSizes.btnHeight,
      padding: EdgeInsets.symmetric(
        horizontal: label.isEmpty ? 0 : AppSpacing.md,
      ),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: primary ? p.accent : null,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: primary
            ? null
            : Border.all(color: p.borderStrong, width: AppBorder.thin),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            AppIcon(icon!, size: AppIconSize.sm, color: fg),
            if (label.isNotEmpty) const SizedBox(width: AppSpacing.xs),
          ],
          if (label.isNotEmpty)
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.caption.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
    return Opacity(
      opacity: enabled ? 1 : RichSizes.disabledAlpha,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled
            ? () {
                Haptics.tap();
                onTap();
              }
            : null,
        child: child,
      ),
    );
  }
}

/// Small mono caps stat, e.g. `STREAK 3`.
class PlayfulTag extends StatelessWidget {
  const PlayfulTag(this.text, {super.key, this.accent = false, this.icon});

  final String text;
  final bool accent;
  final AppIconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = accent ? p.accent : p.textTertiary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          AppIcon(icon!, size: AppIconSize.xs, color: color),
          const SizedBox(width: AppSpacing.xs),
        ],
        Text(text, style: context.text.caption.copyWith(color: color)),
      ],
    );
  }
}
