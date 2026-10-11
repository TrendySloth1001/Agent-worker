import 'dart:math';

import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/widget_kit.dart';
import '../../../../core/constants/widget_playful.dart';
import '../../../../core/haptics.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/widgets/app_icon.dart';
import 'playful_common.dart';
import 'rich_frame.dart';

class QuizQuestion {
  const QuizQuestion(this.text, this.options, this.correct, this.why);
  final String text;
  final List<String> options;

  /// Index into [options].
  final int correct;
  final String why;
}

class QuizData {
  const QuizData(this.title, this.questions);
  final String title;
  final List<QuizQuestion> questions;
}

/// Parses a ```quiz block; null when no usable question remains.
QuizData? parseQuiz(String src) {
  var title = '';
  final out = <QuizQuestion>[];
  String? q;
  var opts = <String>[];
  var correct = -1;
  var why = '';

  void flush() {
    if (q != null && correct >= 0 && opts.length >= 2) {
      if (out.length < PlayfulLimits.quizQuestions) {
        out.add(QuizQuestion(q!, List.of(opts), correct, why));
      }
    }
    q = null;
    opts = [];
    correct = -1;
    why = '';
  }

  for (final line in playfulLines(src)) {
    final kv = playfulKeyValue(line);
    if (kv == null) continue;
    final (key, value) = kv;
    switch (key) {
      case 'title':
        title = value;
      case 'q':
        flush();
        q = value;
      case 'a':
        if (q == null || value.isEmpty) break;
        if (opts.length >= PlayfulLimits.quizOptions) break;
        var v = value;
        if (v.startsWith('*')) {
          v = v.substring(1).trim();
          if (correct < 0 && v.isNotEmpty) correct = opts.length;
        }
        if (v.isNotEmpty) opts.add(v);
      case 'why':
        why = value;
    }
  }
  flush();
  if (out.isEmpty) return null;
  return QuizData(title, out);
}

/// ```quiz block: one question at a time with instant feedback and a score.
class QuizCard extends StatefulWidget {
  const QuizCard({super.key, required this.source});

  final String source;

  @override
  State<QuizCard> createState() => _QuizCardState();
}

class _QuizCardState extends State<QuizCard> {
  late QuizData? _data = parseQuiz(widget.source);
  late int _seed = playfulSeed(widget.source);

  /// Per question: shuffled option order (indices into the original options).
  late List<List<int>> _orders;
  late List<int> _questionOrder;

  int _pos = 0;
  int? _picked; // display index within the shuffled order
  int _score = 0, _streak = 0, _best = 0;
  bool _finished = false;
  bool _scoreSent = false, _harderSent = false;

  @override
  void initState() {
    super.initState();
    _shuffle();
  }

  @override
  void didUpdateWidget(QuizCard old) {
    super.didUpdateWidget(old);
    if (old.source != widget.source) {
      _data = parseQuiz(widget.source);
      _seed = playfulSeed(widget.source);
      _restart(reshuffle: false);
    }
  }

  void _shuffle() {
    final d = _data;
    if (d == null) return;
    final rnd = Random(_seed);
    _questionOrder = List.generate(d.questions.length, (i) => i);
    if (_seed != playfulSeed(widget.source)) _questionOrder.shuffle(rnd);
    _orders = [
      for (final q in d.questions)
        (List.generate(q.options.length, (i) => i)..shuffle(rnd)),
    ];
  }

  void _restart({required bool reshuffle}) {
    setState(() {
      if (reshuffle) _seed = _seed * 7 + 13;
      _shuffle();
      _pos = 0;
      _picked = null;
      _score = 0;
      _streak = 0;
      _best = 0;
      _finished = false;
      _scoreSent = false;
      _harderSent = false;
    });
  }

  QuizQuestion get _q => _data!.questions[_questionOrder[_pos]];
  List<int> get _order => _orders[_questionOrder[_pos]];

  void _pick(int display) {
    if (_picked != null) return;
    final right = _order[display] == _q.correct;
    right ? Haptics.received() : Haptics.error();
    setState(() {
      _picked = display;
      if (right) {
        _score++;
        _streak++;
        _best = max(_best, _streak);
      } else {
        _streak = 0;
      }
    });
  }

  void _next() {
    if (_pos + 1 >= _data!.questions.length) {
      setState(() => _finished = true);
      return;
    }
    setState(() {
      _pos++;
      _picked = null;
    });
  }

  String get _title =>
      _data!.title.isEmpty ? PlayfulStrings.quizUntitled : _data!.title;

  @override
  Widget build(BuildContext context) {
    final d = _data;
    if (d == null) {
      return PlayfulFallback(
        title: WidgetKitStrings.quiz,
        source: widget.source,
      );
    }
    final total = d.questions.length;
    return RichCard(
      title: d.title.isEmpty
          ? WidgetKitStrings.quiz
          : '${WidgetKitStrings.quiz} / ${d.title.toUpperCase()}',
      trailing: _finished
          ? null
          : PlayfulTag(PlayfulStrings.question(_pos + 1, total)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PlayfulBar(
            value:
                (_finished ? total : _pos + (_picked != null ? 1 : 0)) / total,
          ),
          AnimatedSwitcher(
            duration: PlayfulDurations.swap,
            child: KeyedSubtree(
              key: ValueKey(_finished ? -1 : _pos),
              child: _finished ? _end(context, total) : _question(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _question(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final q = _q;
    final order = _order;
    final answered = _picked != null;
    final lastQ = _pos + 1 >= _data!.questions.length;
    return Padding(
      padding: const EdgeInsets.all(PlayfulSizes.pad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_streak > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: PlayfulTag(
                PlayfulStrings.streak(_streak),
                accent: true,
                icon: PlayfulIcons.streak,
              ),
            ),
          Text(q.text, style: t.body.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: AppSpacing.md),
          for (var i = 0; i < order.length; i++)
            _OptionTile(
              label: q.options[order[i]],
              state: !answered
                  ? _TileState.idle
                  : order[i] == q.correct
                  ? _TileState.correct
                  : i == _picked
                  ? _TileState.wrong
                  : _TileState.dim,
              onTap: () => _pick(i),
            ),
          AnimatedSize(
            duration: PlayfulDurations.expand,
            alignment: Alignment.topCenter,
            child: answered
                ? Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          order[_picked!] == q.correct
                              ? PlayfulStrings.correct
                              : PlayfulStrings.wrong,
                          style: t.caption.copyWith(
                            color: order[_picked!] == q.correct
                                ? p.accent
                                : p.textTertiary,
                          ),
                        ),
                        if (q.why.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Text(q.why, style: t.bodySmall),
                        ],
                        const SizedBox(height: AppSpacing.md),
                        Align(
                          alignment: Alignment.centerRight,
                          child: PlayfulButton(
                            label: lastQ
                                ? PlayfulStrings.results
                                : PlayfulStrings.next,
                            icon: PlayfulIcons.next,
                            primary: true,
                            onTap: _next,
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  String _rating(double ratio) {
    for (final (min, word) in PlayfulStrings.ratings) {
      if (ratio >= min) return word;
    }
    return PlayfulStrings.ratings.last.$2;
  }

  Widget _end(BuildContext context, int total) {
    final p = context.palette;
    final t = context.text;
    final can = playfulCanSend(context);
    return Padding(
      padding: const EdgeInsets.all(PlayfulSizes.pad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.sm),
          DotNumber(
            '$_score/$total',
            size: PlayfulSizes.scoreFont,
            align: Alignment.center,
            color: _score == total ? p.accent : null,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            _rating(_score / total),
            textAlign: TextAlign.center,
            style: t.label.copyWith(color: p.accent),
          ),
          if (_best > 1)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                PlayfulStrings.bestStreak(_best),
                textAlign: TextAlign.center,
                style: t.caption,
              ),
            ),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              PlayfulButton(
                label: PlayfulStrings.retry,
                icon: PlayfulIcons.restart,
                onTap: () => _restart(reshuffle: true),
              ),
              PlayfulButton(
                label: _scoreSent
                    ? PlayfulStrings.sent
                    : PlayfulStrings.sendScore,
                icon: PlayfulIcons.send,
                enabled: can && !_scoreSent,
                onTap: () {
                  if (playfulSend(
                    context,
                    PlayfulStrings.scorePrompt(_score, total, _title),
                  )) {
                    setState(() => _scoreSent = true);
                  }
                },
              ),
              PlayfulButton(
                label: _harderSent
                    ? PlayfulStrings.sent
                    : PlayfulStrings.askHarder,
                icon: PlayfulIcons.up,
                primary: true,
                enabled: can && !_harderSent,
                onTap: () {
                  if (playfulSend(
                    context,
                    PlayfulStrings.harderPrompt(_title),
                  )) {
                    setState(() => _harderSent = true);
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _TileState { idle, correct, wrong, dim }

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.label,
    required this.state,
    required this.onTap,
  });

  final String label;
  final _TileState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final correct = state == _TileState.correct;
    final wrong = state == _TileState.wrong;
    final dim = state == _TileState.dim;
    final textColor = wrong
        ? p.textTertiary
        : dim
        ? p.textSecondary
        : p.textPrimary;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Opacity(
        opacity: dim ? PlayfulSizes.dimAlpha : 1,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: state == _TileState.idle ? onTap : null,
          child: AnimatedContainer(
            duration: PlayfulDurations.swap,
            constraints: const BoxConstraints(
              minHeight: PlayfulSizes.tileMinHeight,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(
                color: correct ? p.accent : p.border,
                width: correct ? AppBorder.thick : AppBorder.thin,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: t.bodySmall.copyWith(
                      color: textColor,
                      decoration: wrong ? TextDecoration.lineThrough : null,
                      decorationColor: p.textTertiary,
                    ),
                  ),
                ),
                if (correct || wrong) ...[
                  const SizedBox(width: AppSpacing.sm),
                  AppIcon(
                    correct ? PlayfulIcons.check : PlayfulIcons.cross,
                    size: AppIconSize.sm,
                    color: correct ? p.accent : p.textTertiary,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
