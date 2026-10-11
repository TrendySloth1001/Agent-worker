import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/app_files.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/constants/app_icons.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/icon_label.dart';
import '../../../data/files_api.dart';
import '../attachments_controller.dart';
import 'attachment_bar.dart';

/// Floating capsule with the text field and send button.
class ChatInput extends StatefulWidget {
  const ChatInput({
    super.key,
    required this.onSend,
    required this.onStop,
    required this.isStreaming,
    required this.webSearch,
    required this.knowledge,
    required this.onToggleWebSearch,
    required this.onToggleKnowledge,
    this.roundTable = false,
    this.onToggleRoundTable,
    this.draft,
  });

  final void Function(String text, List<FileInfo> attachments) onSend;
  final VoidCallback onStop;

  /// While true the send button becomes a stop button.
  final bool isStreaming;
  final bool webSearch;
  final bool knowledge;
  final VoidCallback onToggleWebSearch;
  final VoidCallback onToggleKnowledge;

  /// Round Table chip; hidden when [onToggleRoundTable] is null.
  final bool roundTable;
  final VoidCallback? onToggleRoundTable;

  /// Text to place in the field; consumed (reset to null) once applied.
  final ValueNotifier<String?>? draft;

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  final _controller = TextEditingController();
  final _files = AttachmentsController();
  final _picker = ImagePicker();
  bool _waiting = false;

  @override
  void initState() {
    super.initState();
    widget.draft?.addListener(_applyDraft);
  }

  @override
  void didUpdateWidget(ChatInput old) {
    super.didUpdateWidget(old);
    if (old.draft == widget.draft) return;
    old.draft?.removeListener(_applyDraft);
    widget.draft?.addListener(_applyDraft);
  }

  void _applyDraft() {
    final draft = widget.draft;
    final text = draft?.value;
    if (draft == null || text == null) return;
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    draft.value = null;
  }

  @override
  void dispose() {
    widget.draft?.removeListener(_applyDraft);
    _controller.dispose();
    _files.dispose();
    super.dispose();
  }

  bool get _canSend => _controller.text.trim().isNotEmpty || _files.hasUploaded;

  Future<void> _submit() async {
    if (widget.isStreaming || _waiting || !_canSend) return;
    final text = _controller.text;
    // Uploads that are still running finish first; the server waits for
    // files that are still processing.
    if (_files.uploading) setState(() => _waiting = true);
    final ready = await _files.settle();
    if (!mounted) return;
    setState(() => _waiting = false);
    if (ready == null) {
      Haptics.error();
      _toast(AppStrings.attachFixFailed);
      return;
    }
    if (text.trim().isEmpty && ready.isEmpty) return;
    Haptics.send();
    widget.onSend(text, ready);
    _controller.clear();
    _files.clearSent();
  }

  void _toast(String text) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(text, style: context.text.label)));

  void _report(String? problem) {
    if (problem == null) return;
    Haptics.error();
    _toast(
      problem == 'big' ? AppStrings.attachTooBig : AppStrings.attachUnsupported,
    );
  }

  Future<void> _attach() async {
    Haptics.tap();
    if (_files.isFull) {
      _toast(AppStrings.attachMax);
      return;
    }
    final choice = await showAttachSheet(context);
    if (choice == null || !mounted) return;
    try {
      switch (choice) {
        case AttachChoice.media:
          final free = _files.free;
          final list = free < 2
              ? [?await _picker.pickMedia()]
              : await _picker.pickMultipleMedia(limit: free);
          _addPicked(await _fromX(list));
        case AttachChoice.photo:
          final x = await _picker.pickImage(source: ImageSource.camera);
          if (x != null) _addPicked(await _fromX([x]));
        case AttachChoice.video:
          final x = await _picker.pickVideo(source: ImageSource.camera);
          if (x != null) _addPicked(await _fromX([x]));
        case AttachChoice.document:
          final list = await FilePicker.pickFiles();
          _addPicked([
            for (final f in list)
              if (f.path != null) pickedFile(f.path!, f.name),
          ]);
      }
    } catch (_) {
      if (mounted) {
        Haptics.error();
        _toast(AppStrings.attachUnsupported);
      }
    }
  }

  void _addPicked(List<({String path, String name, int size})> picked) {
    final problem = _files.add(picked);
    if (_files.skipped > 0) {
      Haptics.error();
      _toast(AppStrings.attachSkipped(_files.skipped, AppFiles.maxPerMessage));
    } else {
      _report(problem);
    }
  }

  Future<List<({String path, String name, int size})>> _fromX(
    Iterable<XFile> xs,
  ) async => [
    for (final x in xs) (path: x.path, name: x.name, size: await x.length()),
  ];

  @override
  Widget build(BuildContext context) {
    return Glass(
      radius: AppRadius.lg,
      padding: const EdgeInsets.all(AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AttachmentBar(controller: _files),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _attachButton(context),
              Expanded(
                child: TextField(
                  controller: _controller,
                  minLines: 1,
                  maxLines: 5,
                  style: context.text.body,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: AppStrings.inputHint,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ),
              _actionButton(context),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.xs,
              AppSpacing.sm,
              AppSpacing.xs,
            ),
            child: Row(
              children: [
                _Chip(
                  label: AppStrings.web,
                  icon: AppIcons.web,
                  active: widget.webSearch,
                  onTap: widget.onToggleWebSearch,
                ),
                const SizedBox(width: AppSpacing.sm),
                _Chip(
                  label: AppStrings.kb,
                  icon: AppIcons.knowledge,
                  active: widget.knowledge,
                  onTap: widget.onToggleKnowledge,
                ),
                if (widget.onToggleRoundTable != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  _Chip(
                    label: TableStrings.chip,
                    icon: AppIcons.roundTable,
                    active: widget.roundTable,
                    onTap: widget.onToggleRoundTable!,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _attachButton(BuildContext context) {
    final p = context.palette;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _attach,
      child: SizedBox(
        width: AppSizes.sendButton,
        height: AppSizes.sendButton,
        child: AppIcon(
          AppIcons.attach,
          size: AppIconSize.md,
          semanticLabel: AppStrings.attachTitle,
          color: p.textSecondary,
        ),
      ),
    );
  }

  Widget _actionButton(BuildContext context) {
    final p = context.palette;
    if (widget.isStreaming) {
      return GestureDetector(
        onTap: widget.onStop,
        child: Container(
          width: AppSizes.sendButton,
          height: AppSizes.sendButton,
          decoration: BoxDecoration(shape: BoxShape.circle, color: p.accent),
          child: AppIcon(
            AppIcons.stop,
            size: AppIconSize.md,
            semanticLabel: AppStrings.stop,
            color: p.textInverse,
          ),
        ),
      );
    }
    return ListenableBuilder(
      listenable: Listenable.merge([_controller, _files]),
      builder: (context, _) {
        final active = _canSend || _waiting;
        return GestureDetector(
          onTap: _submit,
          child: AnimatedContainer(
            duration: AppDurations.fast,
            width: AppSizes.sendButton,
            height: AppSizes.sendButton,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? p.textPrimary : p.surfaceHigh,
            ),
            child: AppIcon(
              _waiting ? AppIcons.timer : AppIcons.send,
              size: AppIconSize.lg,
              semanticLabel: AppStrings.send,
              color: active ? p.textInverse : p.textTertiary,
            ),
          ),
        );
      },
    );
  }
}

/// Small toggle pill: filled when on, outlined when off.
class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final String label;
  final AppIconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Haptics.tap();
        onTap();
      },
      child: AnimatedContainer(
        duration: AppDurations.fast,
        height: AppSizes.chipHeight,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.chipHorizontalPadding,
        ),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          color: active ? p.textPrimary : Colors.transparent,
          border: Border.all(
            color: active ? p.textPrimary : p.borderStrong,
            width: AppBorder.thin,
          ),
        ),
        child: IconLabel(
          icon: icon,
          text: label,
          style: context.text.caption,
          color: active ? p.textInverse : p.textSecondary,
        ),
      ),
    );
  }
}

enum AttachChoice { media, photo, video, document }

/// Compact sheet with the ways to add a file.
Future<AttachChoice?> showAttachSheet(BuildContext context) {
  final p = context.palette;
  return showModalBottomSheet<AttachChoice>(
    context: context,
    backgroundColor: p.surface,
    shape: RoundedRectangleBorder(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppRadius.lg),
      ),
      side: BorderSide(color: p.border),
    ),
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (choice, icon, label) in [
            (AttachChoice.media, AppIcons.image, AppStrings.attachMedia),
            (AttachChoice.photo, AppIcons.camera, AppStrings.attachTakePhoto),
            (AttachChoice.video, AppIcons.video, AppStrings.attachRecordVideo),
            (AttachChoice.document, AppIcons.file, AppStrings.attachDocument),
          ])
            InkWell(
              onTap: () {
                Haptics.tap();
                Navigator.pop(sheet, choice);
              },
              child: Container(
                height: AppSizes.sheetOptionHeight,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenPadding,
                ),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: p.border)),
                ),
                child: Row(
                  children: [
                    AppIcon(icon, size: AppIconSize.md, color: p.textSecondary),
                    const SizedBox(width: AppSpacing.md),
                    Text(label, style: sheet.text.label),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
