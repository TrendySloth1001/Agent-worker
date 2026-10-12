import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/suggest.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../data/chat_message.dart';
import '../chat_actions.dart';

/// Follow-up prompts under the newest reply. Fresh ones show for a few
/// seconds, then fold into a small "N SUGGESTIONS" pill that opens them
/// again; replies loaded from history start folded. Tap sends one; long-press
/// puts it in the composer to edit. Hidden on older replies and while sending.
class SuggestionChips extends StatefulWidget {
  const SuggestionChips({super.key, required this.message});

  final ChatMessage message;

  /// The saved follow-ups of [message] (empty when it has none).
  static List<String> itemsOf(ChatMessage message) => [
    for (final s
        in message.meta[SuggestConfig.followUpKey] as List? ?? const [])
      if (s is String && s.trim().isNotEmpty) s.trim(),
  ];

  @override
  State<SuggestionChips> createState() => _SuggestionChipsState();
}

class _SuggestionChipsState extends State<SuggestionChips> {
  /// Follow-ups that were already on the reply when it first showed came
  /// from history: they start folded.
  late bool _hadItemsAtStart = SuggestionChips.itemsOf(
    widget.message,
  ).isNotEmpty;
  bool _open = false;
  bool _touching = false;
  Timer? _timer;

  @override
  void didUpdateWidget(SuggestionChips old) {
    super.didUpdateWidget(old);
    final items = SuggestionChips.itemsOf(widget.message);
    if (items.isEmpty) {
      _hadItemsAtStart = false;
    } else if (!_hadItemsAtStart && !_open && _timer == null) {
      // Just arrived for the reply that finished streaming: show them.
      _hadItemsAtStart = true;
      _open = true;
      _armTimer();
    }
  }

  void _armTimer() {
    _timer?.cancel();
    _timer = Timer(SuggestConfig.followUpsVisible, () {
      if (!mounted || _touching) return;
      setState(() => _open = false);
    });
  }

  void _toggle() {
    Haptics.tap();
    _timer?.cancel();
    setState(() => _open = !_open);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final actions = ChatActions.of(context);
    final items = SuggestionChips.itemsOf(widget.message);
    if (actions == null ||
        actions.sending ||
        !identical(actions.latest, widget.message) ||
        items.isEmpty) {
      return const SizedBox.shrink();
    }
    final reduce = MediaQuery.of(context).disableAnimations;
    final duration = reduce ? Duration.zero : AppDurations.normal;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Semantics(
        label: SuggestStrings.followUps,
        child: AnimatedSize(
          duration: duration,
          curve: Curves.easeOutCubic,
          alignment: Alignment.topLeft,
          child: AnimatedSwitcher(
            duration: duration,
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.topLeft,
              children: [...previous, ?current],
            ),
            child: _open
                ? Listener(
                    key: const ValueKey('open'),
                    // Never fold while the user is reaching for a chip.
                    onPointerDown: (_) {
                      _touching = true;
                      _timer?.cancel();
                    },
                    onPointerUp: (_) => _touching = false,
                    onPointerCancel: (_) => _touching = false,
                    child: _OpenList(
                      items: items,
                      actions: actions,
                      onCollapse: _toggle,
                    ),
                  )
                : _FoldedPill(
                    key: const ValueKey('folded'),
                    count: items.length,
                    onTap: _toggle,
                  ),
          ),
        ),
      ),
    );
  }
}

class _OpenList extends StatelessWidget {
  const _OpenList({
    required this.items,
    required this.actions,
    required this.onCollapse,
  });

  final List<String> items;
  final ChatActions actions;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final text in items)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: PromptChip(
              label: text,
              dense: true,
              onTap: () {
                Haptics.tap();
                actions.send(text);
              },
              onLongPress: actions.edit == null
                  ? null
                  : () {
                      Haptics.tick();
                      actions.edit!(text);
                    },
            ),
          ),
        _FoldedPill(count: items.length, open: true, onTap: onCollapse),
      ],
    );
  }
}

/// "✦ 3 SUGGESTIONS ⌄": the folded follow-ups (or the fold control).
class _FoldedPill extends StatelessWidget {
  const _FoldedPill({
    super.key,
    required this.count,
    required this.onTap,
    this.open = false,
  });

  final int count;
  final VoidCallback onTap;
  final bool open;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final shape = BorderRadius.circular(AppRadius.pill);
    return Semantics(
      button: true,
      expanded: open,
      child: Material(
        color: Colors.transparent,
        borderRadius: shape,
        child: InkWell(
          borderRadius: shape,
          onTap: onTap,
          child: Container(
            height: SuggestSizes.pillHeight,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            decoration: BoxDecoration(
              borderRadius: shape,
              border: Border.all(color: p.border, width: AppBorder.thin),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(
                  SuggestIcons.followUps,
                  size: SuggestSizes.pillIcon,
                  color: p.accent,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  SuggestStrings.collapsed(count),
                  style: context.text.caption.copyWith(color: p.textSecondary),
                ),
                const SizedBox(width: AppSpacing.xs),
                AppIcon(
                  open ? SuggestIcons.collapse : SuggestIcons.expand,
                  size: SuggestSizes.pillIcon,
                  color: p.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Outlined pill with a prompt; shared by follow-ups and starter prompts.
/// [dense] is the one-line follow-up variant.
class PromptChip extends StatelessWidget {
  const PromptChip({
    super.key,
    required this.label,
    required this.onTap,
    this.onLongPress,
    this.dense = false,
  });

  final String label;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final shape = BorderRadius.circular(AppRadius.pill);
    return Semantics(
      button: true,
      child: Material(
        color: p.surface,
        borderRadius: shape,
        child: InkWell(
          borderRadius: shape,
          onTap: onTap,
          onLongPress: onLongPress,
          child: Container(
            constraints: BoxConstraints(
              minHeight: dense
                  ? SuggestSizes.denseChipHeight
                  : SuggestSizes.chipHeight,
              maxWidth: SuggestSizes.chipMaxWidth,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            alignment: dense ? Alignment.centerLeft : Alignment.center,
            decoration: BoxDecoration(
              borderRadius: shape,
              border: Border.all(color: p.borderStrong, width: AppBorder.thin),
            ),
            child: Text(
              label,
              maxLines: dense ? 1 : null,
              overflow: dense ? TextOverflow.ellipsis : null,
              style: context.text.bodySmall.copyWith(color: p.textPrimary),
            ),
          ),
        ),
      ),
    );
  }
}
