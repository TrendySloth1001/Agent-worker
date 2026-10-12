import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/widget_github.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../data/chat_api.dart';
import '../../../../data/github_api.dart';
import '../rich/playful_common.dart';
import 'github_common.dart';

/// Loads one page of branches (tests replace the API).
typedef BranchLoader = Future<GhBranchPage> Function(String q, String? after);

/// Searchable sheet over every branch of [repo]. [multi]: pick several
/// (the default branch always stays in) and APPLY, with an "all branches"
/// toggle that takes the newest [maxSelected]; otherwise one tap picks one.
/// Returns the chosen names, or null when dismissed.
Future<Set<String>?> showBranchPicker(
  BuildContext context, {
  required GhRef repo,
  Set<String> selected = const {},
  bool multi = true,
  int maxSelected = GithubBranchLimits.maxSelected,
  BranchLoader? loader,
}) {
  return showModalBottomSheet<Set<String>>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _BranchPicker(
      loader:
          loader ??
          (q, after) => GithubApi.instance.branches(
            repo.owner,
            repo.repo,
            q: q,
            after: after,
          ),
      selected: selected,
      multi: multi,
      maxSelected: maxSelected,
    ),
  );
}

class _BranchPicker extends StatefulWidget {
  const _BranchPicker({
    required this.loader,
    required this.selected,
    required this.multi,
    required this.maxSelected,
  });

  final BranchLoader loader;
  final Set<String> selected;
  final bool multi;
  final int maxSelected;

  @override
  State<_BranchPicker> createState() => _BranchPickerState();
}

class _BranchPickerState extends State<_BranchPicker> {
  final _items = <GhBranch>[];
  late final Set<String> _picked = {...widget.selected};

  /// Newest branches (unfiltered first page) for "all branches".
  List<GhBranch> _recent = const [];
  String _default = '';
  String? _next;
  int _total = 0, _matches = 0;
  bool _loading = true;
  Object? _error;
  String _q = '';
  int _gen = 0;
  Timer? _debounce;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeMore);
    _load(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({required bool reset}) async {
    final gen = reset ? ++_gen : _gen;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.loader(_q, reset ? null : _next);
      if (!mounted || gen != _gen) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(page.items);
        _next = page.nextCursor;
        _total = page.totalCount;
        _matches = page.matchCount;
        _default = page.defaultBranch;
        if (_q.isEmpty && _recent.isEmpty) {
          _recent = [
            for (final b in page.items)
              if (!b.isDefault) b,
          ];
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _maybeMore() {
    if (_loading || _next == null || !_scroll.hasClients) return;
    if (_scroll.position.extentAfter < GithubPagingSizes.prefetchExtent) {
      _load(reset: false);
    }
  }

  void _onFilter(String text) {
    _debounce?.cancel();
    _debounce = Timer(AppDurations.searchDebounce, () {
      _q = text.trim();
      _load(reset: true);
    });
  }

  bool get _allOn {
    final want = _recent.take(widget.maxSelected);
    return want.isNotEmpty && want.every((b) => _picked.contains(b.name));
  }

  void _toggleAll() => setState(() {
    if (_allOn) {
      _picked.clear();
    } else {
      _picked
        ..clear()
        ..addAll(_recent.take(widget.maxSelected).map((b) => b.name));
    }
  });

  void _tap(GhBranch b) {
    if (!widget.multi) {
      Navigator.pop(context, {b.name});
      return;
    }
    if (b.isDefault) return;
    setState(() {
      if (!_picked.remove(b.name) && _picked.length < widget.maxSelected) {
        _picked.add(b.name);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SizedBox(
        height: media.size.height * GithubPagingSizes.sheetHeightFactor,
        child: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenPadding,
                  AppSpacing.lg,
                  AppSpacing.screenPadding,
                  AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    const Octicon(GithubOcticons.branch),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        _total == 0
                            ? GithubBranchStrings.title
                            : GithubBranchStrings.countOf(
                                _q.isEmpty ? _total : _matches,
                                _total,
                              ),
                        style: t.caption,
                      ),
                    ),
                    if (widget.multi)
                      PlayfulButton(
                        label: GithubBranchStrings.apply,
                        icon: GithubPagingIcons.check,
                        onTap: () => Navigator.pop(context, {..._picked}),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenPadding,
                ),
                child: GhSearchField(
                  hint: GithubBranchStrings.filterHint,
                  onChanged: _onFilter,
                  autofocus: false,
                ),
              ),
              if (widget.multi)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenPadding,
                    AppSpacing.sm,
                    AppSpacing.screenPadding,
                    0,
                  ),
                  child: Row(
                    children: [
                      GhTap(
                        onTap: _toggleAll,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GhCheck(on: _allOn),
                            const SizedBox(width: AppSpacing.sm),
                            Text(
                              GithubBranchStrings.all,
                              style: t.caption.copyWith(color: p.textPrimary),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _picked.length >= widget.maxSelected
                            ? GithubBranchStrings.cap(widget.maxSelected)
                            : GithubBranchStrings.selected(_picked.length),
                        style: t.caption.copyWith(
                          color: _picked.length >= widget.maxSelected
                              ? p.accent
                              : p.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: AppSpacing.sm),
              const GhDivider(),
              Expanded(child: _list(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _list(BuildContext context) {
    final t = context.text;
    final e = _error;
    if (e != null && _items.isEmpty) {
      return GhError(
        message: e is ApiException ? e.message : GithubStrings.loadFailed,
        onRetry: () => _load(reset: true),
      );
    }
    if (_items.isEmpty) {
      return _loading
          ? const GhSkeleton(rows: GithubGraphSizes.skeletonRows)
          : Padding(
              padding: const EdgeInsets.all(AppSpacing.screenPadding),
              child: Text(GithubBranchStrings.none, style: t.bodySmall),
            );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
      itemCount: _items.length + (_next != null ? 1 : 0),
      itemBuilder: (context, i) {
        if (i >= _items.length) return const GhLoadingRow();
        final b = _items[i];
        final on = b.isDefault && widget.multi
            ? true
            : _picked.contains(b.name) ||
                  (!widget.multi && _picked.isEmpty && b.name == _default);
        return _BranchRow(
          branch: b,
          on: on,
          locked: widget.multi && b.isDefault,
          onTap: () => _tap(b),
        );
      },
    );
  }
}

class _BranchRow extends StatelessWidget {
  const _BranchRow({
    required this.branch,
    required this.on,
    required this.locked,
    required this.onTap,
  });

  final GhBranch branch;
  final bool on, locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final b = branch;
    return GhTap(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: p.border)),
        ),
        child: Row(
          children: [
            GhCheck(on: on, muted: locked),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                b.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.bodySmall.copyWith(
                  color: on ? p.textPrimary : p.textSecondary,
                ),
              ),
            ),
            if (b.isDefault) ...[
              const SizedBox(width: AppSpacing.sm),
              GhChip(GithubBranchStrings.isDefault),
            ],
            const SizedBox(width: AppSpacing.sm),
            Text(GithubStrings.ago(b.date), style: t.caption),
          ],
        ),
      ),
    );
  }
}
