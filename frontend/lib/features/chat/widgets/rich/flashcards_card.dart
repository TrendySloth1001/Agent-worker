import 'dart:math';

import 'package:flutter/material.dart';

import "../../../../core/constants/app_icons.dart";
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/widget_kit.dart';
import '../../../../core/constants/widget_playful.dart';
import '../../../../core/haptics.dart';
import '../../../../core/theme/app_palette.dart';
import 'playful_common.dart';
import 'rich_frame.dart';

class FlashCard {
  const FlashCard(this.front, this.back);
  final String front, back;
}

class FlashData {
  const FlashData(this.title, this.cards);
  final String title;
  final List<FlashCard> cards;
}

/// Parses a ```flashcards block; null when there are no cards.
FlashData? parseFlashcards(String src) {
  var title = '';
  final cards = <FlashCard>[];
  for (final line in playfulLines(src)) {
    final kv = playfulKeyValue(line);
    if (kv == null) continue;
    final (key, value) = kv;
    if (key == 'title') {
      title = value;
    } else if (key == 'card' && cards.length < PlayfulLimits.cards) {
      final i = value.indexOf('|');
      if (i <= 0) continue;
      final f = value.substring(0, i).trim();
      final b = value.substring(i + 1).trim();
      if (f.isNotEmpty && b.isNotEmpty) cards.add(FlashCard(f, b));
    }
  }
  if (cards.isEmpty) return null;
  return FlashData(title, cards);
}

/// ```flashcards block: flip, swipe, mark known / again.
class FlashcardsCard extends StatefulWidget {
  const FlashcardsCard({super.key, required this.source});

  final String source;

  @override
  State<FlashcardsCard> createState() => _FlashcardsCardState();
}

class _FlashcardsCardState extends State<FlashcardsCard> {
  late FlashData? _data = parseFlashcards(widget.source);
  late List<int> _deck = _identity();
  final Set<int> _known = {}, _again = {};
  int _pos = 0;
  bool _flipped = false;

  List<int> _identity() => List.generate(_data?.cards.length ?? 0, (i) => i);

  @override
  void didUpdateWidget(FlashcardsCard old) {
    super.didUpdateWidget(old);
    if (old.source != widget.source) {
      _data = parseFlashcards(widget.source);
      _restart();
    }
  }

  bool get _finished => _pos >= _deck.length;

  void _restart() {
    setState(() {
      _deck = _identity();
      _known.clear();
      _again.clear();
      _pos = 0;
      _flipped = false;
    });
  }

  void _shuffle() {
    setState(() {
      _deck.shuffle(Random());
      _pos = 0;
      _flipped = false;
    });
  }

  void _studyAgain() {
    setState(() {
      _deck = _again.toList()..shuffle(Random());
      _again.clear();
      _pos = 0;
      _flipped = false;
    });
  }

  void _go(int delta) {
    final n = (_pos + delta).clamp(0, _deck.length);
    if (n == _pos) return;
    setState(() {
      _pos = n;
      _flipped = false;
    });
  }

  void _mark(bool knew) {
    final id = _deck[_pos];
    knew ? Haptics.received() : Haptics.tick();
    setState(() {
      if (knew) {
        _known.add(id);
        _again.remove(id);
      } else {
        _again.add(id);
        _known.remove(id);
      }
      _pos++;
      _flipped = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    if (d == null) {
      return PlayfulFallback(
        title: WidgetKitStrings.flashcards,
        source: widget.source,
      );
    }
    final p = context.palette;
    final t = context.text;
    return RichCard(
      title: d.title.isEmpty
          ? WidgetKitStrings.flashcards
          : '${WidgetKitStrings.flashcards} / ${d.title.toUpperCase()}',
      trailing: PlayfulTag(
        '${PlayfulStrings.known} ${_known.length}',
        accent: _known.isNotEmpty,
      ),
      actions: [
        RichAction(
          icon: PlayfulIcons.shuffle,
          label: PlayfulStrings.shuffle,
          onTap: () async {
            _shuffle();
            return true;
          },
        ),
        RichAction(
          icon: PlayfulIcons.restart,
          label: PlayfulStrings.restart,
          onTap: () async {
            _restart();
            return true;
          },
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PlayfulBar(value: _deck.isEmpty ? 0 : _pos / _deck.length),
          Padding(
            padding: const EdgeInsets.all(PlayfulSizes.pad),
            child: AnimatedSwitcher(
              duration: PlayfulDurations.swap,
              child: KeyedSubtree(
                key: ValueKey(_finished ? -1 : _deck[_pos]),
                child: _finished ? _end(context) : _card(context, d),
              ),
            ),
          ),
          if (!_finished)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                PlayfulSizes.pad,
                0,
                PlayfulSizes.pad,
                PlayfulSizes.pad,
              ),
              child: Row(
                children: [
                  _NavButton(
                    icon: PlayfulIcons.prev,
                    enabled: _pos > 0,
                    onTap: () => _go(-1),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: PlayfulButton(
                      label: PlayfulStrings.again,
                      icon: PlayfulIcons.restart,
                      onTap: () => _mark(false),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: PlayfulButton(
                      label: PlayfulStrings.knewIt,
                      icon: PlayfulIcons.check,
                      primary: true,
                      onTap: () => _mark(true),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _NavButton(icon: PlayfulIcons.next, onTap: () => _go(1)),
                ],
              ),
            ),
          if (!_finished)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Center(
                child: Text(
                  '${_pos + 1}/${_deck.length}',
                  style: t.caption.copyWith(color: p.textTertiary),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, FlashData d) {
    final c = d.cards[_deck[_pos]];
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Haptics.tap();
        setState(() => _flipped = !_flipped);
      },
      onHorizontalDragEnd: (e) {
        final v = e.primaryVelocity ?? 0;
        if (v.abs() < PlayfulSizes.swipeVelocity) return;
        Haptics.tap();
        _go(v < 0 ? 1 : -1);
      },
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: _flipped ? 1.0 : 0.0),
        duration: PlayfulDurations.flip,
        curve: Curves.easeInOutCubic,
        builder: (context, v, _) {
          final back = v > 0.5;
          final angle = v * pi;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, PlayfulSizes.flipPerspective)
              ..rotateY(angle),
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()..rotateY(back ? pi : 0),
              child: _Face(text: back ? c.back : c.front, back: back),
            ),
          );
        },
      ),
    );
  }

  Widget _end(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final total = _known.length + _again.length;
    return SizedBox(
      height: PlayfulSizes.cardHeight,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(PlayfulStrings.done, style: t.caption),
          const SizedBox(height: AppSpacing.sm),
          DotNumber(
            '${_known.length}/$total',
            size: PlayfulSizes.scoreFont * 0.75,
            align: Alignment.center,
            color: _again.isEmpty ? p.accent : null,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${PlayfulStrings.known} ${_known.length}  /  '
            '${PlayfulStrings.againCount} ${_again.length}',
            style: t.caption,
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            alignment: WrapAlignment.center,
            children: [
              if (_again.isNotEmpty)
                PlayfulButton(
                  label: PlayfulStrings.studyAgain,
                  icon: PlayfulIcons.restart,
                  primary: true,
                  onTap: _studyAgain,
                ),
              PlayfulButton(label: PlayfulStrings.restart, onTap: _restart),
            ],
          ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.onTap,
    this.enabled = true,
  });

  final AppIconData icon;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: PlayfulSizes.btnHeight + AppSpacing.sm,
      child: PlayfulButton(
        label: '',
        icon: icon,
        onTap: onTap,
        enabled: enabled,
      ),
    );
  }
}

class _Face extends StatelessWidget {
  const _Face({required this.text, required this.back});

  final String text;
  final bool back;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    return Container(
      height: PlayfulSizes.cardHeight,
      padding: const EdgeInsets.all(AppSpacing.lg),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: back ? p.surfaceRaised : p.background,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: back ? p.accent : p.borderStrong,
          width: AppBorder.thin,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: PlayfulSizes.cardTextMax,
                ),
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: t.title.copyWith(fontSize: PlayfulSizes.cardFont),
                ),
              ),
            ),
          ),
          if (!back) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(PlayfulStrings.tapToFlip, style: t.caption),
          ],
        ],
      ),
    );
  }
}
