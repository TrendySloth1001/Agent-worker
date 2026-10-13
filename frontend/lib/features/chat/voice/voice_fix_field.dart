import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/voice_fix.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import 'transcript_fixer.dart';

/// A text field controller that knows the last dictation fix: it tints the
/// corrected words for a moment and can put back what was heard.
class VoiceFixTextController extends TextEditingController {
  VoiceFixTextController({super.text}) {
    addListener(_check);
  }

  VoiceFix? _fix;
  int _at = 0;
  bool _tint = false;
  Timer? _tintTimer, _undoTimer;

  /// The fix the undo chip offers; null once the text moved on.
  VoiceFix? get fix => _fix;

  /// Marks [fix] as the text at [offset] (where the dictation began).
  void showFix(VoiceFix? fix, {required int offset}) {
    _clear(notify: false);
    if (fix == null || !fix.hasEdits || !_segmentIs(fix, offset)) {
      notifyListeners();
      return;
    }
    _fix = fix;
    _at = offset;
    _tint = fix.changed.isNotEmpty;
    _tintTimer = Timer(VoiceFixConfig.highlightFor, () {
      _tint = false;
      notifyListeners();
    });
    _undoTimer = Timer(VoiceFixConfig.undoFor, () => _clear());
    notifyListeners();
  }

  /// Puts back what the recognizer heard.
  void undoFix() {
    final f = _fix;
    if (f == null || !_segmentIs(f, _at)) return _clear();
    final next = text.replaceRange(_at, _at + f.text.length, f.raw);
    _clear(notify: false);
    value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: _at + f.raw.length),
    );
  }

  bool _segmentIs(VoiceFix f, int at) =>
      at >= 0 &&
      at + f.text.length <= text.length &&
      text.substring(at, at + f.text.length) == f.text;

  /// Typing over, sending or clearing the text ends the offer.
  void _check() {
    final f = _fix;
    if (f != null && !_segmentIs(f, _at)) _clear();
  }

  void _clear({bool notify = true}) {
    _tintTimer?.cancel();
    _undoTimer?.cancel();
    _tintTimer = _undoTimer = null;
    final had = _fix != null || _tint;
    _fix = null;
    _tint = false;
    if (notify && had) notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final f = _fix;
    if (!_tint || f == null || !_segmentIs(f, _at)) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final mark = (style ?? const TextStyle()).copyWith(
      backgroundColor: context.palette.accent.withValues(
        alpha: VoiceFixSizes.highlightAlpha,
      ),
    );
    final spans = <TextSpan>[];
    var pos = 0;
    for (final r in f.changed) {
      final start = _at + r.start, end = _at + r.end;
      if (start < pos || end > text.length) continue;
      if (start > pos) spans.add(TextSpan(text: text.substring(pos, start)));
      spans.add(TextSpan(text: text.substring(start, end), style: mark));
      pos = end;
    }
    if (pos < text.length) spans.add(TextSpan(text: text.substring(pos)));
    return TextSpan(style: style, children: spans);
  }

  @override
  void dispose() {
    _clear(notify: false);
    super.dispose();
  }
}

/// "Fixed 2 words · Undo fix" under the composer after a corrected dictation.
class VoiceFixChip extends StatelessWidget {
  const VoiceFixChip({super.key, required this.controller});

  final VoiceFixTextController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final fix = controller.fix;
        return AnimatedSize(
          duration: AppDurations.fast,
          alignment: Alignment.bottomLeft,
          child: fix == null
              ? const SizedBox(width: double.infinity)
              : _chip(context, fix),
        );
      },
    );
  }

  Widget _chip(BuildContext context, VoiceFix fix) {
    final p = context.palette;
    final t = context.text;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.sm,
        0,
      ),
      child: Row(
        children: [
          AppIcon(
            AppIcons.aiFormat,
            size: VoiceFixSizes.chipIcon,
            color: p.accent,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              VoiceFixStrings.fixed(fix.edits),
              style: t.caption.copyWith(color: p.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Semantics(
            button: true,
            label: VoiceFixStrings.undoSemantics,
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                Haptics.tap();
                controller.undoFix();
              },
              child: Container(
                height: VoiceFixSizes.chipHeight,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(color: p.border, width: AppBorder.thin),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppIcon(
                      AppIcons.undo,
                      size: VoiceFixSizes.chipIcon,
                      color: p.textPrimary,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      VoiceFixStrings.undo,
                      style: t.caption.copyWith(color: p.textPrimary),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
