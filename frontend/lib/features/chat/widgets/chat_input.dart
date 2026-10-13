import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/docs.dart';
import '../../../core/constants/smart_toggles.dart';
import '../../../core/constants/suggest.dart';
import '../../../core/constants/voice.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/constants/app_icons.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/m3_kit_extras.dart';
import '../../settings/widgets/settings_kit.dart';
import '../../../data/chat_event.dart';
import '../../../data/files_api.dart';
import '../../../data/suggest_api.dart';
import '../attach_picker.dart';
import '../attachments_controller.dart';
import '../autocomplete/autocomplete_bar.dart';
import '../autocomplete/autocomplete_controller.dart';
import '../autocomplete/local_words.dart';
import '../voice/voice_controller.dart';
import '../voice/voice_permission.dart';
import '../voice/voice_fix_field.dart';
import '../voice/voice_strip.dart';
import 'attachment_bar.dart';
import 'smart_chip.dart';
import 'suggest_prompt.dart';

/// Floating capsule with the text field and send button.
class ChatInput extends StatefulWidget {
  const ChatInput({
    super.key,
    required this.onSend,
    required this.onStop,
    required this.isStreaming,
    this.webMode = WebMode.auto,
    required this.knowledge,
    required this.onToggleWebSearch,
    required this.onToggleKnowledge,
    this.roundTable = false,
    this.onToggleRoundTable,
    this.draft,
    this.doc = false,
    this.onToggleDoc,
    this.docLength = DocConfig.defaultLength,
    this.onDocLength,
    this.onSendAsDoc,
    this.autocomplete = false,
    this.conversationId,
    this.voice,
    this.sendVoiceAutomatically = false,
    this.suggestion,
    this.onAcceptSuggestion,
    this.onDismissSuggestion,
  });

  final void Function(String text, List<FileInfo> attachments) onSend;
  final VoidCallback onStop;

  /// While true the send button becomes a stop button.
  final bool isStreaming;

  /// WEB chip state; tapping [onToggleWebSearch] steps to the next one.
  final WebMode webMode;
  final bool knowledge;
  final VoidCallback onToggleWebSearch;
  final VoidCallback onToggleKnowledge;

  /// Round Table chip; hidden when [onToggleRoundTable] is null.
  final bool roundTable;
  final VoidCallback? onToggleRoundTable;

  /// Text to place in the field; consumed (reset to null) once applied.
  final ValueNotifier<String?>? draft;

  /// DOC chip (long-form document); hidden when [onToggleDoc] is null.
  final bool doc;
  final VoidCallback? onToggleDoc;

  /// Document length while DOC is on, and its picker.
  final String docLength;
  final ValueChanged<String>? onDocLength;

  /// Sends the text as a document once (the WRITE AS DOCUMENT? hint).
  final void Function(String text, List<FileInfo> attachments)? onSendAsDoc;

  /// Ghost-text completion and next-word chips (the settings toggle).
  final bool autocomplete;

  /// The open chat, as context for completions.
  final String? conversationId;

  /// Dictation; the mic button shows while the field is empty. Null hides it.
  final VoiceController? voice;

  /// Send as soon as dictation finishes (the settings toggle).
  final bool sendVoiceAutomatically;

  /// A knowledge-base or Doc suggestion from the server, shown above the
  /// composer with its two actions.
  final SuggestToggleEvent? suggestion;
  final VoidCallback? onAcceptSuggestion;
  final VoidCallback? onDismissSuggestion;

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  final _controller = VoiceFixTextController();
  final _files = AttachmentsController();
  final _picker = AttachPicker();
  bool _waiting = false;

  /// Text the user dismissed the document hint for.
  String? _hintDismissed;

  AutocompleteController? _auto;
  SharedPreferences? _prefs;

  /// True while dictating or waiting for the transcript.
  final _voiceOn = ValueNotifier<bool>(false);

  /// Text already in the field when dictation started (with a trailing space).
  String _voiceBase = '';
  bool _holding = false, _slidingOut = false, _starting = false;
  bool _releaseAfterStart = false;

  @override
  void initState() {
    super.initState();
    widget.voice?.addListener(_voiceChanged);
    widget.draft?.addListener(_applyDraft);
    _controller.addListener(_onText);
    _auto = _makeAuto(LocalWords());
    SharedPreferences.getInstance().then(_prefsReady).catchError((_) {});
  }

  AutocompleteController _makeAuto(LocalWords words) {
    final api = SuggestApi();
    return AutocompleteController(
      fetch: (text, id) => api.complete(text, conversationId: id),
      local: words,
      conversationId: widget.conversationId,
      enabled: widget.autocomplete,
    );
  }

  void _prefsReady(SharedPreferences prefs) {
    if (!mounted) return;
    _prefs = prefs;
    final old = _auto;
    final fresh = _makeAuto(
      LocalWords(prefs.getString(SuggestConfig.memoryKey)),
    );
    _auto = fresh;
    old?.dispose();
    fresh.update(_atEnd ? _controller.text : '');
    setState(() {});
  }

  bool get _atEnd {
    final s = _controller.selection;
    return !s.isValid ||
        (s.isCollapsed && s.baseOffset == _controller.text.length);
  }

  void _onText() {
    if (_voiceOn.value) return;
    _auto?.update(_atEnd ? _controller.text : '');
  }

  void _acceptGhost() {
    if (_auto?.accept(_controller) ?? false) Haptics.tap();
  }

  void _learn(String text) {
    final auto = _auto;
    if (auto == null) return;
    auto.local.learn(text);
    _prefs?.setString(SuggestConfig.memoryKey, auto.local.toStorage());
  }

  @override
  void didUpdateWidget(ChatInput old) {
    super.didUpdateWidget(old);
    _auto
      ?..enabled = widget.autocomplete
      ..conversationId = widget.conversationId;
    if (!widget.autocomplete) _auto?.reset();
    if (old.voice != widget.voice) {
      old.voice?.removeListener(_voiceChanged);
      widget.voice?.addListener(_voiceChanged);
      _voiceChanged();
    }
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
    widget.voice?.removeListener(_voiceChanged);
    _voiceOn.dispose();
    _controller.removeListener(_onText);
    _auto?.dispose();
    _controller.dispose();
    _files.dispose();
    super.dispose();
  }

  bool get _canSend => _controller.text.trim().isNotEmpty || _files.hasUploaded;

  Future<void> _submit({bool asDoc = false}) async {
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
    _learn(text);
    final send = asDoc ? widget.onSendAsDoc ?? widget.onSend : widget.onSend;
    send(text, ready);
    _controller.clear();
    _files.clearSent();
  }

  void _voiceChanged() => _voiceOn.value = widget.voice?.active ?? false;

  Future<void> _startVoice() async {
    final voice = widget.voice;
    if (voice == null || voice.active || _starting || widget.isStreaming) {
      return;
    }
    _starting = true;
    try {
      if (!await _micRationale(voice) || !mounted) return;
      FocusScope.of(context).unfocus();
      final text = _controller.text;
      _voiceBase = text.trim().isEmpty ? '' : '${text.trimRight()} ';
      await voice.start(_onVoiceText);
    } finally {
      _starting = false;
    }
    // The button was let go while the permission prompt was up.
    if (_releaseAfterStart) {
      _releaseAfterStart = false;
      if (mounted) _finishHold();
    }
  }

  /// Explains the microphone permission before the system asks for it.
  /// A blocked permission skips this: the strip offers the app settings.
  Future<bool> _micRationale(VoiceController voice) async {
    final state = await voice.permissionState();
    if (state != VoicePermissionState.denied || !mounted) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(VoiceStrings.rationaleTitle),
        content: Text(VoiceStrings.rationaleBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(VoiceStrings.rationaleNotNow),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(VoiceStrings.rationaleAllow),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  void _onVoiceText(String text, bool isFinal) {
    if (!mounted) return;
    final all = _voiceBase + text;
    _controller.value = TextEditingValue(
      text: all,
      selection: TextSelection.collapsed(offset: all.length),
    );
    if (!isFinal) return;
    _controller.showFix(widget.voice?.lastFix, offset: _voiceBase.length);
    _onText();
    if (widget.sendVoiceAutomatically) _submit();
  }

  void _cancelVoice() {
    widget.voice?.cancel();
    final base = _voiceBase.trimRight();
    _controller.value = TextEditingValue(
      text: base,
      selection: TextSelection.collapsed(offset: base.length),
    );
  }

  void _micTap() {
    final voice = widget.voice;
    if (voice == null) return;
    if (voice.listening) {
      voice.stop();
    } else if (!voice.active) {
      _startVoice();
    }
  }

  void _finishHold() {
    final voice = widget.voice;
    final out = _slidingOut;
    setState(() => _holding = _slidingOut = false);
    if (voice == null || !voice.active) return;
    out ? _cancelVoice() : voice.stop();
  }

  void _toast(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  /// The "+": the same picker as the assistant overlay.
  Future<void> _attach() => _picker.pick(
    context,
    _files,
    say: (text) {
      if (mounted) _toast(text);
    },
  );

  /// "write a report on …" with DOC off: offer a document, never start one.
  bool _suggestsDoc(String text) =>
      !widget.doc &&
      widget.onSendAsDoc != null &&
      !widget.isStreaming &&
      text != _hintDismissed &&
      DocConfig.intent.hasMatch(text);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => AnimatedSize(
            duration: AppDurations.fast,
            alignment: Alignment.bottomCenter,
            child: _suggestsDoc(_controller.text)
                ? Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: _DocHint(
                      onWrite: () => _submit(asDoc: true),
                      onDismiss: () =>
                          setState(() => _hintDismissed = _controller.text),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ),
        AnimatedSize(
          duration: AppDurations.fast,
          alignment: Alignment.bottomCenter,
          child: widget.suggestion != null && widget.onAcceptSuggestion != null
              ? Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: SuggestPrompt(
                    suggestion: widget.suggestion!,
                    onAccept: widget.onAcceptSuggestion!,
                    onDismiss: widget.onDismissSuggestion ?? () {},
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        _autocompleteBar(),
        _capsule(context),
      ],
    );
  }

  Widget _autocompleteBar() {
    final auto = _auto;
    if (auto == null || !widget.autocomplete) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: Listenable.merge([auto, _controller]),
      builder: (context, _) => AutocompleteBar(
        ghost: auto.ghostFor(_controller.text),
        words: _controller.text == auto.text ? auto.words : const [],
        onAccept: _acceptGhost,
        onWord: (w) => auto.insertWord(_controller, w),
      ),
    );
  }

  /// The text field, with the completion shown dimmed after the cursor;
  /// swiping right on it accepts the completion.
  Widget _field(BuildContext context) {
    final field = ValueListenableBuilder<bool>(
      valueListenable: _voiceOn,
      builder: (context, dictating, _) => _textField(context, dictating),
    );
    final auto = _auto;
    if (auto == null || !widget.autocomplete) return field;
    return _ghostField(context, field, auto);
  }

  Widget _textField(BuildContext context, bool dictating) {
    return TextField(
      controller: _controller,
      readOnly: dictating,
      minLines: 1,
      maxLines: 5,
      style: context.text.body,
      textCapitalization: TextCapitalization.sentences,
      decoration: const InputDecoration(
        hintText: AppStrings.inputHint,
        isDense: true,
        contentPadding: _fieldPadding,
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
      ),
    );
  }

  Widget _ghostField(
    BuildContext context,
    Widget field,
    AutocompleteController auto,
  ) {
    return ListenableBuilder(
      listenable: Listenable.merge([auto, _controller]),
      builder: (context, _) {
        final ghost = _atEnd ? auto.ghostFor(_controller.text) : '';
        final style = context.text.body;
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragEnd: ghost.isEmpty
              ? null
              : (d) {
                  if ((d.primaryVelocity ?? 0) > SuggestSizes.swipeVelocity) {
                    _acceptGhost();
                  }
                },
          child: Stack(
            children: [
              if (ghost.isNotEmpty)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Padding(
                      padding: _fieldPadding,
                      child: Text.rich(
                        TextSpan(
                          style: style.copyWith(color: Colors.transparent),
                          text: _controller.text,
                          children: [
                            TextSpan(
                              text: ghost,
                              style: style.copyWith(
                                color: context.palette.textTertiary,
                              ),
                            ),
                          ],
                        ),
                        maxLines: 5,
                        overflow: TextOverflow.clip,
                      ),
                    ),
                  ),
                ),
              field,
            ],
          ),
        );
      },
    );
  }

  static const _fieldPadding = EdgeInsets.symmetric(
    horizontal: AppSpacing.md,
    vertical: AppSpacing.sm,
  );

  Widget _capsule(BuildContext context) {
    return Glass(
      radius: AppRadius.lg,
      padding: const EdgeInsets.all(AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AttachmentBar(controller: _files),
          if (widget.doc && widget.onDocLength != null)
            _DocLengthRow(value: widget.docLength, onPick: widget.onDocLength!),
          if (widget.voice != null)
            VoiceStrip(
              voice: widget.voice!,
              holding: _holding,
              slidingOut: _slidingOut,
              onCancel: _cancelVoice,
              onRetry: _startVoice,
              onSettings: widget.voice!.openSettings,
            ),
          if (widget.voice != null) VoiceFixChip(controller: _controller),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _attachButton(context),
              Expanded(child: _field(context)),
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
            // Scrolls rather than overflowing when every chip is shown.
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  SmartChip(
                    label: AppStrings.web,
                    icon: AppIcons.web,
                    active: widget.webMode == WebMode.on,
                    hint: switch (widget.webMode) {
                      WebMode.auto => SmartStrings.webAuto,
                      WebMode.off => SmartStrings.webOff,
                      WebMode.on => null,
                    },
                    dim: widget.webMode == WebMode.off,
                    onTap: widget.onToggleWebSearch,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  SmartChip(
                    label: AppStrings.kb,
                    icon: AppIcons.knowledge,
                    active: widget.knowledge,
                    onTap: widget.onToggleKnowledge,
                  ),
                  if (widget.onToggleRoundTable != null) ...[
                    const SizedBox(width: AppSpacing.sm),
                    SmartChip(
                      label: TableStrings.chip,
                      icon: AppIcons.roundTable,
                      active: widget.roundTable,
                      onTap: widget.onToggleRoundTable!,
                    ),
                  ],
                  if (widget.onToggleDoc != null) ...[
                    const SizedBox(width: AppSpacing.sm),
                    SmartChip(
                      label: DocStrings.chip,
                      icon: AppIcons.doc,
                      active: widget.doc,
                      onTap: widget.onToggleDoc!,
                    ),
                  ],
                ],
              ),
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

  /// Mic when idle; tick while listening (tap, or let go after holding);
  /// the clock while the transcript is on its way.
  Widget _micButton(BuildContext context, VoiceController voice) {
    final p = context.palette;
    return ListenableBuilder(
      listenable: voice,
      builder: (context, _) {
        final listening = voice.listening;
        final working = voice.phase == VoicePhase.transcribing;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _micTap,
          onLongPressStart: (_) {
            if (voice.active) return;
            setState(() => _holding = true);
            _startVoice();
          },
          onLongPressMoveUpdate: (d) {
            final out = d.offsetFromOrigin.dx < -VoiceSizes.holdCancelDistance;
            if (_holding && out != _slidingOut) {
              setState(() => _slidingOut = out);
            }
          },
          onLongPressEnd: (_) {
            if (!_holding) return;
            if (_starting) {
              _releaseAfterStart = true;
            } else {
              _finishHold();
            }
          },
          child: AnimatedContainer(
            duration: AppDurations.fast,
            width: AppSizes.sendButton,
            height: AppSizes.sendButton,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: listening ? p.accent : p.surfaceHigh,
            ),
            child: AppIcon(
              working
                  ? AppIcons.timer
                  : listening
                  ? AppIcons.check
                  : AppIcons.mic,
              size: AppIconSize.lg,
              semanticLabel: listening ? VoiceStrings.finish : VoiceStrings.mic,
              color: listening ? p.textInverse : p.textPrimary,
            ),
          ),
        );
      },
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
    final voice = widget.voice;
    return ListenableBuilder(
      listenable: Listenable.merge([_controller, _files, _voiceOn]),
      builder: (context, _) {
        if (voice != null && (_voiceOn.value || (!_canSend && !_waiting))) {
          return _micButton(context, voice);
        }
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

/// WRITE AS DOCUMENT? — one tap sends the message as a document.
class _DocHint extends StatelessWidget {
  const _DocHint({required this.onWrite, required this.onDismiss});

  final VoidCallback onWrite;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    return Align(
      alignment: Alignment.centerLeft,
      child: Glass(
        padding: const EdgeInsets.only(left: AppSpacing.md),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                Haptics.tap();
                onWrite();
              },
              child: SizedBox(
                height: AppSizes.sendButton,
                child: Row(
                  children: [
                    AppIcon(
                      AppIcons.doc,
                      size: AppIconSize.sm,
                      color: p.accent,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      DocStrings.suggest,
                      style: t.caption.copyWith(color: p.textPrimary),
                    ),
                  ],
                ),
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                Haptics.tap();
                onDismiss();
              },
              child: SizedBox.square(
                dimension: AppSizes.sendButton,
                child: AppIcon(
                  AppIcons.close,
                  size: AppIconSize.sm,
                  semanticLabel: AppStrings.cancel,
                  color: p.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// LENGTH label and an M3 segmented button (short, standard, long), shown
/// while DOC is on.
class _DocLengthRow extends StatelessWidget {
  const _DocLengthRow({required this.value, required this.onPick});

  final String value;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        0,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Text(DocStrings.lengthLabel, style: t.caption),
            const SizedBox(width: AppSpacing.md),
            SegmentedButton<String>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                textStyle: Theme.of(context).textTheme.labelMedium,
                selectedBackgroundColor: Theme.of(
                  context,
                ).colorScheme.secondaryContainer,
                selectedForegroundColor: context.palette.textPrimary,
              ),
              segments: [
                for (final (id, label) in DocStrings.lengths)
                  ButtonSegment(value: id, label: Text(sentenceCase(label))),
              ],
              selected: {value},
              onSelectionChanged: (v) {
                Haptics.tap();
                onPick(v.first);
              },
            ),
          ],
        ),
      ),
    );
  }
}

enum AttachChoice { media, photo, video, document }

/// Compact sheet with the ways to add a file.
Future<AttachChoice?> showAttachSheet(BuildContext context) {
  return showM3Sheet<AttachChoice>(
    context,
    builder: (sheet) => M3ActionSheet(
      rows: [
        for (final (choice, icon, label) in [
          (AttachChoice.media, AppIcons.image, AppStrings.attachMedia),
          (AttachChoice.photo, AppIcons.camera, AppStrings.attachTakePhoto),
          (AttachChoice.video, AppIcons.video, AppStrings.attachRecordVideo),
          (AttachChoice.document, AppIcons.file, AppStrings.attachDocument),
        ])
          SettingsTile(
            icon: icon,
            title: sentenceCase(label),
            onTap: () => Navigator.pop(sheet, choice),
          ),
      ],
    ),
  );
}
