import 'package:flutter/material.dart';

import '../../core/constants/app_sizes.dart';
import '../../core/constants/github_detail.dart';
import '../../core/constants/widget_github.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/m3_kit_extras.dart';
import '../../data/github_api.dart';
import 'gh_actions.dart';
import 'gh_item_controller.dart';
import 'github_controller.dart';
import 'widgets/diff_view.dart';
import 'widgets/gh_detail_header.dart';
import 'widgets/gh_item_view.dart';
import 'widgets/gh_pr_tabs.dart';
import 'widgets/gh_rows.dart';
import 'widgets/gh_sheets.dart';

/// One pull request, in-app: the header with Ask Sparky, then the
/// Conversation (description, comments, reviews, events and the comment
/// box), Commits, Files changed and Checks tabs. Review, merge, close,
/// labels and edits run here when the viewer may; otherwise they explain
/// why. "Open on GitHub" stays in the overflow.
class GithubPullScreen extends StatefulWidget {
  const GithubPullScreen({
    super.key,
    required this.owner,
    required this.repo,
    required this.number,
    this.seedTitle = '',
    this.api,
    this.initialTab = 0,
  });

  final String owner, repo;
  final int number;

  /// Known from the list row; shown until the detail loads.
  final String seedTitle;

  /// Test seam; defaults to [GithubApi.instance].
  final GithubApi? api;
  final int initialTab;

  @override
  State<GithubPullScreen> createState() => _GithubPullScreenState();
}

class _GithubPullScreenState extends State<GithubPullScreen>
    with SingleTickerProviderStateMixin {
  late final GhItemController _c = GhItemController(
    owner: widget.owner,
    repo: widget.repo,
    number: widget.number,
    isPr: true,
    api: widget.api,
  );
  late final TabController _tabs = TabController(
    length: 4,
    vsync: this,
    initialIndex: widget.initialTab,
  );

  @override
  void initState() {
    super.initState();
    _tabs.addListener(_onTab);
    _c.load();
    _c.ensureTab(widget.initialTab);
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTab);
    _tabs.dispose();
    _c.dispose();
    super.dispose();
  }

  void _onTab() {
    if (_tabs.indexIsChanging) return;
    _c.ensureTab(_tabs.index);
    setState(() {});
  }

  void _ask() {
    final d = _c.detail;
    askSparky(
      context,
      GhPrompts.pull(_c.fullName, widget.number, d?.title ?? widget.seedTitle),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        final d = _c.detail;
        return M3Page(
          title:
              '${GhDetailStrings.pullTitle} ${GithubStrings.issueNumber(widget.number)}',
          onRefresh: _c.load,
          actions: [
            IconButton(
              tooltip: GhDetailStrings.askSparky,
              onPressed: _ask,
              icon: const AppIcon(GhDetailIcons.ask, size: AppIconSize.lg),
            ),
            GhOverflowMenu(controller: _c),
          ],
          bottom: TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            dividerColor: Colors.transparent,
            tabs: [
              const Tab(text: GhDetailStrings.tabConversation),
              Tab(
                text: GhDetailStrings.tabCount(
                  GhDetailStrings.tabCommits,
                  d?.commits ?? 0,
                ),
              ),
              Tab(
                text: GhDetailStrings.tabCount(
                  GhDetailStrings.tabFiles,
                  d?.changedFiles ?? 0,
                ),
              ),
              const Tab(text: GhDetailStrings.tabChecks),
            ],
          ),
          slivers: [
            M3Body(
              children: [
                const SizedBox(height: AppSpacing.sm),
                GhDetailHeader(
                  repo: _c.fullName,
                  number: widget.number,
                  isPr: true,
                  seedTitle: widget.seedTitle,
                  detail: d,
                  onAsk: _ask,
                ),
                GhItemBanners(controller: _c),
                const SizedBox(height: AppSpacing.lg),
                ..._content(context),
              ],
            ),
          ],
        );
      },
    );
  }

  List<Widget> _content(BuildContext context) {
    final d = _c.detail;
    if (d == null) {
      if (_c.error != null && !_c.loading) {
        return [GhItemFailed(controller: _c)];
      }
      return const [GhSkeletonCells(count: 3)];
    }
    switch (_tabs.index) {
      case 1:
        return [
          _Loaded<List<GhPrCommit>>(
            state: _c.commits,
            onRetry: _c.loadCommits,
            builder: (v) => GhPrCommitsList(repo: _c.fullName, commits: v),
          ),
        ];
      case 2:
        return [
          _Loaded<(List<GhFile>, bool)>(
            state: _c.files,
            onRetry: _c.loadFiles,
            builder: (v) => v.$1.isEmpty
                ? const M3Empty(
                    icon: GhDetailIcons.commit,
                    title: GhDetailStrings.noFiles,
                  )
                : GhDiffView(
                    files: v.$1,
                    truncated: v.$2,
                    onAskFile: (f) => askSparky(
                      context,
                      GhPrompts.pullFile(
                        _c.fullName,
                        widget.number,
                        f.filename,
                      ),
                    ),
                  ),
          ),
        ];
      case 3:
        return [
          _Loaded<GhChecks>(
            state: _c.checks,
            onRetry: _c.loadChecks,
            builder: (v) => GhChecksView(
              checks: v,
              onReconnect: () => ghReconnect(context),
            ),
          ),
        ];
    }
    return [
      GhActionBar(controller: _c),
      const SizedBox(height: AppSpacing.lg),
      GhMetaCard(
        detail: d,
        onLabels: () => _gated('label', d.can.label, _labels),
        onAssignees: () => _gated('assign', d.can.assign, _assignees),
      ),
      const SizedBox(height: AppSpacing.lg),
      GhConversation(controller: _c),
    ];
  }

  void _labels() => showLabelsSheet(context, _c);
  void _assignees() => showAssigneesSheet(context, _c);

  void _gated(String key, bool ok, VoidCallback run) {
    final d = _c.detail!;
    ok
        ? run()
        : explainDisabled(
            context,
            d.can.why(key),
            reconnect: d.viewer.needsReconnect || !d.viewer.canWrite,
          );
  }
}

/// A tab's lazily loaded data: placeholders, the error with a retry (old
/// data stays when a refresh fails), or the content.
class _Loaded<T> extends StatelessWidget {
  const _Loaded({
    required this.state,
    required this.onRetry,
    required this.builder,
  });

  final Loadable<T> state;
  final VoidCallback onRetry;
  final Widget Function(T value) builder;

  @override
  Widget build(BuildContext context) {
    final v = state.data;
    if (v != null) return builder(v);
    if (state.failed) {
      final e = state.error!;
      final reconnect = ghNeedsReconnect(e);
      return M3Empty(
        icon: GhDetailIcons.warning,
        title: GhDetailStrings.loadFailed,
        hint: ghErrorText(e),
        action: FilledButton.tonal(
          onPressed: reconnect ? () => ghReconnect(context) : onRetry,
          child: Text(
            reconnect ? GhDetailStrings.reconnect : GhDetailStrings.retry,
          ),
        ),
      );
    }
    return const GhSkeletonCells(count: 4);
  }
}
