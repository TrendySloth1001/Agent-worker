import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/thinking_words.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/model_logo.dart';
import '../wait_status.dart';
import 'thinking_indicator.dart';

/// The compact status line that stands in for the plain "AI" label while a
/// reply has no text yet: which model is being picked, what is happening, or
/// a playful word. Steps crossfade; with reduced motion nothing moves.
class WaitStatusLine extends StatefulWidget {
  const WaitStatusLine({
    super.key,
    required this.step,
    this.prompt,
    this.usedWords,
  });

  final WaitStep step;

  /// The user's message, to flavour the playful words.
  final String? prompt;

  /// Words already shown (default: this session's).
  final Set<String>? usedWords;

  @override
  State<WaitStatusLine> createState() => _WaitStatusLineState();
}

class _WaitStatusLineState extends State<WaitStatusLine> {
  Timer? _timer;
  String _word = '';
  int _lit = 0;
  late final Set<String> _used = widget.usedWords ?? ThinkingWords.sessionUsed;

  @override
  void initState() {
    super.initState();
    _word = _nextWord();
  }

  String _nextWord() => ThinkingWords.next(
    seed: ThinkingWords.seedOf(widget.prompt ?? ''),
    prompt: widget.prompt,
    used: _used,
  );

  void _tick(Timer _) {
    if (!mounted) return;
    setState(() {
      _lit++;
      if (widget.step.kind == WaitKind.think &&
          _lit % AppDurations.waitWordBeats == 0) {
        _word = _nextWord();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _timer?.cancel();
    _timer = null;
    if (!MediaQuery.disableAnimationsOf(context)) {
      _timer = Timer.periodic(AppDurations.waitCycle, _tick);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final step = widget.step;
    final text = step.kind == WaitKind.think ? _word : step.text;
    final logos = step.logoIds;
    final lit = logos.isEmpty ? 0 : _lit % logos.length;
    return Semantics(
      liveRegion: true,
      label: text,
      excludeSemantics: true,
      child: AnimatedSwitcher(
        duration: reduce ? Duration.zero : AppDurations.normal,
        layoutBuilder: (current, previous) => Stack(
          alignment: AlignmentDirectional.centerStart,
          children: [...previous, ?current],
        ),
        child: logos.isEmpty
            ? KeyedSubtree(
                key: ValueKey('${step.kind.name}|$text'),
                child: ThinkingIndicator(label: text),
              )
            : _LogoLine(
                key: ValueKey('${step.kind.name}|$text'),
                logoIds: logos,
                lit: step.kind == WaitKind.picking && !reduce ? lit : -1,
                text: text,
              ),
      ),
    );
  }
}

class _LogoLine extends StatelessWidget {
  const _LogoLine({
    super.key,
    required this.logoIds,
    required this.lit,
    required this.text,
  });

  final List<String> logoIds;

  /// Index of the highlighted logo, or -1 for all at full strength.
  final int lit;
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      children: [
        for (var i = 0; i < logoIds.length; i++)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: AppSpacing.xs),
            child: AnimatedOpacity(
              duration: AppDurations.fast,
              opacity: lit < 0 || i == lit ? 1 : AppSizes.waitDimmedOpacity,
              child: ModelLogo(logoIds[i], size: AppSizes.modelLabelLogo),
            ),
          ),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.caption.copyWith(color: p.textSecondary),
          ),
        ),
      ],
    );
  }
}
