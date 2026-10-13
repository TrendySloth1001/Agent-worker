import 'dart:async';
import '../features/actions/open_in_chips.dart';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';

import '../core/constants/app_icons.dart';
import '../core/constants/app_sizes.dart';
import '../core/constants/app_strings.dart';
import '../core/constants/assist.dart';
import '../core/constants/circle_search.dart';
import '../core/constants/live_voice.dart';
import '../core/constants/docs.dart';
import '../core/constants/smart_toggles.dart';
import '../core/constants/voice.dart';
import '../core/haptics.dart';
import '../core/theme/app_palette.dart';
import '../core/widgets/app_icon.dart';
import '../core/widgets/dot_matrix_backdrop.dart';
import '../core/widgets/icon_label.dart';
import '../features/settings/widgets/settings_kit.dart' show DotGrid;
import '../data/chat_message.dart';
import '../data/doc_models.dart';
import '../features/auth/auth_controller.dart';
import '../features/auth/widgets/auth_widgets.dart' show Wordmark;
import '../features/chat/attach_picker.dart';
import '../features/chat/voice/voice_controller.dart';
import '../features/chat/voice/voice_locale.dart';
import '../features/chat/voice/voice_permission.dart';
import '../features/chat/voice/voice_strip.dart';
import '../features/chat/widgets/attachment_bar.dart';
import '../features/chat/widgets/markdown/app_markdown.dart';
import '../features/chat/widgets/image_strip.dart';
import '../features/chat/widgets/memory_chip.dart';
import '../features/chat/widgets/round_table_header.dart';
import '../features/chat/widgets/round_table_panel.dart';
import '../features/chat/widgets/smart_chip.dart';
import '../features/chat/widgets/source_chips.dart';
import '../features/chat/widgets/suggest_prompt.dart';
import '../features/chat/widgets/thinking_indicator.dart';
import 'assist_controller.dart';
import 'circle/circle_view.dart';
import 'live/live_bar.dart';
import 'live/live_voice.dart';
import 'live/speaker.dart';

/// Card colour of the overlay: white on light, raised black on dark.
Color _card(AppPalette p) => p.isDark ? p.surfaceRaised : p.surface;

/// Tonal fill for buttons inside a card.
Color _tonal(AppPalette p) => p.isDark ? p.surfaceHigh : p.surfaceRaised;

/// The assistant overlay: a see-through scrim over the app behind (tap to
/// close), the answer sheet, the screen chip and the "Ask sparky" pill.
class AssistOverlay extends StatefulWidget {
  const AssistOverlay({
    super.key,
    required this.controller,
    this.voice,
    this.auth,
    this.attach,
    this.speaker,
    this.circleImage,
  });

  final AssistController controller;
  final VoiceController? voice;

  /// Defaults to [AuthController.instance].
  final AuthController? auth;

  /// The "+" (the app's picker: photos, camera, video, documents).
  final AttachPicker? attach;

  /// Live mode's voice; defaults to Android TextToSpeech.
  final Speaker? speaker;

  /// The frozen screenshot's image (a file on the phone; tests pass bytes).
  final ImageProvider Function(String path)? circleImage;

  @override
  State<AssistOverlay> createState() => _AssistOverlayState();
}

class _AssistOverlayState extends State<AssistOverlay> {
  final _field = TextEditingController();
  final _focus = FocusNode();
  late final _attachPicker = widget.attach ?? AttachPicker();
  String _voiceBase = '';
  bool _talking = false;
  LiveVoice? _live;
  StreamSubscription<void>? _hides;
  int _answers = 0;

  AssistController get _c => widget.controller;
  AuthController get _auth => widget.auth ?? AuthController.instance;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onController);
    // Out of sight (Home, another app): stop talking and listening.
    _hides = _c.bridge.hides.listen((_) {
      _live?.end();
      widget.voice?.cancel();
    });
  }

  @override
  void didUpdateWidget(AssistOverlay old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onController);
      widget.controller.addListener(_onController);
    }
  }

  /// A new opening clears what was typed; shared text fills the field;
  /// Live hears about the answer growing.
  void _onController() {
    if (_c.generation != _seen) {
      _seen = _c.generation;
      _field.clear();
      _focus.unfocus();
      _live?.end();
      widget.voice?.cancel();
    }
    final draft = _c.takeDraft();
    if (draft != null) {
      _field.value = TextEditingValue(
        text: draft,
        selection: TextSelection.collapsed(offset: draft.length),
      );
    }
    final live = _live;
    if (live != null && live.active) {
      final n = _c.messages.length;
      if (n != _answers || _c.streaming || !_c.sending) {
        _answers = n;
        live.answerChanged();
      }
    }
  }

  late int _seen = _c.generation;

  @override
  void dispose() {
    _c.removeListener(_onController);
    _hides?.cancel();
    _live?.dispose();
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _field.text;
    if (!_c.canSend(text)) return;
    _focus.unfocus();
    final sent = await _c.send(text);
    if (sent && mounted) _field.clear();
  }

  // ---- voice ---------------------------------------------------------------

  /// Dictates into the field; [talk] sends as soon as the speech ends.
  Future<void> _startVoice({bool talk = false}) async {
    final voice = widget.voice;
    if (voice == null || voice.active) return;
    Haptics.tap();
    if (!await _micRationale(voice) || !mounted) return;
    _focus.unfocus();
    final text = _field.text;
    _voiceBase = text.trim().isEmpty ? '' : '${text.trimRight()} ';
    _talking = talk;
    await voice.start(_onVoiceText);
  }

  /// The overlay never asks Android for the microphone itself: the system
  /// closes the overlay when its permission dialog appears. Until it is
  /// allowed, offer to open sparky, which asks in a normal window.
  Future<bool> _micRationale(VoiceController voice) async {
    final state = await voice.permissionState();
    if (state == VoicePermissionState.granted || !mounted) return true;
    final open = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(AssistStrings.micTitle),
        content: const Text(AssistStrings.micBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(AssistStrings.micNotNow),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(AssistStrings.micOpen),
          ),
        ],
      ),
    );
    if (open == true) await _c.bridge.allowMicInApp();
    return false;
  }

  // ---- live ----------------------------------------------------------------

  /// Live: talk, sparky answers aloud, and listens again.
  Future<void> _startLive() async {
    final voice = widget.voice;
    if (voice == null || voice.active || (_live?.active ?? false)) return;
    Haptics.tap();
    if (!await _micRationale(voice) || !mounted) return;
    _focus.unfocus();
    final live = _live ??= LiveVoice(
      ears: VoiceEars(voice),
      speaker: widget.speaker ?? ChannelSpeaker(),
      ask: (text) => _c.send(text),
      answer: () => _c.liveAnswer,
      onInterrupt: _c.stop,
      lang: () => voiceLocaleFor(
        language: _c.settings.language,
        device: PlatformDispatcher.instance.locale.toLanguageTag(),
      ),
    )..addListener(_onLive);
    _answers = _c.messages.length;
    live.start();
  }

  void _onLive() {
    final live = _live;
    if (live != null && !live.active && live.endedBySilence) {
      live.endedBySilence = false;
      _c.say(LiveStrings.ended);
    }
    if (mounted) setState(() {});
  }

  bool get _liveOn => _live?.active ?? false;

  void _onVoiceText(String text, bool isFinal) {
    if (!mounted) return;
    final all = _voiceBase + text;
    _field.value = TextEditingValue(
      text: all,
      selection: TextSelection.collapsed(offset: all.length),
    );
    if (isFinal && _talking) {
      _talking = false;
      _submit();
    }
  }

  void _cancelVoice() {
    widget.voice?.cancel();
    _talking = false;
    final base = _voiceBase.trimRight();
    _field.value = TextEditingValue(
      text: base,
      selection: TextSelection.collapsed(offset: base.length),
    );
  }

  // ---- attach --------------------------------------------------------------

  /// Same files as the app's chat: uploads with progress chips in the pill.
  Future<void> _attach() =>
      _attachPicker.pick(context, _c.attachments, say: _c.say);

  // ---- build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _c.close();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Positioned.fill(
              child: ListenableBuilder(
                listenable: _c,
                builder: (context, _) {
                  final image = _c.circleImage;
                  if (_c.circle != CirclePhase.off && image != null) {
                    return CircleView(
                      image:
                          widget.circleImage?.call(image) ??
                          CircleView.fileImage(image),
                      selection: _c.circleSelection,
                      selecting: _c.circle != CirclePhase.results,
                      busy: _c.circle == CirclePhase.cropping,
                      onSelect: (rect, view) {
                        _focus.unfocus();
                        _c.circleSelect(rect, view);
                      },
                      onCancel: _c.cancelCircle,
                      onDrawStart: _c.circleDrawing,
                      onEmpty: () => _c.say(CircleStrings.nothingSelected),
                    );
                  }
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _c.close,
                    child: ListenableBuilder(
                      listenable: Listenable.merge([_c, ?widget.voice]),
                      builder: (context, _) => DotMatrixBackdrop(
                        mode: _backdropMode(),
                        wave: _c.generation,
                        level: widget.voice == null
                            ? null
                            : () => widget.voice!.level,
                      ),
                    ),
                  );
                },
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(AssistSizes.edge),
                  child: ListenableBuilder(
                    listenable: Listenable.merge([_c, _auth, ?_live]),
                    builder: (context, _) => _content(context),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The backdrop follows the overlay: listening, thinking (no words yet),
  /// streaming, else a calm idle glow.
  DotMatrixMode _backdropMode() {
    if (widget.voice?.listening ?? false) return DotMatrixMode.listening;
    if (_live?.phase == LivePhase.speaking) return DotMatrixMode.streaming;
    final last = _c.messages.lastOrNull;
    if (_c.waitingUploads ||
        (_c.streaming && last!.content.isEmpty) ||
        (_c.sending && !_c.streaming)) {
      return DotMatrixMode.thinking;
    }
    if (_c.streaming) return DotMatrixMode.streaming;
    return DotMatrixMode.idle;
  }

  Widget _content(BuildContext context) {
    if (_auth.status == AuthStatus.signedOut) {
      return _SignInCard(onOpen: _c.openInSparky, onClose: _c.close);
    }
    final maxSheet =
        MediaQuery.sizeOf(context).height * AssistSizes.sheetMaxFactor;
    // Drawing on the frozen screen: only a note, if any, at the bottom.
    if (_c.circle == CirclePhase.selecting ||
        _c.circle == CirclePhase.cropping) {
      return _c.notice == null
          ? const SizedBox.shrink()
          : _Notice(controller: _c);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_c.hasThread)
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxSheet),
              child: _AnswerSheet(
                controller: _c,
                onAsk: () => _focus.requestFocus(),
                circleThumb: widget.circleImage,
              ),
            ),
          ),
        if (_c.hasThread) const SizedBox(height: AppSpacing.sm),
        if (_c.suggestion != null) ...[
          SuggestPrompt(
            suggestion: _c.suggestion!,
            onAccept: _c.acceptSuggestion,
            onDismiss: _c.dismissSuggestion,
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        if (_c.notice != null) ...[
          _Notice(controller: _c),
          const SizedBox(height: AppSpacing.sm),
        ],
        if (_c.canShare && !_c.hasThread && !_liveOn) ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            child: Row(
              children: [
                _ShareChip(controller: _c),
                const SizedBox(width: AppSpacing.sm),
                _ScreenChip(
                  icon: CircleIcons.circle,
                  label: CircleStrings.chip,
                  onTap: _c.startCircle,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        _pill(context),
      ],
    );
  }

  Widget _pill(BuildContext context) {
    final p = context.palette;
    final voice = widget.voice;
    final live = _live;
    final pill = Container(
      constraints: const BoxConstraints(minHeight: AssistSizes.pillHeight),
      padding: const EdgeInsets.all(AssistSizes.pillPadding),
      decoration: BoxDecoration(
        color: _card(p),
        borderRadius: BorderRadius.circular(AssistSizes.pillRadius),
        border: Border.all(color: p.border, width: AppBorder.thin),
        boxShadow: _shadow(p.isDark),
      ),
      child: live != null && live.active
          ? LiveBar(live: live, level: () => voice?.level ?? 0)
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AttachmentBar(controller: _c.attachments),
                if (voice != null)
                  VoiceStrip(
                    voice: voice,
                    holding: false,
                    slidingOut: false,
                    onCancel: _cancelVoice,
                    onRetry: _startVoice,
                    onSettings: voice.openSettings,
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _RoundButton(
                      icon: AppIcons.add,
                      label: AssistStrings.attach,
                      fill: _tonal(p),
                      color: p.textPrimary,
                      onTap: _attach,
                    ),
                    Expanded(child: _input(context)),
                    if (voice != null) _micButton(context, voice),
                    const SizedBox(width: AppSpacing.xs),
                    _trailing(context),
                  ],
                ),
                _Toggles(controller: _c),
              ],
            ),
    );
    // Long-press the pill: Circle to search (when the screen can be used).
    if (!_c.canCircle) return pill;
    return GestureDetector(onLongPress: _c.startCircle, child: pill);
  }

  Widget _input(BuildContext context) {
    final p = context.palette;
    return TextField(
      controller: _field,
      focusNode: _focus,
      minLines: 1,
      maxLines: AssistSizes.fieldMaxLines,
      // A plain text keyboard: its action key sends (a multiline keyboard
      // would insert a newline instead). Long questions still wrap.
      keyboardType: TextInputType.text,
      textCapitalization: TextCapitalization.sentences,
      textInputAction: TextInputAction.send,
      onSubmitted: (_) => _submit(),
      style: context.text.body,
      cursorColor: p.accent,
      decoration: InputDecoration(
        hintText: AssistStrings.askHint,
        hintStyle: context.text.body.copyWith(color: p.textTertiary),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        filled: false,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
      ),
    );
  }

  Widget _micButton(BuildContext context, VoiceController voice) {
    final p = context.palette;
    return ListenableBuilder(
      listenable: voice,
      builder: (context, _) {
        final listening = voice.listening;
        return _RoundButton(
          icon: listening ? AppIcons.check : AppIcons.mic,
          label: listening ? VoiceStrings.finish : AssistStrings.mic,
          fill: listening ? p.accent : Colors.transparent,
          color: listening ? p.textInverse : p.textPrimary,
          onTap: () {
            if (voice.listening) {
              Haptics.tap();
              voice.stop();
            } else {
              _startVoice();
            }
          },
        );
      },
    );
  }

  /// Stop while answering, send with text, else talk (dictate and send).
  Widget _trailing(BuildContext context) {
    final p = context.palette;
    if (_c.streaming) {
      return _RoundButton(
        icon: AssistIcons.stop,
        label: AssistStrings.stop,
        fill: p.accent,
        color: p.textInverse,
        onTap: _c.stop,
      );
    }
    return ListenableBuilder(
      listenable: Listenable.merge([_field, _c.attachments]),
      builder: (context, _) {
        final ready = _c.canSend(_field.text);
        if (!ready && widget.voice != null) {
          final live = _c.settings.assistLive;
          return _RoundButton(
            icon: live ? LiveIcons.live : AssistIcons.live,
            label: live ? LiveStrings.start : AssistStrings.talk,
            fill: p.textPrimary,
            color: p.textInverse,
            onTap: live ? _startLive : () => _startVoice(talk: true),
          );
        }
        return _RoundButton(
          icon: _c.waitingUploads ? AppIcons.timer : AppIcons.send,
          label: AssistStrings.send,
          fill: ready ? p.textPrimary : _tonal(p),
          color: ready ? p.textInverse : p.textTertiary,
          onTap: _submit,
        );
      },
    );
  }
}

/// The overlay's soft shadow under cards.
List<BoxShadow> _shadow(bool dark) => [
  BoxShadow(
    color: Colors.black.withValues(
      alpha: dark ? AssistSizes.shadowDark : AssistSizes.shadowLight,
    ),
    blurRadius: AssistSizes.shadowBlur,
    offset: const Offset(0, AssistSizes.shadowY),
  ),
];

/// A 44dp circle button with an icon.
class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.label,
    required this.fill,
    required this.color,
    required this.onTap,
  });

  final AppIconData icon;
  final String label;
  final Color fill, color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppDurations.fast,
          width: AssistSizes.pillButton,
          height: AssistSizes.pillButton,
          decoration: BoxDecoration(shape: BoxShape.circle, color: fill),
          child: AppIcon(icon, size: AppIconSize.lg, color: color),
        ),
      ),
    );
  }
}

/// "Share screen with sparky", then what was shared (tap x to take it back).
class _ShareChip extends StatelessWidget {
  const _ShareChip({required this.controller});

  final AssistController controller;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = controller;
    final shared = c.share == ScreenShare.shared;
    final loading = c.share == ScreenShare.loading;
    final app = c.screen?.appName;
    final label = switch (c.share) {
      ScreenShare.loading => AssistStrings.sharingScreen,
      ScreenShare.shared =>
        app == null
            ? AssistStrings.screenShared
            : AssistStrings.screenSharedFrom(app),
      _ => AssistStrings.shareScreen,
    };
    final fg = shared ? p.textInverse : p.textPrimary;
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: shared ? c.unshare : c.shareScreen,
        child: AnimatedContainer(
          duration: AppDurations.fast,
          height: AssistSizes.chipHeight,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: BoxDecoration(
            color: shared ? p.textPrimary : _card(p),
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: shared ? p.textPrimary : p.border,
              width: AppBorder.thin,
            ),
            boxShadow: _shadow(p.isDark),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading)
                SizedBox.square(
                  dimension: AppIconSize.sm,
                  child: CircularProgressIndicator(
                    strokeWidth: AppBorder.thick,
                    color: p.textSecondary,
                  ),
                )
              else
                AppIcon(AssistIcons.screen, size: AppIconSize.sm, color: fg),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodySmall.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (shared) ...[
                const SizedBox(width: AppSpacing.sm),
                AppIcon(
                  AppIcons.close,
                  size: AppIconSize.sm,
                  color: fg,
                  semanticLabel: AssistStrings.unshare,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A plain chip next to the screen chip ("Circle to search").
class _ScreenChip extends StatelessWidget {
  const _ScreenChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final AppIconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: AssistSizes.chipHeight,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: BoxDecoration(
            color: _card(p),
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: p.border, width: AppBorder.thin),
            boxShadow: _shadow(p.isDark),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(icon, size: AppIconSize.sm, color: p.accent),
              const SizedBox(width: AppSpacing.sm),
              Text(
                label,
                style: context.text.bodySmall.copyWith(
                  color: p.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One line of help above the pill, optionally with a SETTINGS link.
class _Notice extends StatelessWidget {
  const _Notice({required this.controller});

  final AssistController controller;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: _card(p),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: p.border, width: AppBorder.thin),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              controller.notice!,
              style: context.text.bodySmall.copyWith(color: p.textSecondary),
            ),
          ),
          if (controller.noticeOpensSettings)
            TextButton(
              onPressed: () {
                Haptics.tap();
                controller.bridge.assistantSettings();
              },
              child: Text(
                AssistStrings.screenSettings,
                style: context.text.caption.copyWith(color: p.accent),
              ),
            ),
          IconButton(
            tooltip: AssistStrings.close,
            onPressed: controller.dismissNotice,
            icon: AppIcon(
              AppIcons.close,
              size: AppIconSize.sm,
              color: p.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

/// The conversation of this opening, newest at the bottom, with the
/// actions under the latest answer.
class _AnswerSheet extends StatelessWidget {
  const _AnswerSheet({
    required this.controller,
    required this.onAsk,
    this.circleThumb,
  });

  final AssistController controller;

  /// "Ask…" under a circle answer: focus the field.
  final VoidCallback onAsk;
  final ImageProvider Function(String path)? circleThumb;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = controller;
    final app = c.share == ScreenShare.shared ? c.screen?.appName : null;
    return Container(
      decoration: BoxDecoration(
        color: _card(p),
        borderRadius: BorderRadius.circular(AssistSizes.sheetRadius),
        border: Border.all(color: p.border, width: AppBorder.thin),
        boxShadow: _shadow(p.isDark),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AssistSizes.sheetPadding,
              AppSpacing.sm,
              AppSpacing.xs,
              0,
            ),
            child: Row(
              children: [
                const Wordmark(size: AssistSizes.wordmark),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    app?.toUpperCase() ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.caption,
                  ),
                ),
                IconButton(
                  tooltip: AssistStrings.close,
                  onPressed: c.close,
                  icon: AppIcon(
                    AppIcons.close,
                    size: AppIconSize.md,
                    color: p.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (c.circle == CirclePhase.results && c.circleCrop != null)
            _CircleHeader(controller: c, onAsk: onAsk, thumb: circleThumb),
          Flexible(
            child: SingleChildScrollView(
              // Anchored at the bottom: new text stays in view.
              reverse: true,
              padding: const EdgeInsets.fromLTRB(
                AssistSizes.sheetPadding,
                0,
                AssistSizes.sheetPadding,
                AppSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final m in c.messages)
                    if (m.role == Role.user)
                      _Question(message: m)
                    else
                      _Answer(message: m, onAnswerFast: c.answerFast),
                ],
              ),
            ),
          ),
          if (c.lastAnswer != null && !c.streaming) _Actions(controller: c),
        ],
      ),
    );
  }
}

/// Above a circle answer: the cut-out, its text, and the quick chips
/// (Search, Explain, Translate, Copy text, Ask…, Re-select).
class _CircleHeader extends StatefulWidget {
  const _CircleHeader({
    required this.controller,
    required this.onAsk,
    this.thumb,
  });

  final AssistController controller;
  final VoidCallback onAsk;
  final ImageProvider Function(String path)? thumb;

  @override
  State<_CircleHeader> createState() => _CircleHeaderState();
}

class _CircleHeaderState extends State<_CircleHeader> {
  bool _copied = false;

  Future<void> _copy() async {
    await widget.controller.circleQuick(CircleQuick.copy);
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(AppDurations.copiedFeedback);
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = widget.controller;
    final crop = c.circleCrop!;
    final text = c.circleText.replaceAll('\n', ' · ');
    const gap = SizedBox(width: AppSpacing.xs);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AssistSizes.sheetPadding,
        AppSpacing.xs,
        AssistSizes.sheetPadding,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: Container(
                  width: CircleSizes.thumb,
                  height: CircleSizes.thumb,
                  decoration: BoxDecoration(
                    color: _tonal(p),
                    border: Border.all(color: p.accent, width: AppBorder.thick),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Image(
                    image: widget.thumb?.call(crop) ?? FileImage(File(crop)),
                    fit: BoxFit.cover,
                    errorBuilder: (context, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(CircleStrings.selection, style: context.text.caption),
                    if (text.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                SmartChip(
                  label: CircleStrings.search,
                  icon: CircleIcons.search,
                  active: false,
                  height: AssistSizes.toggleHeight,
                  onTap: () => c.circleQuick(CircleQuick.search),
                ),
                gap,
                SmartChip(
                  label: CircleStrings.explain,
                  icon: CircleIcons.explain,
                  active: false,
                  height: AssistSizes.toggleHeight,
                  onTap: () => c.circleQuick(CircleQuick.explain),
                ),
                gap,
                SmartChip(
                  label: CircleStrings.translate,
                  icon: CircleIcons.translate,
                  active: false,
                  height: AssistSizes.toggleHeight,
                  onTap: () => c.circleQuick(CircleQuick.translate),
                ),
                if (c.circleText.isNotEmpty) ...[
                  gap,
                  SmartChip(
                    label: _copied
                        ? CircleStrings.copiedText
                        : CircleStrings.copyText,
                    icon: _copied ? AppIcons.check : CircleIcons.copy,
                    active: false,
                    height: AssistSizes.toggleHeight,
                    onTap: _copy,
                  ),
                ],
                gap,
                SmartChip(
                  label: CircleStrings.ask,
                  icon: CircleIcons.ask,
                  active: false,
                  height: AssistSizes.toggleHeight,
                  onTap: () {
                    c.circleQuick(CircleQuick.ask);
                    widget.onAsk();
                  },
                ),
                gap,
                SmartChip(
                  label: CircleStrings.reselect,
                  icon: CircleIcons.reselect,
                  active: false,
                  height: AssistSizes.toggleHeight,
                  onTap: c.startCircle,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Question extends StatelessWidget {
  const _Question({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final photos = message.attachments.length;
    final width = MediaQuery.sizeOf(context).width;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.md),
      child: Align(
        alignment: AlignmentDirectional.centerEnd,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: width * AssistSizes.questionMaxWidthFactor,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: p.userBubble,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (photos > 0)
                  IconLabel(
                    icon: AppIcons.image,
                    text: _attachLabel(message),
                    style: context.text.caption,
                    color: p.userBubbleText.withValues(
                      alpha: AssistSizes.mutedAlpha,
                    ),
                  ),
                if (message.content.isNotEmpty)
                  Text(
                    message.content,
                    style: context.text.body.copyWith(color: p.userBubbleText),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "SCREENSHOT" / "1 PHOTO" / "2 PHOTOS" above a question.
String _attachLabel(ChatMessage m) {
  final n = m.attachments.length;
  final screen = m.attachments.any(
    (a) => a.name == AssistConfig.screenshotName,
  );
  final selection = m.attachments.any((a) => a.name == CircleConfig.cropName);
  return AssistStrings.attachLabel(n, screenshot: screen, selection: selection);
}

class _Answer extends StatelessWidget {
  const _Answer({required this.message, required this.onAnswerFast});

  final ChatMessage message;
  final VoidCallback onAnswerFast;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final waiting = message.isStreaming && message.content.isEmpty;
    if (waiting && message.tablePhase != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: RoundTablePanel(message: message, onAnswerFast: onAnswerFast),
      );
    }
    final doc = message.isError ? null : DocLink.fromMeta(message.meta);
    if (doc != null) return _DocCard(message: message);
    if (waiting) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: ThinkingIndicator(label: AssistStrings.thinking),
        ),
      );
    }
    if (message.isError) {
      return Text(
        message.content,
        style: context.text.bodySmall.copyWith(color: p.error),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (message.table != null) ...[
          RoundTableHeader(table: message.table!, citations: message.citations),
          const SizedBox(height: AppSpacing.md),
        ],
        AppMarkdown(
          data: message.content,
          citations: message.citations,
          evidence: message.evidence,
          streaming: message.isStreaming,
        ),
        if (message.error != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              message.error!,
              style: context.text.caption.copyWith(color: p.error),
            ),
          ),
        if (message.notice != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(message.notice!, style: context.text.caption),
        ],
        if (message.memoryOps.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          MemoryChip(ops: message.memoryOps),
        ],
        if (message.images.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          ImageStrip(images: message.images),
        ],
        if (message.meta[SmartConfig.searchedKey] == true) ...[
          const SizedBox(height: AppSpacing.sm),
          const SearchedWebNote(),
        ],
        if (message.citations.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          SourceChips(citations: message.citations, used: message.usedIds),
        ],
        if (!message.isStreaming &&
            OpenInChips.linksOf(message.citations).isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          OpenInChips(citations: message.citations),
        ],
      ],
    );
  }
}

/// DOC: the document keeps being written on the server; it opens in the app.
class _DocCard extends StatelessWidget {
  const _DocCard({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: _tonal(p),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        children: [
          AppIcon(AppIcons.doc, size: AppIconSize.lg, color: p.textPrimary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message.content, style: context.text.body),
                const SizedBox(height: AppSpacing.xs),
                Text(AssistStrings.docInApp, style: context.text.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// WEB / KB / TABLE / DOC, like the app's composer (smaller).
class _Toggles extends StatelessWidget {
  const _Toggles({required this.controller});

  final AssistController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    const gap = SizedBox(width: AppSpacing.xs);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xs,
        AppSpacing.xs,
        AppSpacing.xs,
        0,
      ),
      // Scrolls rather than overflowing on narrow phones.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            SmartChip(
              label: AppStrings.web,
              icon: AppIcons.web,
              active: c.webMode == WebMode.on,
              hint: switch (c.webMode) {
                WebMode.auto => SmartStrings.webAuto,
                WebMode.off => SmartStrings.webOff,
                WebMode.on => null,
              },
              dim: c.webMode == WebMode.off,
              height: AssistSizes.toggleHeight,
              onTap: c.cycleWebMode,
            ),
            gap,
            SmartChip(
              label: AppStrings.kb,
              icon: AppIcons.knowledge,
              active: c.knowledge,
              height: AssistSizes.toggleHeight,
              onTap: c.toggleKnowledge,
            ),
            gap,
            SmartChip(
              label: TableStrings.chip,
              icon: AppIcons.roundTable,
              active: c.roundTable,
              height: AssistSizes.toggleHeight,
              onTap: c.toggleRoundTable,
            ),
            gap,
            SmartChip(
              label: DocStrings.chip,
              icon: AppIcons.doc,
              active: c.doc,
              height: AssistSizes.toggleHeight,
              onTap: c.toggleDoc,
            ),
          ],
        ),
      ),
    );
  }
}

/// Open in sparky (filled) and Copy under the latest answer.
class _Actions extends StatefulWidget {
  const _Actions({required this.controller});

  final AssistController controller;

  @override
  State<_Actions> createState() => _ActionsState();
}

class _ActionsState extends State<_Actions> {
  bool _copied = false;

  Future<void> _copy() async {
    await widget.controller.copyAnswer();
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(AppDurations.copiedFeedback);
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = widget.controller;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AssistSizes.sheetPadding,
        AppSpacing.sm,
        AssistSizes.sheetPadding,
        AssistSizes.sheetPadding,
      ),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: p.border, width: AppBorder.thin),
        ),
      ),
      child: Row(
        children: [
          _PillAction(
            icon: AssistIcons.openApp,
            label: c.opening
                ? AssistStrings.opening
                : AssistStrings.openInSparky,
            filled: true,
            onTap: c.opening ? null : c.openInSparky,
          ),
          const SizedBox(width: AppSpacing.sm),
          _PillAction(
            icon: _copied ? AppIcons.check : AppIcons.copy,
            label: _copied ? AssistStrings.copied : AssistStrings.copy,
            onTap: _copy,
          ),
        ],
      ),
    );
  }
}

class _PillAction extends StatelessWidget {
  const _PillAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  final AppIconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fg = filled ? p.textInverse : p.textPrimary;
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: AssistSizes.actionHeight,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          decoration: BoxDecoration(
            color: filled ? p.textPrimary : _tonal(p),
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(icon, size: AppIconSize.sm, color: fg),
              const SizedBox(width: AppSpacing.sm),
              Text(
                label,
                style: context.text.bodySmall.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown instead of the pill when nobody is signed in.
class _SignInCard extends StatelessWidget {
  const _SignInCard({required this.onOpen, required this.onClose});

  final VoidCallback onOpen, onClose;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AssistSizes.sheetPadding + AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.xs,
        AssistSizes.sheetPadding + AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: _card(p),
        borderRadius: BorderRadius.circular(AssistSizes.sheetRadius),
        border: Border.all(color: p.border, width: AppBorder.thin),
        boxShadow: _shadow(p.isDark),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Wordmark(size: AssistSizes.wordmark),
              const Spacer(),
              IconButton(
                tooltip: AssistStrings.close,
                onPressed: onClose,
                icon: AppIcon(
                  AppIcons.close,
                  size: AppIconSize.md,
                  color: p.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(AssistStrings.signInTitle, style: context.text.title),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      AssistStrings.signInBody,
                      style: context.text.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.md),
                child: DotGrid(
                  size: AssistSizes.pillButton,
                  color: p.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _PillAction(
            icon: AssistIcons.openApp,
            label: AssistStrings.signInAction,
            filled: true,
            onTap: onOpen,
          ),
        ],
      ),
    );
  }
}
