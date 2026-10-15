import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/constants/app_sizes.dart';
import '../../core/constants/intent_cards.dart';
import '../../core/haptics.dart';
import '../../core/theme/app_palette.dart';
import '../../core/widgets/app_icon.dart';
import '../chat/widgets/markdown/code_block.dart';
import 'intent_card_model.dart';
import 'intent_runner.dart';

/// A ```sparky-card block: place, event, alarm/timer, contact, product,
/// ride, food, travel or UPI. One layout, shaped per type (icon, rows,
/// chips, the UPI notice). Every button is an intent the phone runs only
/// when it is tapped; installed apps are offered first, otherwise a link
/// opens in the browser.
class IntentCard extends StatefulWidget {
  const IntentCard({super.key, required this.source, this.runner});

  final String source;

  /// Defaults to [IntentRunner.instance].
  final IntentRunner? runner;

  @override
  State<IntentCard> createState() => _IntentCardState();
}

class _IntentCardState extends State<IntentCard> {
  late IntentCardSpec? _spec = IntentCardSpec.parse(widget.source);
  Set<String> _installed = const {};
  String? _message;

  IntentRunner get _runner => widget.runner ?? IntentRunner.instance;

  @override
  void initState() {
    super.initState();
    _checkInstalled();
  }

  @override
  void didUpdateWidget(IntentCard old) {
    super.didUpdateWidget(old);
    if (old.source != widget.source) {
      _spec = IntentCardSpec.parse(widget.source);
      _message = null;
      _checkInstalled();
    }
  }

  Future<void> _checkInstalled() async {
    final spec = _spec;
    if (spec == null) return;
    final packages = <String>{
      for (final a in spec.actions)
        if (a.group != null && a.intent.package != null) a.intent.package!,
    }.toList();
    if (packages.isEmpty) return;
    final source = widget.source;
    final found = await InstalledCardApps.check(
      packages,
      runner: widget.runner,
    );
    if (mounted && widget.source == source) setState(() => _installed = found);
  }

  Future<void> _tap(CardButton b) async {
    Haptics.tap();
    final outcome = await _runner.run(b.intent);
    if (!mounted) return;
    switch (outcome) {
      case IntentOutcome.done:
        setState(() => _message = null);
      case IntentOutcome.unavailable:
        Haptics.error();
        setState(() => _message = IntentCardStrings.unavailable);
      case IntentOutcome.failed:
        Haptics.error();
        setState(() => _message = IntentCardStrings.failed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final spec = _spec;
    // Not a finished card: show what was written.
    if (spec == null) {
      return CodeBlock(code: widget.source, language: IntentCardWire.fence);
    }
    final p = context.palette;
    final t = context.text;
    final buttons = spec.ordered(_installed);
    final full = [
      for (final b in buttons)
        if (!b.chip) b,
    ];
    final chips = [
      for (final b in buttons)
        if (b.chip) b,
    ];
    final logo = switch (spec.type) {
      IntentCardType.place => 'maps',
      IntentCardType.event => 'calendar',
      _ => null,
    };
    return Semantics(
      container: true,
      label: '${spec.type.kicker}. ${spec.title}',
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: p.isDark ? p.surfaceHigh : p.surfaceRaised,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: p.border, width: AppBorder.thin),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: IntentCardSizes.iconCircle,
                  height: IntentCardSizes.iconCircle,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: logo != null ? p.surface : p.accent,
                    border: logo != null
                        ? Border.all(color: p.border, width: AppBorder.thin)
                        : null,
                  ),
                  child: Center(
                    child: AppIcon(
                      logo != null
                          ? IntentCardIcons.forApp(logo)
                          : spec.type.icon,
                      size: logo != null ? AppIconSize.lg : AppIconSize.md,
                      color: logo != null ? p.textPrimary : p.textInverse,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(spec.type.kicker, style: t.caption),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        spec.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.title,
                      ),
                      if (spec.subtitle != null) ...[
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          spec.subtitle!,
                          maxLines: IntentCardSizes.maxRowLines,
                          overflow: TextOverflow.ellipsis,
                          style: t.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (spec.rows.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              for (final (label, value) in spec.rows)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: IntentCardSizes.labelWidth,
                        child: Text(label.toUpperCase(), style: t.caption),
                      ),
                      Expanded(
                        child: Text(
                          value,
                          maxLines: IntentCardSizes.maxRowLines,
                          overflow: TextOverflow.ellipsis,
                          style: t.bodySmall.copyWith(color: p.textPrimary),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            if (spec.notice != null) ...[
              const SizedBox(height: AppSpacing.md),
              _Notice(
                text: spec.notice!,
                strong: spec.type == IntentCardType.upi,
              ),
            ],
            if (chips.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final b in chips)
                    _ActionButton(
                      button: b,
                      card: spec.title,
                      onTap: () => _tap(b),
                    ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final b in full)
                  _ActionButton(
                    button: b,
                    card: spec.title,
                    onTap: () => _tap(b),
                  ),
              ],
            ),
            if (_message != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_message!, style: t.bodySmall.copyWith(color: p.error)),
            ],
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.strong});

  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: strong ? p.borderStrong : p.border,
          width: AppBorder.thin,
        ),
        color: strong ? p.surface : null,
      ),
      child: Text(
        text,
        style: context.text.bodySmall.copyWith(
          color: strong ? p.textPrimary : p.textSecondary,
          fontWeight: strong ? FontWeight.w600 : null,
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.button,
    required this.card,
    required this.onTap,
  });

  final CardButton button;
  final String card;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final filled = button.primary;
    final fg = filled ? p.textInverse : p.textPrimary;
    final isLogo = IntentCardIcons.isLogo(button.app);
    final iconSize = button.chip
        ? IntentCardSizes.chipLogo
        : IntentCardSizes.buttonLogo;
    final icon = AppIcon(
      IntentCardIcons.forApp(button.app),
      size: iconSize,
      color: isLogo ? p.textPrimary : fg,
    );
    return Semantics(
      button: true,
      label: IntentCardStrings.button(button.label, card),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: button.chip
              ? IntentCardSizes.chipHeight
              : IntentCardSizes.buttonHeight,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          decoration: BoxDecoration(
            color: filled ? p.textPrimary : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: filled ? p.textPrimary : p.borderStrong,
              width: AppBorder.thin,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // A brand logo keeps its colors on a plain disc, so it reads on
              // the dark filled button too.
              if (isLogo)
                Container(
                  width: iconSize + AppSpacing.sm,
                  height: iconSize + AppSpacing.sm,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: p.isDark ? p.textPrimary : p.surface,
                  ),
                  child: Center(child: icon),
                )
              else
                icon,
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  button.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodySmall.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
