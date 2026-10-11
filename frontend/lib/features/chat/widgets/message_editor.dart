import 'package:flutter/material.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/share_export.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../data/chat_message.dart';
import '../../../data/files_api.dart';
import 'attachment_views.dart';

/// Inline editor that takes the place of a user bubble: the text and its
/// files, CANCEL and SEND. Files can be removed, not added.
class MessageEditor extends StatefulWidget {
  const MessageEditor({
    super.key,
    required this.message,
    required this.onCancel,
    required this.onSend,
  });

  final ChatMessage message;
  final VoidCallback onCancel;
  final void Function(String text, List<FileInfo> attachments) onSend;

  @override
  State<MessageEditor> createState() => _MessageEditorState();
}

class _MessageEditorState extends State<MessageEditor> {
  late final _controller = TextEditingController(text: widget.message.content);
  late final List<FileInfo> _files = List.of(widget.message.attachments);

  bool get _canSend => _controller.text.trim().isNotEmpty || _files.isNotEmpty;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    if (!_canSend) return;
    Haptics.send();
    widget.onSend(_controller.text, _files);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: p.borderStrong, width: AppBorder.thin),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(EditStrings.editing, style: t.caption),
          if (_files.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final f in _files)
                  _FileChip(
                    file: f,
                    onRemove: () => setState(() => _files.remove(f)),
                  ),
              ],
            ),
          ],
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 1,
            maxLines: ShareSizes.editorMaxLines,
            style: t.body,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: EditStrings.inputHint,
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _Button(
                label: EditStrings.cancel,
                onTap: () {
                  Haptics.tap();
                  widget.onCancel();
                },
              ),
              const SizedBox(width: AppSpacing.sm),
              _Button(
                label: EditStrings.send,
                filled: true,
                onTap: _canSend ? _send : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Bordered pill; [filled] for the main action.
class _Button extends StatelessWidget {
  const _Button({required this.label, this.onTap, this.filled = false});

  final String label;
  final VoidCallback? onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final enabled = onTap != null;
    final fill = filled && enabled ? p.textPrimary : Colors.transparent;
    final color = !enabled
        ? p.textTertiary
        : filled
        ? p.textInverse
        : p.textPrimary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppDurations.fast,
        height: ShareSizes.editorButtonHeight,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: enabled
                ? (filled ? p.textPrimary : p.borderStrong)
                : p.border,
            width: AppBorder.thin,
          ),
        ),
        child: Text(label, style: context.text.caption.copyWith(color: color)),
      ),
    );
  }
}

/// A kept file: icon, name and a remove cross.
class _FileChip extends StatelessWidget {
  const _FileChip({required this.file, required this.onRemove});

  final FileInfo file;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      height: AppSizes.chipHeight,
      constraints: const BoxConstraints(
        maxWidth: ShareSizes.editorChipMaxWidth,
      ),
      padding: const EdgeInsets.only(left: AppSpacing.sm),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: p.border, width: AppBorder.thin),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(
            fileIcon(file.kind),
            size: AppIconSize.xs,
            color: p.textSecondary,
          ),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              file.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.caption.copyWith(color: p.textSecondary),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              Haptics.tap();
              onRemove();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: AppIcon(
                AppIcons.close,
                size: AppIconSize.xs,
                color: p.textSecondary,
                semanticLabel: AppStrings.attachRemove,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
