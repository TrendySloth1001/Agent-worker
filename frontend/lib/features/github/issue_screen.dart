import 'package:flutter/material.dart';

import '../../core/constants/app_sizes.dart';
import '../../core/constants/github_detail.dart';
import '../../core/constants/widget_github.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/m3_kit_extras.dart';
import '../../data/github_api.dart';
import 'gh_actions.dart';
import 'gh_item_controller.dart';
import 'widgets/gh_detail_header.dart';
import 'widgets/gh_item_view.dart';
import 'widgets/gh_rows.dart';
import 'widgets/gh_sheets.dart';

/// One issue, in-app: header with Ask Sparky, close (completed / not
/// planned) or reopen, labels, assignees and milestone, the conversation
/// and the comment box. Off actions explain why; "Open on GitHub" stays in
/// the overflow.
class GithubIssueScreen extends StatefulWidget {
  const GithubIssueScreen({
    super.key,
    required this.owner,
    required this.repo,
    required this.number,
    this.seedTitle = '',
    this.api,
  });

  final String owner, repo;
  final int number;
  final String seedTitle;

  /// Test seam; defaults to [GithubApi.instance].
  final GithubApi? api;

  @override
  State<GithubIssueScreen> createState() => _GithubIssueScreenState();
}

class _GithubIssueScreenState extends State<GithubIssueScreen> {
  late final GhItemController _c = GhItemController(
    owner: widget.owner,
    repo: widget.repo,
    number: widget.number,
    isPr: false,
    api: widget.api,
  );

  @override
  void initState() {
    super.initState();
    _c.load();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _ask() {
    final d = _c.detail;
    askSparky(
      context,
      GhPrompts.issue(_c.fullName, widget.number, d?.title ?? widget.seedTitle),
    );
  }

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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        final d = _c.detail;
        return M3Page(
          title:
              '${GhDetailStrings.issueTitle} ${GithubStrings.issueNumber(widget.number)}',
          onRefresh: _c.load,
          actions: [
            IconButton(
              tooltip: GhDetailStrings.askSparky,
              onPressed: _ask,
              icon: const AppIcon(GhDetailIcons.ask, size: AppIconSize.lg),
            ),
            GhOverflowMenu(controller: _c),
          ],
          slivers: [
            M3Body(
              children: [
                const SizedBox(height: AppSpacing.sm),
                GhDetailHeader(
                  repo: _c.fullName,
                  number: widget.number,
                  isPr: false,
                  seedTitle: widget.seedTitle,
                  detail: d,
                  onAsk: _ask,
                ),
                GhItemBanners(controller: _c),
                const SizedBox(height: AppSpacing.lg),
                if (d == null)
                  _c.error != null && !_c.loading
                      ? GhItemFailed(controller: _c)
                      : const GhSkeletonCells(count: 3)
                else ...[
                  GhActionBar(controller: _c),
                  const SizedBox(height: AppSpacing.lg),
                  GhMetaCard(
                    detail: d,
                    onLabels: () => _gated(
                      'label',
                      d.can.label,
                      () => showLabelsSheet(context, _c),
                    ),
                    onAssignees: () => _gated(
                      'assign',
                      d.can.assign,
                      () => showAssigneesSheet(context, _c),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  GhConversation(controller: _c),
                ],
              ],
            ),
          ],
        );
      },
    );
  }
}
