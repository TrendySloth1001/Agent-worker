import 'package:flutter/material.dart';

import '../../../core/app_scope.dart';
import '../../../data/chat_api.dart';
import '../../../data/knowledge_api.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/docs.dart';
import '../../../core/constants/share_export.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/appear.dart';
import '../../../core/widgets/copy_action.dart';
import '../../../data/chat_message.dart';
import '../../../data/doc_models.dart';
import '../../docs/doc_card.dart';
import '../chat_actions.dart';
import '../share/reply_share.dart';
import 'markdown/app_markdown.dart';
import 'message_sheet.dart';
import 'attachment_views.dart';
import 'image_strip.dart';
import 'memory_chip.dart';
import 'source_chips.dart';
import 'suggestion_chips.dart';
import 'thinking_indicator.dart';
import 'round_table_header.dart';
import 'round_table_panel.dart';
import '../../../core/constants/app_icons.dart';
import '../../../core/widgets/app_icon.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.label,
    this.onRegenerate,
    this.question,
    this.conversationId,
    this.onFork,
    this.onAnswerFast,
    this.onNotify,
    this.onEdit,
    this.onTurnIntoDoc,
  });

  final ChatMessage message;

  /// Live Round Table: answer with one model instead / notify when done.
  final VoidCallback? onAnswerFast;
  final VoidCallback? onNotify;

  /// Shown above AI replies: the model's name.
  final String label;

  /// Set only on the last reply, when it is not streaming.
  final VoidCallback? onRegenerate;

  /// The user message that prompted this reply, saved with it as a note.
  final String? question;
  final String? conversationId;

  /// Reply: fork up to and including it. User message: fork from just
  /// before it (long-press menu). Null while sending.
  final VoidCallback? onFork;

  /// User message: edit it in place (long-press menu). Null while sending.
  final VoidCallback? onEdit;

  /// Reply: write a document from it (long-press menu, long replies).
  final VoidCallback? onTurnIntoDoc;

  @override
  Widget build(BuildContext context) {
    return Appear(
      child: message.role == Role.user ? _user(context) : _assistant(context),
    );
  }

  Widget _user(BuildContext context) {
    final maxWidth =
        MediaQuery.sizeOf(context).width * AppSizes.maxBubbleWidthFactor;
    final box = Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: context.palette.userBubble,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Text(
        message.content,
        style: context.text.body.copyWith(
          color: context.palette.userBubbleText,
        ),
      ),
    );
    final bubble = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () => showUserMessageActions(
        context,
        text: message.content,
        onForkHere: onFork,
        onEdit: onEdit,
      ),
      child: box,
    );
    final hasText = message.content.trim().isNotEmpty;
    if (message.attachments.isEmpty) {
      return Align(alignment: Alignment.centerRight, child: bubble);
    }
    return Align(
      alignment: Alignment.centerRight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          MessageAttachments(files: message.attachments),
          if (hasText) ...[const SizedBox(height: AppSizes.attachGap), bubble],
        ],
      ),
    );
  }

  String _statusLabel() => switch (message.status) {
    'queued' => AppStrings.queued,
    'searching' => AppStrings.searchingWeb,
    'retrieving' => AppStrings.retrieving,
    'round_table' => TableStrings.status,
    _ => AppStrings.thinking,
  };

  Widget _assistant(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final waiting = message.isStreaming && message.content.isEmpty;
    final doc = message.isError ? null : DocLink.fromMeta(message.meta);
    if (doc != null) return _docReply(context, doc);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: AppSizes.dot,
              height: AppSizes.dot,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: message.isError ? p.accent : p.textPrimary,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(label.toUpperCase(), style: t.caption),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (message.table != null && !message.isError) ...[
          RoundTableHeader(table: message.table!, citations: message.citations),
          const SizedBox(height: AppSpacing.md),
        ],
        if (message.isError)
          Text(message.content, style: t.body.copyWith(color: p.accent))
        else if (waiting && message.tablePhase != null)
          RoundTablePanel(
            message: message,
            onAnswerFast: onAnswerFast,
            onNotify: onNotify,
          )
        else if (waiting)
          ThinkingIndicator(label: _statusLabel())
        else
          GestureDetector(
            onLongPress:
                message.isStreaming ||
                    message.content.length < DocConfig.turnIntoDocMinChars
                ? null
                : () => showReplyActions(
                    context,
                    text: message.content,
                    onTurnIntoDoc: onTurnIntoDoc,
                  ),
            child: ReplyScope(
              message: message,
              child: AppMarkdown(
                data: message.content,
                citations: message.citations,
                evidence: message.evidence,
                streaming: message.isStreaming,
              ),
            ),
          ),
        if (message.error != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(message.error!, style: t.caption.copyWith(color: p.accent)),
        ],
        if (message.notice != null && !message.isError) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(message.notice!, style: t.caption),
        ],
        if (message.memoryOps.isNotEmpty && !message.isError) ...[
          const SizedBox(height: AppSpacing.sm),
          MemoryChip(ops: message.memoryOps),
        ],
        if (message.images.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          ImageStrip(images: message.images),
        ],
        if (message.citations.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          SourceChips(citations: message.citations, used: message.usedIds),
        ],
        if (!message.isStreaming && !message.isError)
          SuggestionChips(message: message),
        if (!message.isStreaming) ...[
          const SizedBox(height: AppSpacing.sm),
          // Wraps on narrow screens rather than overflowing.
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: AppSpacing.xs,
            children: [
              if (!message.isError) ...[
                CopyAction(text: message.content),
                const SizedBox(width: AppSpacing.lg),
                _TextAction(
                  icon: ShareIcons.share,
                  label: ShareStrings.share,
                  onTap: () =>
                      showReplyShare(context, message: message, model: label),
                ),
                const SizedBox(width: AppSpacing.lg),
                _SaveAction(
                  content: message.content,
                  question: question,
                  conversationId: conversationId,
                ),
                const SizedBox(width: AppSpacing.lg),
                if (onFork != null) ...[
                  _TextAction(
                    icon: AppIcons.fork,
                    label: LineageStrings.fork,
                    onTap: onFork!,
                  ),
                  const SizedBox(width: AppSpacing.lg),
                ],
              ],
              if (onRegenerate != null)
                _TextAction(
                  icon: AppIcons.regenerate,
                  label: message.isError
                      ? AppStrings.retry
                      : AppStrings.regenerate,
                  onTap: onRegenerate!,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

extension on MessageBubble {
  /// A reply that is a document: the model line, then the live card.
  Widget _docReply(BuildContext context, DocLink doc) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: AppSizes.dot,
              height: AppSizes.dot,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: p.textPrimary,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(DocStrings.card, style: context.text.caption),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        DocCard(link: doc),
      ],
    );
  }
}

class _TextAction extends StatelessWidget {
  const _TextAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final AppIconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = context.palette.textTertiary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Haptics.tap();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(icon, size: AppIconSize.sm, color: color),
            const SizedBox(width: AppSpacing.xs),
            Text(label, style: context.text.caption.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}

enum _SaveState { idle, saving, saved }

/// SAVE -> SAVING -> SAVED: stores the reply as a knowledge note.
class _SaveAction extends StatefulWidget {
  const _SaveAction({
    required this.content,
    this.question,
    this.conversationId,
  });

  final String content;
  final String? question;
  final String? conversationId;

  @override
  State<_SaveAction> createState() => _SaveActionState();
}

class _SaveActionState extends State<_SaveAction> {
  _SaveState _state = _SaveState.idle;

  Future<void> _save() async {
    if (_state != _SaveState.idle) return;
    Haptics.tap();
    final api = KnowledgeApi(AppScope.of(context).baseUrl);
    setState(() => _state = _SaveState.saving);
    try {
      await api.addNote(
        content: widget.content,
        question: widget.question,
        conversationId: widget.conversationId,
      );
      Haptics.received();
      if (mounted) setState(() => _state = _SaveState.saved);
    } on ApiException catch (e) {
      // A duplicate means the reply is already in the knowledge base.
      if (e.status == 409) {
        if (mounted) setState(() => _state = _SaveState.saved);
        return;
      }
      _fail(e.message);
    } catch (_) {
      _fail(AppStrings.errorGeneric);
    }
  }

  void _fail(String message) {
    Haptics.error();
    if (!mounted) return;
    setState(() => _state = _SaveState.idle);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: context.palette.surfaceHigh,
        content: Text(message, style: context.text.label),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final saved = _state == _SaveState.saved;
    final color = saved ? context.palette.accent : context.palette.textTertiary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _save,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(
              saved ? AppIcons.check : AppIcons.knowledge,
              size: AppIconSize.sm,
              color: color,
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(switch (_state) {
              _SaveState.idle => AppStrings.saveToKnowledge,
              _SaveState.saving => AppStrings.saving,
              _SaveState.saved => AppStrings.saved,
            }, style: context.text.caption.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}
