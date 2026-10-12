import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/history.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../data/conversation.dart';
import 'highlighted_text.dart';

/// One conversation in the sidebar: a compact one-line row with the title.
/// The open chat is filled. Small marks show a fork or merge and a reply that
/// is still being written; [time] and the matched preview appear in search.
/// Swipe right pins, swipe left archives; long-press opens the actions.
class ChatRow extends StatelessWidget {
  const ChatRow({
    super.key,
    required this.chat,
    required this.isCurrent,
    required this.onTap,
    required this.onLongPress,
    required this.onPin,
    required this.onArchive,
    this.running = false,
    this.query = '',
    this.time,
    this.renaming = false,
    this.onRename,
    this.onCancelRename,
    this.archivedList = false,
  });

  final ConversationSummary chat;
  final bool isCurrent;
  final bool running;

  /// Search text to highlight; also turns on the preview line.
  final String query;

  /// Right-hand time, only where it adds something (pinned, search).
  final String? time;
  final bool renaming;
  final bool archivedList;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onPin;
  final VoidCallback onArchive;
  final ValueChanged<String>? onRename;
  final VoidCallback? onCancelRename;

  String get _title => chat.title ?? HistoryStrings.untitled;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final body = _body(context);
    if (renaming) return body;
    final archiveLabel = archivedList
        ? HistoryStrings.swipeUnarchive
        : HistoryStrings.swipeArchive;
    final pinLabel = chat.pinned
        ? HistoryStrings.swipeUnpin
        : HistoryStrings.swipePin;
    return Semantics(
      container: true,
      button: true,
      selected: isCurrent,
      label: [
        _title,
        if (chat.pinned) HistoryStrings.pinnedState,
        if (chat.isFork) HistoryStrings.forked,
        if (chat.isMerge) HistoryStrings.merged,
        if (running) HistoryStrings.running,
      ].join(', '),
      onTap: onTap,
      onLongPress: onLongPress,
      customSemanticsActions: {
        if (!archivedList) CustomSemanticsAction(label: pinLabel): onPin,
        CustomSemanticsAction(label: archiveLabel): onArchive,
      },
      excludeSemantics: true,
      child: Dismissible(
        key: ValueKey('chat-${chat.id}'),
        dismissThresholds: const {
          DismissDirection.startToEnd: HistorySizes.swipeThreshold,
          DismissDirection.endToStart: HistorySizes.swipeThreshold,
        },
        confirmDismiss: (direction) async {
          Haptics.tap();
          final toRight = direction == DismissDirection.startToEnd;
          if (toRight && !archivedList) {
            onPin();
          } else {
            onArchive();
          }
          return false;
        },
        background: _SwipeBackground(
          icon: archivedList
              ? AppIcons.unarchive
              : (chat.pinned ? AppIcons.unpin : AppIcons.pin),
          label: archivedList ? archiveLabel : pinLabel,
          alignment: Alignment.centerLeft,
          color: p.surfaceRaised,
        ),
        secondaryBackground: _SwipeBackground(
          icon: archivedList ? AppIcons.unarchive : AppIcons.archive,
          label: archiveLabel,
          alignment: Alignment.centerRight,
          color: p.surfaceRaised,
        ),
        child: body,
      ),
    );
  }

  Widget _body(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final snippet = query.trim().isNotEmpty && chat.preview.isNotEmpty;
    final content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: HistorySizes.rowInset + AppSpacing.xs,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          if (running) ...[
            RunningDot(color: p.accent),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (renaming)
                  _RenameField(
                    initial: chat.title ?? '',
                    onSubmit: (v) => onRename?.call(v),
                    onCancel: () => onCancelRename?.call(),
                  )
                else
                  HighlightedText(
                    _title,
                    query: query,
                    style: t.body.copyWith(height: 1.3),
                  ),
                if (snippet && !renaming)
                  HighlightedText(
                    chat.preview,
                    query: query,
                    style: t.bodySmall.copyWith(
                      color: p.textTertiary,
                      height: 1.25,
                    ),
                  ),
              ],
            ),
          ),
          if (chat.isFork || chat.isMerge) ...[
            const SizedBox(width: AppSpacing.sm),
            AppIcon(
              chat.isFork ? HistoryIcons.fork : HistoryIcons.merge,
              size: AppIconSize.xs,
              color: p.textTertiary,
            ),
          ],
          if (time != null && !renaming) ...[
            const SizedBox(width: AppSpacing.sm),
            Text(time!, style: t.caption.copyWith(color: p.textTertiary)),
          ],
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: HistorySizes.rowInset,
        vertical: AppSpacing.xxs / 2,
      ),
      child: Material(
        color: isCurrent ? p.surfaceHigh : Colors.transparent,
        borderRadius: BorderRadius.circular(HistorySizes.rowRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: renaming ? null : onTap,
          onLongPress: renaming ? null : onLongPress,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: HistorySizes.rowHeight - AppSpacing.xxs,
            ),
            child: Align(alignment: Alignment.centerLeft, child: content),
          ),
        ),
      ),
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({
    required this.icon,
    required this.label,
    required this.alignment,
    required this.color,
  });

  final AppIconData icon;
  final String label;
  final Alignment alignment;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: HistorySizes.rowInset),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      alignment: alignment,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(HistorySizes.rowRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(icon, size: AppIconSize.md, color: p.textPrimary),
          const SizedBox(width: AppSpacing.sm),
          Text(label, style: context.text.caption),
        ],
      ),
    );
  }
}

/// Inline title editor: Enter or the check saves, tapping elsewhere cancels.
class _RenameField extends StatefulWidget {
  const _RenameField({
    required this.initial,
    required this.onSubmit,
    required this.onCancel,
  });

  final String initial;
  final ValueChanged<String> onSubmit;
  final VoidCallback onCancel;

  @override
  State<_RenameField> createState() => _RenameFieldState();
}

class _RenameFieldState extends State<_RenameField> {
  late final _text = TextEditingController(text: widget.initial)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initial.length,
    );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    Haptics.tap();
    widget.onSubmit(_text.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _text,
            autofocus: true,
            maxLength: 120,
            maxLines: 1,
            style: context.text.body.copyWith(height: 1.3),
            textInputAction: TextInputAction.done,
            textCapitalization: TextCapitalization.sentences,
            onSubmitted: (_) => _submit(),
            onTapOutside: (_) => widget.onCancel(),
            decoration: InputDecoration(
              isDense: true,
              counterText: '',
              hintText: HistoryStrings.renameHint,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              contentPadding: const EdgeInsets.symmetric(
                vertical: AppSpacing.sm,
              ),
              hintStyle: context.text.body.copyWith(color: p.textTertiary),
            ),
          ),
        ),
        Semantics(
          button: true,
          label: HistoryStrings.renameSubmit,
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _submit,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: AppIcon(
                AppIcons.check,
                size: AppIconSize.md,
                color: p.accent,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A small red dot that breathes while a reply is being written. Still when
/// the system asks for reduced motion.
class RunningDot extends StatefulWidget {
  const RunningDot({super.key, required this.color});

  final Color color;

  @override
  State<RunningDot> createState() => _RunningDotState();
}

class _RunningDotState extends State<RunningDot>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: HistoryDurations.pulse,
  );
  bool? _reduce;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (reduce == _reduce) return;
    _reduce = reduce;
    if (reduce) {
      _c.stop();
      _c.value = 1;
    } else {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: HistoryStrings.running,
      child: FadeTransition(
        opacity: Tween(begin: 0.35, end: 1.0).animate(_c),
        child: Container(
          width: HistorySizes.runningDot,
          height: HistorySizes.runningDot,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color,
          ),
        ),
      ),
    );
  }
}
