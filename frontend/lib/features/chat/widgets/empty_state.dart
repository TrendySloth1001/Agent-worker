import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/home_copy.dart';
import '../../../core/constants/suggest.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/mascot.dart';
import '../../../data/conversation.dart';
import '../../../data/suggest_api.dart';
import 'home_widgets.dart';

/// Picks a card category for a personalised starter from its wording.
StarterKind kindOfPrompt(String prompt) {
  final s = prompt.toLowerCase();
  bool has(List<String> words) => words.any(s.contains);
  if (has(['compare', ' vs ', 'versus', 'difference', 'pros and cons'])) {
    return StarterKind.compare;
  }
  if (has(['plan', 'schedule', 'roadmap', 'organi', 'prioriti'])) {
    return StarterKind.plan;
  }
  if (has(['write', 'draft', 'summar', 'rewrite', 'email', 'essay'])) {
    return StarterKind.write;
  }
  if (has([
    'build',
    'code',
    'debug',
    'fix',
    'implement',
    'flutter',
    'bug',
    'api',
    'design',
    'review',
    'refactor',
  ])) {
    return StarterKind.build;
  }
  return StarterKind.learn;
}

/// The greeting for [now]: "Good evening" and so on.
String greetingFor(DateTime now) {
  final h = now.hour;
  if (h >= 5 && h < 12) return HomeStrings.morning;
  if (h >= 12 && h < 17) return HomeStrings.afternoon;
  if (h >= 17 && h < 22) return HomeStrings.evening;
  return HomeStrings.night;
}

/// The new-chat home: a time-aware greeting, starter cards, feature chips and
/// the latest chats, anchored above the composer. Sections drop out in
/// priority order as space runs short (keyboard, landscape).
class EmptyState extends StatefulWidget {
  const EmptyState({
    super.key,
    this.onSuggestion,
    this.onEdit,
    this.onCapability,
    this.isOn,
    this.recentLoader,
    this.onOpenChat,
    this.name,
    this.now,
    this.startersLoader,
    this.bottomClear,
  });

  /// Sends a starter prompt; starters are hidden when null.
  final ValueChanged<String>? onSuggestion;

  /// Puts a starter in the composer to edit (long-press).
  final ValueChanged<String>? onEdit;

  /// A capability chip was tapped; chips are hidden when null.
  final ValueChanged<HomeCapability>? onCapability;

  /// Whether a capability is currently on (its chip is filled).
  final bool Function(HomeCapability)? isOn;

  /// Latest chats for "Continue"; the row is hidden when null.
  final Future<List<ConversationSummary>> Function()? recentLoader;
  final ValueChanged<String>? onOpenChat;

  /// First name for the greeting.
  final String? name;

  /// Clock override for tests.
  final DateTime? now;

  /// Personalised starters; defaults to `GET /assist/starters`.
  final Future<List<String>> Function()? startersLoader;

  /// Height the composer covers at the bottom, when the screen knows it.
  final double? bottomClear;

  @visibleForTesting
  static void resetCache() {
    _EmptyStateState._cached = const [];
    _EmptyStateState._cachedAt = null;
    _EmptyStateState._recent = const [];
    _EmptyStateState._recentAt = null;
  }

  @override
  State<EmptyState> createState() => _EmptyStateState();
}

class _EmptyStateState extends State<EmptyState>
    with SingleTickerProviderStateMixin {
  /// Starters from recent chats, kept for the session so new chats show
  /// them at once; the built-in prompts fill in until they arrive.
  static List<String> _cached = const [];
  static DateTime? _cachedAt;

  /// Latest chats, shown at once and refreshed when stale.
  static List<ConversationSummary> _recent = const [];
  static DateTime? _recentAt;
  static const _recentTtl = Duration(seconds: 20);

  List<String> _prompts = _cached;
  List<ConversationSummary> _chats = _recent;
  int _page = 0;

  late final _enter = AnimationController(
    vsync: this,
    duration: HomeSizes.entrance,
  );
  late final int _subline = DateTime.now().millisecondsSinceEpoch;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    final at = _cachedAt;
    if (at == null ||
        DateTime.now().difference(at) >= SuggestConfig.startersTtl) {
      (widget.startersLoader ?? SuggestApi().starters)().then((list) {
        if (list.isEmpty) return;
        _cached = list;
        _cachedAt = DateTime.now();
        if (mounted) setState(() => _prompts = list);
      });
    }
    final load = widget.recentLoader;
    final rAt = _recentAt;
    if (load != null &&
        (rAt == null || DateTime.now().difference(rAt) >= _recentTtl)) {
      load()
          .then((list) {
            _recent = list;
            _recentAt = DateTime.now();
            if (mounted) setState(() => _chats = list);
          })
          .catchError((_) {});
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _enter.value = 1;
    } else {
      _enter.forward();
    }
  }

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  /// Personalised starters first, then the built-ins; a page is four cards.
  List<Starter> get _pool => [
    for (final p in _prompts) Starter(kindOfPrompt(p), p, p),
    ...fallbackStarters,
  ];

  List<Starter> get _shown {
    final pool = _pool;
    final n = HomeSizes.poolShown;
    return [for (var i = 0; i < n; i++) pool[(_page * n + i) % pool.length]];
  }

  void _shuffle() {
    Haptics.tap();
    setState(() => _page++);
  }

  /// Staggered fade and rise for the section at [index].
  Widget _reveal(int index, Widget child) {
    final start =
        (index * HomeSizes.staggerMs) / HomeSizes.entrance.inMilliseconds;
    final curve = CurvedAnimation(
      parent: _enter,
      curve: Interval(start.clamp(0.0, 0.7), 1, curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: curve,
      child: child,
      builder: (context, child) => Opacity(
        opacity: curve.value,
        child: Transform.translate(
          offset: Offset(0, (1 - curve.value) * HomeSizes.rise),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final scale = MediaQuery.textScalerOf(
      context,
    ).scale(1.0).clamp(1.0, 1.6).toDouble();
    final top = padding.top + AppSizes.topInset;
    final bottom =
        (widget.bottomClear ??
            padding.bottom + AppSpacing.md + AppSizes.bottomInset) +
        AppSpacing.md;
    return LayoutBuilder(
      builder: (context, box) {
        final room = box.maxHeight - top - bottom;
        const gap = HomeSizes.sectionGap;
        final send = widget.onSuggestion;

        // What fits, in priority order: greeting, starters, chips, recents.
        final fullHeader = HomeSizes.headerFull * scale;
        final compactHeader = HomeSizes.headerCompact * scale;
        final grid = HomeSizes.gridBlock * scale;
        final row = HomeSizes.rowBlock * scale;
        var left = room;
        var compactHead = false;
        var mode = 0; // 0 none, 1 row, 2 grid
        if (send != null && left >= fullHeader + gap + grid) {
          mode = 2;
          left -= fullHeader + gap + grid;
        } else if (send != null && left >= fullHeader + gap + row) {
          mode = 1;
          left -= fullHeader + gap + row;
        } else if (send != null && left >= compactHeader + gap + row) {
          mode = 1;
          compactHead = true;
          left -= compactHeader + gap + row;
        } else {
          compactHead = left < fullHeader;
          left -= compactHead ? compactHeader : fullHeader;
        }
        final showChips =
            widget.onCapability != null &&
            mode != 0 &&
            left >= gap + HomeSizes.chipsBlock;
        if (showChips) left -= gap + HomeSizes.chipsBlock;
        final chats = _chats.take(2).toList();
        final recentRows = chats.isEmpty
            ? 0
            : left >= gap + HomeSizes.recentBlock + HomeSizes.recentRow
            ? chats.length
            : left >= gap + HomeSizes.recentBlock
            ? 1
            : 0;
        final showRecent =
            widget.onOpenChat != null && mode != 0 && recentRows > 0;
        if (showRecent) {
          left -= gap + HomeSizes.recentBlock;
          if (recentRows > 1) left -= HomeSizes.recentRow;
        }
        // Plenty of height: the mascot steps above a bigger greeting.
        final roomy = mode == 2 && left >= HomeSizes.roomyExtra * scale;

        var i = 0;
        const edge = EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding);
        final body = <Widget>[
          _reveal(
            i++,
            Padding(padding: edge, child: _header(context, compactHead, roomy)),
          ),
          if (mode != 0) ...[
            const SizedBox(height: gap),
            _reveal(
              i++,
              mode == 2
                  ? Padding(padding: edge, child: _grid(context))
                  : _row(context, scale),
            ),
          ],
          if (showChips) ...[
            const SizedBox(height: gap),
            _reveal(i++, _chips(context)),
          ],
          if (showRecent) ...[
            const SizedBox(height: gap),
            _reveal(
              i++,
              Padding(
                padding: edge,
                child: _recentBlock(context, chats.take(recentRows).toList()),
              ),
            ),
          ],
        ];
        return Padding(
          padding: EdgeInsets.only(top: top, bottom: bottom),
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: (box.maxHeight - top - bottom).clamp(0, 9999),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: body,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _header(BuildContext context, bool compact, bool roomy) {
    final p = context.palette;
    final t = context.text;
    final hello = HomeStrings.greeting(
      greetingFor(widget.now ?? DateTime.now()),
      widget.name,
    );
    final sub = HomeStrings.sublines[_subline % HomeStrings.sublines.length];
    final mascot = Mascot(
      state: MascotState.idle,
      size: compact
          ? HomeSizes.mascotCompact
          : roomy
          ? HomeSizes.mascotRoomy
          : HomeSizes.mascot,
    );
    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          hello,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: t.headline.copyWith(
            fontSize: compact
                ? HomeSizes.greetingCompact
                : roomy
                ? HomeSizes.greetingRoomy
                : HomeSizes.greetingSize,
            letterSpacing: -0.6,
            height: 1.15,
          ),
        ),
        if (!compact) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.bodySmall.copyWith(
              fontSize: HomeSizes.sublineSize,
              color: p.textSecondary,
            ),
          ),
        ],
      ],
    );
    return Semantics(
      container: true,
      header: true,
      label: '$hello. $sub',
      excludeSemantics: true,
      child: roomy
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                mascot,
                const SizedBox(height: AppSpacing.lg),
                texts,
              ],
            )
          : Row(
              children: [
                mascot,
                const SizedBox(width: AppSpacing.md),
                Expanded(child: texts),
              ],
            ),
    );
  }

  Widget _label(BuildContext context, String text, {bool shuffle = false}) {
    final p = context.palette;
    return SizedBox(
      height: HomeSizes.labelRow,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(text, style: context.text.caption),
          ),
          if (shuffle)
            Positioned(
              right: -AppSpacing.md,
              top: (HomeSizes.labelRow - HomeSizes.hit) / 2,
              child: Semantics(
                button: true,
                excludeSemantics: true,
                label: HomeStrings.shuffle,
                onTap: _shuffle,
                child: InkResponse(
                  radius: HomeSizes.hit / 2,
                  onTap: _shuffle,
                  child: SizedBox.square(
                    dimension: HomeSizes.hit,
                    child: AppIcon(
                      HomeIcons.shuffle,
                      size: AppIconSize.md,
                      color: p.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  StarterCard _card(Starter s, {bool compact = false}) => StarterCard(
    compact: compact,
    starter: s,
    onSend: () => widget.onSuggestion?.call(s.prompt),
    onEdit: () => (widget.onEdit ?? widget.onSuggestion)?.call(s.prompt),
  );

  Widget _grid(BuildContext context) {
    final cards = _shown;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label(context, HomeStrings.tryAsking, shuffle: true),
        for (var r = 0; r < cards.length; r += 2) ...[
          if (r > 0) const SizedBox(height: HomeSizes.cardGap),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _card(cards[r])),
                const SizedBox(width: HomeSizes.cardGap),
                Expanded(
                  child: r + 1 < cards.length
                      ? _card(cards[r + 1])
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// One scrollable row of cards, for short screens.
  Widget _row(BuildContext context, double scale) {
    final cards = _shown;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenPadding,
          ),
          child: _label(context, HomeStrings.tryAsking, shuffle: true),
        ),
        SizedBox(
          height: HomeSizes.cardCompactHeight * scale,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenPadding,
            ),
            itemCount: cards.length,
            separatorBuilder: (_, _) =>
                const SizedBox(width: HomeSizes.cardGap),
            itemBuilder: (context, i) => SizedBox(
              width: HomeSizes.cardCompactWidth,
              child: _card(
                Starter(cards[i].kind, cards[i].title, cards[i].prompt),
                compact: true,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _chips(BuildContext context) {
    final on = widget.isOn ?? (_) => false;
    return SizedBox(
      height: HomeSizes.hit,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenPadding,
        ),
        itemCount: HomeCapability.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, i) {
          final c = HomeCapability.values[i];
          return CapabilityChip(
            capability: c,
            on: on(c),
            onTap: () => widget.onCapability!(c),
          );
        },
      ),
    );
  }

  Widget _recentBlock(BuildContext context, List<ConversationSummary> chats) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 28,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(HomeStrings.continueTitle, style: context.text.caption),
          ),
        ),
        RecentChats(chats: chats, onOpen: widget.onOpenChat!),
      ],
    );
  }
}
