import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/constants/error_copy.dart';
import '../../../../core/constants/app_icons.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/widget_github.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../data/chat_api.dart';
import '../../../../data/github_api.dart';
import '../rich/rich_frame.dart';
import 'git_graph_layout.dart';
import 'github_branch_picker.dart';
import 'github_commits_card.dart';
import 'github_common.dart';
import 'github_connect_card.dart';

/// What a ```github-graph block asks for.
class GhGraphSpec {
  const GhGraphSpec(this.ref, {this.branches = const [], this.limit});
  final GhRef ref;
  final List<String> branches;
  final int? limit;

  static final _key = RegExp(r'^(\w+)\s*:\s*(.*)$');

  /// `owner/repo`, then optional `branches: a, b` and `limit: 100` lines.
  static GhGraphSpec? parse(String source) {
    final lines = ghLines(source);
    if (lines.isEmpty) return null;
    final ref = parseGhRef(lines.first.split(RegExp(r'\s+')).first);
    if (ref == null) return null;
    var branches = <String>[];
    int? limit;
    for (final l in lines.skip(1)) {
      final m = _key.firstMatch(l);
      if (m == null) continue;
      final value = m[2]!.trim();
      switch (m[1]!.toLowerCase()) {
        case GithubGraphLang.keyBranches:
          branches = [
            for (final b in value.split(RegExp(r'[,\s]+')))
              if (b.isNotEmpty) b,
          ];
        case GithubGraphLang.keyLimit:
          final n = int.tryParse(value);
          if (n != null) {
            limit = n.clamp(
              GithubGraphLimits.minLimit,
              GithubGraphLimits.maxLimit,
            );
          }
      }
    }
    return GhGraphSpec(
      ref.ref == null || branches.contains(ref.ref)
          ? ref
          : GhRef(ref.owner, ref.repo),
      branches: [
        ...branches,
        if (ref.ref != null && !branches.contains(ref.ref)) ref.ref!,
      ],
      limit: limit,
    );
  }
}

/// ```github-graph block: the commit history as a branch/merge graph (lanes,
/// dots, curves) with subject, date, author and sha columns. Tap a row for
/// its changed files and diffs.
class GithubGraphCard extends StatelessWidget {
  const GithubGraphCard({super.key, required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    final spec = GhGraphSpec.parse(source);
    if (spec == null) {
      return GhBadBlock(
        title: GithubGraphStrings.title,
        source: source,
        hint: GithubStrings.badSpec,
      );
    }
    final url = GithubGraphStrings.webUrl(spec.ref.full);
    return RichCard(
      title: GithubStrings.titled(
        GithubGraphStrings.title,
        spec.ref.full.toUpperCase(),
      ),
      leading: const Octicon(GithubOcticons.branch),
      actions: [
        ghVisitAction(context, url),
        RichAction.copy(text: url),
      ],
      child: GhGraphView(spec: spec, height: GithubGraphSizes.cardHeight),
    );
  }
}

/// Toolbar (branch picker, chips, refresh, fullscreen), the graph table and a
/// footer. History loads page by page as the table is scrolled (or all at
/// once, up to a cap, with LOAD ALL). [height] null = fill the parent
/// (fullscreen).
class GhGraphView extends StatefulWidget {
  const GhGraphView({
    super.key,
    required this.spec,
    this.height,
    this.loader,
    this.pageLoader,
    this.branchLoader,
  });

  final GhGraphSpec spec;
  final double? height;

  /// Replaces the first-page API call (tests).
  final Future<GhGraph> Function(List<String> branches)? loader;

  /// Replaces the next-page API call (tests).
  final Future<GhGraph> Function(String cursor)? pageLoader;

  /// Replaces the branch list of the picker (tests).
  final BranchLoader? branchLoader;

  @override
  State<GhGraphView> createState() => _GhGraphViewState();
}

class _GhGraphViewState extends State<GhGraphView>
    with SingleTickerProviderStateMixin {
  GhGraph? _data;
  final _commits = <GhGraphCommit>[];
  final _seen = <String>{};
  GraphLayout? _layout;
  Map<String, int> _rowOf = const {};
  String? _next;
  int? _total;
  Object? _error;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _moreError;
  bool _loadingAll = false;
  bool _capped = false;
  int _gen = 0;

  /// Every branch seen so far (chips stay when toggled off).
  final _known = <GhGraphBranch>[];

  /// Non-default branches to show.
  late Set<String> _selected = widget.spec.branches.toSet();

  /// True once the branch set is explicit (block, chips or picker).
  late bool _custom = widget.spec.branches.isNotEmpty;
  final _open = <String>{};
  final _v = ScrollController();

  /// Horizontal offset of the text columns (the lane gutter stays put).
  final _hx = ValueNotifier<double>(0);
  double _hxMax = 0;
  late final AnimationController _fling;

  @override
  void initState() {
    super.initState();
    _fling = AnimationController.unbounded(vsync: this)
      ..addListener(() => _hx.value = _fling.value.clamp(0, _hxMax));
    _v.addListener(_maybeMore);
    _fetch();
  }

  @override
  void dispose() {
    _gen++;
    _v.dispose();
    _hx.dispose();
    _fling.dispose();
    super.dispose();
  }

  List<String> get _request {
    if (!_custom) return const [];
    if (_selected.isNotEmpty) return _selected.toList();
    final def = _data?.defaultBranch ?? '';
    return def.isEmpty ? const [] : [def];
  }

  /// Fetches again (chip toggles, picker, refresh, retry).
  void _load() {
    setState(() {
      _loading = true;
      _error = null;
      _loadingAll = false;
    });
    _fetch();
  }

  void _relayout() {
    _layout = layoutGraph(
      [for (final c in _commits) GraphNode(c.sha, c.parents)],
      defaultHead: _data?.defaultHead,
      colorCount: GithubGraphColors.lanes.length,
      more: _next != null,
    );
    _rowOf = {for (var i = 0; i < _commits.length; i++) _commits[i].sha: i};
  }

  Future<void> _fetch() async {
    final gen = ++_gen;
    try {
      final g =
          await (widget.loader?.call(_request) ??
              GithubApi.instance.graph(
                widget.spec.ref.owner,
                widget.spec.ref.repo,
                branches: _request,
                limit: widget.spec.limit ?? GithubPagingLimits.graphPage,
              ));
      if (!mounted || gen != _gen) return;
      setState(() {
        _data = g;
        _commits.clear();
        _seen.clear();
        _open.clear();
        _capped = false;
        _moreError = null;
        _append(g);
        _loading = false;
        for (final b in g.branches) {
          if (!_known.any((k) => k.name == b.name)) _known.add(b);
        }
        _known.sort((a, b) => (b.isDefault ? 1 : 0) - (a.isDefault ? 1 : 0));
        if (!_custom) {
          _selected = {
            for (final b in g.branches)
              if (!b.isDefault) b.name,
          };
        }
      });
      if (_v.hasClients) _v.jumpTo(0);
      _checkFill();
    } catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  /// Adds a page (skipping commits already shown) and lays out again.
  void _append(GhGraph g) {
    for (final c in g.commits) {
      if (_seen.add(c.sha)) _commits.add(c);
    }
    _next = g.nextCursor;
    _total = g.totalCount ?? _total;
    _relayout();
  }

  /// After a page lands: a short page may not fill the view, so no scroll
  /// would ever ask for more.
  void _checkFill() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) _maybeMore();
  });

  void _maybeMore() {
    if (!_v.hasClients || _loadingAll) return;
    if (_v.position.extentAfter < GithubPagingSizes.prefetchExtent) _more();
  }

  /// Loads the next (older) page; false when there is none or it failed.
  Future<bool> _more() async {
    final cursor = _next;
    if (cursor == null || _loadingMore || _loading) return false;
    final gen = _gen;
    setState(() {
      _loadingMore = true;
      _moreError = null;
    });
    try {
      final g =
          await (widget.pageLoader?.call(cursor) ??
              GithubApi.instance.graph(
                widget.spec.ref.owner,
                widget.spec.ref.repo,
                after: cursor,
                limit: GithubPagingLimits.graphPage,
              ));
      if (!mounted || gen != _gen) return false;
      setState(() {
        _loadingMore = false;
        _append(g);
      });
      if (!_loadingAll) _checkFill();
      return true;
    } catch (e) {
      if (!mounted || gen != _gen) return false;
      setState(() {
        _loadingMore = false;
        _moreError = e;
      });
      return false;
    }
  }

  /// LOAD ALL: pages until the history ends, STOP, or the safety cap.
  Future<void> _loadAll() async {
    if (_loadingAll) {
      setState(() => _loadingAll = false);
      return;
    }
    setState(() {
      _loadingAll = true;
      _capped = false;
    });
    while (mounted && _loadingAll && _next != null) {
      if (_commits.length >= GithubPagingLimits.loadAllCap) {
        setState(() => _capped = true);
        break;
      }
      if (!await _more()) break;
    }
    if (mounted) setState(() => _loadingAll = false);
  }

  void _toggle(GhGraphBranch b) {
    if (b.isDefault) return;
    setState(() {
      _custom = true;
      if (!_selected.remove(b.name)) _selected.add(b.name);
    });
    _load();
  }

  Future<void> _pickBranches() async {
    final picked = await showBranchPicker(
      context,
      repo: widget.spec.ref,
      selected: _selected,
      loader: widget.branchLoader,
    );
    if (picked == null || !mounted) return;
    final def = _data?.defaultBranch;
    setState(() {
      _custom = true;
      _selected = {
        for (final b in picked)
          if (b != def) b,
      };
      // New picks get chips too (their color once loaded).
      for (final b in _selected) {
        if (!_known.any((k) => k.name == b)) {
          _known.add(GhGraphBranch({'name': b}));
        }
      }
    });
    _load();
  }

  Color _branchColor(BuildContext context, GhGraphBranch b) {
    final head = _data?.branches.where((x) => x.name == b.name).firstOrNull;
    final i = _rowOf[head?.sha ?? b.sha];
    if (i == null || _layout == null) return context.palette.textTertiary;
    return GithubGraphColors.lane(_layout!.rows[i].color);
  }

  void _fullscreen() {
    final spec = GhGraphSpec(
      widget.spec.ref,
      branches: _custom ? _request : widget.spec.branches,
      limit: widget.spec.limit,
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => _GraphFullscreen(spec: spec)),
    );
  }

  void _pan(double dx) {
    _fling.stop();
    _hx.value = (_hx.value - dx).clamp(0, _hxMax);
  }

  void _panEnd(double velocity) {
    if (velocity.abs() < 1) return;
    _fling.value = _hx.value;
    _fling.animateWith(
      ClampingScrollSimulation(position: _hx.value, velocity: -velocity),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fill = widget.height == null;
    final body = _body(context);
    return Column(
      mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _toolbar(context),
        const GhDivider(),
        if (fill)
          Expanded(child: body)
        else
          SizedBox(height: widget.height, child: body),
        if (_data != null && _error == null) ...[
          const GhDivider(),
          _footer(context, _data!),
        ],
      ],
    );
  }

  Widget _toolbar(BuildContext context) {
    final p = context.palette;
    return SizedBox(
      height: GithubGraphSizes.toolbarHeight,
      child: Row(
        children: [
          _ToolButton(
            icon: GithubIcons.branch,
            label: GithubBranchStrings.title,
            onTap: _loading ? null : _pickBranches,
            color: p.textPrimary,
          ),
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              children: [
                for (final b in _known) ...[
                  _BranchChip(
                    name: b.name,
                    color: _branchColor(context, b),
                    selected: b.isDefault || _selected.contains(b.name),
                    onTap: b.isDefault ? null : () => _toggle(b),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                ],
              ],
            ),
          ),
          _ToolButton(
            icon: GithubIcons.refresh,
            label: GithubGraphStrings.refresh,
            onTap: _loading ? null : _load,
            color: p.textSecondary,
          ),
          if (widget.height != null)
            _ToolButton(
              icon: GithubIcons.fullscreen,
              label: GithubGraphStrings.fullscreen,
              onTap: _fullscreen,
              color: p.textSecondary,
            ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
    );
  }

  Widget _footer(BuildContext context, GhGraph g) {
    final p = context.palette;
    final t = context.text;
    final parts = [
      GithubPagingStrings.commitsOf(_commits.length, _total),
      GithubGraphStrings.branches(g.branches.length),
      if (_capped) GithubPagingStrings.capped(GithubPagingLimits.loadAllCap),
      if (_next == null && g.truncated) GithubGraphStrings.truncated,
      if ((_layout?.width ?? 0) > GithubGraphLimits.maxLanes)
        GithubGraphStrings.overflow,
    ];
    final busy = _loadingAll || _loadingMore;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Thin progress bar while LOAD ALL runs (share of the cap).
        if (_loadingAll)
          LinearProgressIndicator(
            minHeight: GithubPagingSizes.progress,
            value: (_commits.length / GithubPagingLimits.loadAllCap).clamp(
              0,
              1,
            ),
            color: p.textPrimary,
            backgroundColor: p.border,
          ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: GithubSizes.pad,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _loadingAll
                      ? GithubPagingStrings.loadingAll(
                          _commits.length,
                          GithubPagingLimits.loadAllCap,
                        )
                      : parts.join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.caption,
                ),
              ),
              if (_next != null && !_capped)
                GhTap(
                  onTap: _loadAll,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                      vertical: AppSpacing.xs,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppIcon(
                          _loadingAll
                              ? GithubPagingIcons.stop
                              : GithubPagingIcons.loadAll,
                          size: AppIconSize.sm,
                          color: busy ? p.accent : p.textSecondary,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          _loadingAll
                              ? GithubPagingStrings.stop
                              : GithubPagingStrings.loadAll,
                          style: t.caption.copyWith(color: p.textPrimary),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _body(BuildContext context) {
    final e = _error;
    if (e != null) {
      if (e is ApiException && e.status == 409) {
        return SingleChildScrollView(
          child: GithubConnectPanel(paper: context.palette.codeBackground),
        );
      }
      return Align(
        alignment: Alignment.topCenter,
        child: GhError(
          message: e is ApiException
              ? (e.status == 404
                    ? GithubGraphStrings.notFound
                    : friendlyException(e))
              : GithubStrings.loadFailed,
          onRetry: _load,
        ),
      );
    }
    final g = _data;
    final layout = _layout;
    if (g == null || layout == null) {
      return const ClipRect(
        child: GhSkeleton(rows: GithubGraphSizes.skeletonRows),
      );
    }
    if (_commits.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(GithubSizes.pad),
        child: Text(GithubGraphStrings.empty, style: context.text.bodySmall),
      );
    }
    return AnimatedOpacity(
      duration: GithubDurations.expand,
      opacity: _loading ? GithubGraphColors.mergeTextAlpha : 1,
      child: IgnorePointer(ignoring: _loading, child: _table(context, layout)),
    );
  }

  Widget _table(BuildContext context, GraphLayout layout) {
    final lanes = math.min(layout.width, GithubGraphLimits.maxLanes);
    final overflow = layout.width > GithubGraphLimits.maxLanes;
    final graphW =
        GithubGraphSizes.graphPad * 2 +
        math.max(lanes - 1, 0) * GithubGraphSizes.laneWidth +
        (overflow ? GithubGraphSizes.overflowGap * 3 : 0);
    const gap = GithubGraphSizes.colGap;
    const fixedRight =
        gap * 3 +
        GithubGraphSizes.dateWidth +
        GithubGraphSizes.authorWidth +
        GithubGraphSizes.shaWidth;
    final repo = GhRef(widget.spec.ref.owner, widget.spec.ref.repo);
    return LayoutBuilder(
      builder: (context, c) {
        final viewport = math.max(c.maxWidth - graphW, 0.0);
        final subject = math.max(
          viewport - fixedRight - gap,
          GithubGraphSizes.subjectMin,
        );
        final content = subject + gap + fixedRight;
        _hxMax = math.max(content - viewport, 0);
        final cols = _Columns(
          graph: graphW,
          subject: subject,
          content: content,
        );
        final pan = _Pan(offset: _hx, max: _hxMax, onPan: _pan, onEnd: _panEnd);
        final tail = _next != null || _moreError != null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _HeaderRow(cols: cols, pan: pan),
            const GhDivider(),
            Expanded(
              child: ListView.builder(
                controller: _v,
                padding: EdgeInsets.zero,
                itemCount: _commits.length + (tail ? 1 : 0),
                itemBuilder: (context, i) {
                  if (i >= _commits.length) {
                    final err = _moreError;
                    if (err != null) {
                      return GhError(
                        message: err is ApiException
                            ? friendlyException(err)
                            : GithubStrings.loadFailed,
                        onRetry: _more,
                      );
                    }
                    return const GhLoadingRow(
                      label: GithubPagingStrings.loadingMore,
                    );
                  }
                  final c = _commits[i];
                  return _GraphRowView(
                    key: ValueKey(c.sha),
                    repo: repo,
                    commit: c,
                    row: layout.rows[i],
                    cols: cols,
                    pan: pan,
                    open: _open.contains(c.sha),
                    onTap: () => setState(() {
                      if (!_open.remove(c.sha)) _open.add(c.sha);
                    }),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Columns {
  const _Columns({
    required this.graph,
    required this.subject,
    required this.content,
  });

  /// Lane gutter, subject column, and all text columns together.
  final double graph, subject, content;
}

/// Shared horizontal pan of the text columns.
class _Pan {
  const _Pan({
    required this.offset,
    required this.max,
    required this.onPan,
    required this.onEnd,
  });
  final ValueNotifier<double> offset;

  /// Largest offset for the current width (the notifier may hold more
  /// after a resize; it is clamped when drawn).
  final double max;
  final void Function(double dx) onPan;
  final void Function(double velocity) onEnd;
}

/// The text columns of one row, shifted by the shared pan offset and clipped
/// to the space right of the lane gutter. Drag sideways to pan.
class _PannedColumns extends StatelessWidget {
  const _PannedColumns({
    required this.pan,
    required this.width,
    required this.child,
  });

  final _Pan pan;
  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    onHorizontalDragUpdate: (d) => pan.onPan(d.delta.dx),
    onHorizontalDragEnd: (d) => pan.onEnd(d.velocity.pixelsPerSecond.dx),
    child: ClipRect(
      child: ValueListenableBuilder<double>(
        valueListenable: pan.offset,
        child: child,
        builder: (context, x, child) => OverflowBox(
          alignment: Alignment.centerLeft,
          minWidth: width,
          maxWidth: width,
          child: Transform.translate(
            offset: Offset(-x.clamp(0.0, pan.max), 0),
            child: child,
          ),
        ),
      ),
    ),
  );
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.color,
  });

  final AppIconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final button = Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: AppIcon(
        icon,
        size: AppIconSize.sm,
        color: onTap == null ? context.palette.textTertiary : color,
        semanticLabel: label,
      ),
    );
    if (onTap == null) return button;
    return GhTap(onTap: onTap!, child: button);
  }
}

class _BranchChip extends StatelessWidget {
  const _BranchChip({
    required this.name,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final Color color;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final chip = Container(
      height: GithubSizes.chipHeight,
      padding: const EdgeInsets.symmetric(horizontal: GithubSizes.chipPadH),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(
          color: selected ? color : p.border,
          width: AppBorder.thin,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: GithubGraphSizes.chipDot,
            height: GithubGraphSizes.chipDot,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? color : null,
              border: Border.all(
                color: selected ? color : p.textTertiary,
                width: AppBorder.thin,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            name,
            style: context.text.caption.copyWith(
              color: selected ? p.textPrimary : p.textTertiary,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return chip;
    return GhTap(onTap: onTap!, child: chip);
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.cols, required this.pan});

  final _Columns cols;
  final _Pan pan;

  @override
  Widget build(BuildContext context) {
    final t = context.text.caption;
    Widget cell(String s, double w) => SizedBox(
      width: w,
      child: Text(s, maxLines: 1, overflow: TextOverflow.clip, style: t),
    );
    const gap = SizedBox(width: GithubGraphSizes.colGap);
    return SizedBox(
      height: GithubGraphSizes.headerHeight,
      child: Row(
        children: [
          SizedBox(
            width: cols.graph,
            child: Padding(
              padding: const EdgeInsets.only(left: AppSpacing.sm),
              child: Text(
                GithubGraphStrings.colGraph,
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: t,
              ),
            ),
          ),
          Expanded(
            child: _PannedColumns(
              pan: pan,
              width: cols.content,
              child: Row(
                children: [
                  cell(GithubGraphStrings.colSubject, cols.subject),
                  gap,
                  cell(GithubGraphStrings.colDate, GithubGraphSizes.dateWidth),
                  gap,
                  cell(
                    GithubGraphStrings.colAuthor,
                    GithubGraphSizes.authorWidth,
                  ),
                  gap,
                  cell(GithubGraphStrings.colSha, GithubGraphSizes.shaWidth),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One commit: lane gutter (fixed) + panned text columns; when open, the
/// commit detail spans the full width below it (outside the panned area, so
/// diffs wrap and scroll on their own) while the lanes keep running alongside.
class _GraphRowView extends StatelessWidget {
  const _GraphRowView({
    super.key,
    required this.repo,
    required this.commit,
    required this.row,
    required this.cols,
    required this.pan,
    required this.open,
    required this.onTap,
  });

  final GhRef repo;
  final GhGraphCommit commit;
  final GraphRow row;
  final _Columns cols;
  final _Pan pan;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final c = commit;
    final laneColor = GithubGraphColors.lane(row.color);
    final dim = row.merge ? GithubGraphColors.mergeTextAlpha : 1.0;
    final primary = p.textPrimary.withValues(alpha: dim);
    final secondary = p.textSecondary.withValues(alpha: dim);
    const gap = SizedBox(width: GithubGraphSizes.colGap);
    final cells = Row(
      children: [
        SizedBox(
          width: cols.subject,
          child: Row(
            children: [
              for (final r in c.refs.take(GithubGraphLimits.refsShown)) ...[
                _RefPill(name: r, color: laneColor),
                const SizedBox(width: AppSpacing.xs),
              ],
              if (c.refs.length > GithubGraphLimits.refsShown) ...[
                Text(
                  GithubGraphStrings.moreRefs(
                    c.refs.length - GithubGraphLimits.refsShown,
                  ),
                  style: t.caption.copyWith(color: laneColor),
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
              Expanded(
                child: Text(
                  c.subject,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodySmall.copyWith(color: primary, height: 1),
                ),
              ),
            ],
          ),
        ),
        gap,
        SizedBox(
          width: GithubGraphSizes.dateWidth,
          child: Text(
            GithubGraphStrings.dateTime(c.date),
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: t.caption.copyWith(color: secondary),
          ),
        ),
        gap,
        SizedBox(
          width: GithubGraphSizes.authorWidth,
          child: Text(
            c.author,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.caption.copyWith(color: secondary),
          ),
        ),
        gap,
        SizedBox(
          width: GithubGraphSizes.shaWidth,
          child: Align(
            alignment: Alignment.centerLeft,
            child: GhChip(c.shortSha, onTap: () => ghCopy(context, c.sha)),
          ),
        ),
      ],
    );
    return Container(
      color: open ? p.surfaceRaised : null,
      child: CustomPaint(
        painter: _LanePainter(
          row: row,
          graphWidth: cols.graph,
          head: c.refs.isNotEmpty,
          background: open ? p.surfaceRaised : p.codeBackground,
          overflowColor: p.textTertiary,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GhTap(
              onTap: onTap,
              child: SizedBox(
                height: GithubGraphSizes.rowHeight,
                child: Row(
                  children: [
                    SizedBox(width: cols.graph),
                    Expanded(
                      child: _PannedColumns(
                        pan: pan,
                        width: cols.content,
                        child: cells,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (open)
              Padding(
                padding: EdgeInsets.only(
                  left: cols.graph,
                  right: GithubSizes.pad,
                  bottom: AppSpacing.sm,
                ),
                child: GhCommitDetail(repo: repo, sha: c.sha),
              ),
          ],
        ),
      ),
    );
  }
}

class _RefPill extends StatelessWidget {
  const _RefPill({required this.name, required this.color});

  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    height: GithubGraphSizes.pillHeight,
    constraints: const BoxConstraints(maxWidth: GithubGraphSizes.pillMaxWidth),
    padding: const EdgeInsets.symmetric(horizontal: GithubGraphSizes.pillPadH),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: color.withValues(alpha: GithubGraphColors.pillFillAlpha),
      borderRadius: BorderRadius.circular(AppRadius.pill),
      border: Border.all(color: color, width: AppBorder.thin),
    ),
    child: Text(
      name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: context.text.caption.copyWith(color: color, height: 1),
    ),
  );
}

/// Draws one row of the lane column: the curves from the row above, the
/// commit dot, and the lines toward the row below (straight down through an
/// expanded detail, then curving into place).
class _LanePainter extends CustomPainter {
  _LanePainter({
    required this.row,
    required this.graphWidth,
    required this.head,
    required this.background,
    required this.overflowColor,
  });

  final GraphRow row;
  final double graphWidth;
  final bool head;
  final Color background, overflowColor;

  static const _h = GithubGraphSizes.rowHeight;
  static const _c = _h / 2;
  static const _last = GithubGraphLimits.maxLanes - 1;

  double _x(int col) =>
      GithubGraphSizes.graphPad +
      math.min(col, _last) * GithubGraphSizes.laneWidth;

  Paint _stroke(Color color) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = GithubGraphSizes.line
    ..strokeCap = StrokeCap.round;

  void _curve(
    Canvas canvas,
    double x1,
    double y1,
    double x2,
    double y2,
    Paint paint,
  ) {
    if (x1 == x2) {
      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), paint);
      return;
    }
    final d = (y2 - y1) * GithubGraphSizes.curve;
    canvas.drawPath(
      Path()
        ..moveTo(x1, y1)
        ..cubicTo(x1, y1 + d, x2, y2 - d, x2, y2),
      paint,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, graphWidth, size.height));
    for (final l in row.up) {
      _curve(
        canvas,
        _x(l.from),
        _c - _h,
        _x(l.to),
        _c,
        _stroke(GithubGraphColors.lane(l.color)),
      );
    }
    // Where the lines toward the next row start bending (below a detail).
    final bend = math.max(_c, size.height - _c);
    for (final l in row.down) {
      final paint = _stroke(GithubGraphColors.lane(l.color));
      final x = _x(l.from);
      if (bend > _c) canvas.drawLine(Offset(x, _c), Offset(x, bend), paint);
      _curve(canvas, x, bend, _x(l.to), bend + _h, paint);
    }
    final color = GithubGraphColors.lane(row.color);
    final cx = _x(row.lane);
    final faded = _stroke(
      color.withValues(alpha: GithubGraphColors.danglingAlpha),
    );
    if (row.danglingFirst) {
      canvas.drawLine(Offset(cx, _c), Offset(cx, size.height), faded);
    }
    for (var i = 0; i < row.danglingExtra; i++) {
      final dx = GithubGraphSizes.laneWidth * (0.6 + 0.3 * i);
      canvas.drawLine(Offset(cx, _c), Offset(cx + dx, _c + _h * 0.45), faded);
    }

    final center = Offset(cx, _c);
    if (head) {
      canvas.drawCircle(
        center,
        GithubGraphSizes.dot + GithubGraphSizes.headRing,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = AppBorder.thin,
      );
    }
    if (row.merge) {
      canvas.drawCircle(
        center,
        GithubGraphSizes.dot,
        Paint()..color = background,
      );
      canvas.drawCircle(
        center,
        GithubGraphSizes.dot - GithubGraphSizes.mergeDotStroke / 2,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = GithubGraphSizes.mergeDotStroke,
      );
    } else {
      canvas.drawCircle(center, GithubGraphSizes.dot, Paint()..color = color);
    }

    if (row.width > GithubGraphLimits.maxLanes) {
      final dot = Paint()..color = overflowColor;
      final x0 = _x(_last) + GithubGraphSizes.laneWidth * 0.6;
      for (var i = 0; i < 3; i++) {
        canvas.drawCircle(
          Offset(x0 + i * GithubGraphSizes.overflowGap, _c),
          GithubGraphSizes.overflowDot,
          dot,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LanePainter old) =>
      old.row != row ||
      old.graphWidth != graphWidth ||
      old.head != head ||
      old.background != background ||
      old.overflowColor != overflowColor;
}

/// Full-page graph for a closer look.
class _GraphFullscreen extends StatelessWidget {
  const _GraphFullscreen({required this.spec});

  final GhGraphSpec spec;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.codeBackground,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: AppSizes.appBarHeight,
              padding: const EdgeInsets.symmetric(
                horizontal: GithubGraphSizes.fullscreenPad,
              ),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: p.border)),
              ),
              child: Row(
                children: [
                  GhTap(
                    onTap: () => Navigator.of(context).pop(),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      child: AppIcon(
                        GithubIcons.back,
                        color: p.textPrimary,
                        semanticLabel: GithubGraphStrings.back,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  const Octicon(GithubOcticons.branch),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      GithubStrings.titled(
                        GithubGraphStrings.title,
                        spec.ref.full.toUpperCase(),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.label,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: GhGraphView(spec: spec)),
          ],
        ),
      ),
    );
  }
}
