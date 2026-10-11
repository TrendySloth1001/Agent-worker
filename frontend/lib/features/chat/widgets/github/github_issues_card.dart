import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/widget_github.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../data/github_api.dart';
import '../rich/playful_common.dart';
import '../rich/rich_frame.dart';
import 'github_common.dart';
import 'github_review_card.dart';

/// ```github-prs / ```github-issues block (`owner/repo [open|closed|all]`):
/// live list with state icons and labels; tap to read the body (and, for
/// pull requests, the changed files).
class GithubIssuesCard extends StatefulWidget {
  const GithubIssuesCard({super.key, required this.source, required this.prs});

  final String source;
  final bool prs;

  @override
  State<GithubIssuesCard> createState() => _GithubIssuesCardState();
}

class _GithubIssuesCardState extends State<GithubIssuesCard> {
  late GhRef? _ref = _parse();
  late String _state = ghState(widget.source);

  GhRef? _parse() {
    final lines = ghLines(widget.source);
    return lines.isEmpty ? null : parseGhRef(lines.first.split(' ').first);
  }

  @override
  void didUpdateWidget(GithubIssuesCard old) {
    super.didUpdateWidget(old);
    if (old.source != widget.source) {
      _ref = _parse();
      _state = ghState(widget.source);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.prs ? GithubStrings.prs : GithubStrings.issues;
    final ref = _ref;
    if (ref == null) {
      return GhBadBlock(
        title: title,
        source: widget.source,
        hint: GithubStrings.badSpec,
      );
    }
    final kind = widget.prs ? 'pulls' : 'issues';
    final webUrl =
        '${ref.url}/$kind?q=${Uri.encodeQueryComponent(_state == GithubStrings.stateAll ? '' : 'is:$_state')}';
    final api = GithubApi.instance;
    return RichCard(
      title: GithubStrings.titled(title, ref.full.toUpperCase()),
      leading: Octicon(
        widget.prs ? GithubOcticons.pr : GithubOcticons.issueOpen,
      ),
      actions: [
        ghVisitAction(context, webUrl),
        RichAction.copy(text: webUrl),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              GithubSizes.pad,
              GithubSizes.pad,
              GithubSizes.pad,
              0,
            ),
            child: Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final s in const [
                  GithubStrings.stateOpen,
                  GithubStrings.stateClosed,
                  GithubStrings.stateAll,
                ])
                  _StateChip(
                    label: s.toUpperCase(),
                    selected: s == _state,
                    onTap: () => setState(() => _state = s),
                  ),
              ],
            ),
          ),
          GhFuture<List<GhIssue>>(
            key: ValueKey(_state),
            skeletonRows: 5,
            load: () => widget.prs
                ? api.pulls(ref.owner, ref.repo, _state)
                : api.issues(ref.owner, ref.repo, _state),
            builder: (context, list) => _IssueList(repo: ref, items: list),
          ),
        ],
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GhTap(
      onTap: onTap,
      child: Container(
        height: GithubSizes.chipHeight,
        padding: const EdgeInsets.symmetric(horizontal: GithubSizes.chipPadH),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? p.textPrimary : null,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: selected ? p.textPrimary : p.border,
            width: AppBorder.thin,
          ),
        ),
        child: Text(
          label,
          style: context.text.caption.copyWith(
            color: selected ? p.textInverse : p.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _IssueList extends StatefulWidget {
  const _IssueList({required this.repo, required this.items});

  final GhRef repo;
  final List<GhIssue> items;

  @override
  State<_IssueList> createState() => _IssueListState();
}

class _IssueListState extends State<_IssueList> {
  final _open = <int>{};
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final items = widget.items;
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(GithubSizes.pad),
        child: Text(GithubStrings.noResults, style: t.bodySmall),
      );
    }
    final shown = _all
        ? items.length
        : items.length.clamp(0, GithubLimits.initialVisible);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: GithubSizes.pad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < shown; i++) ...[
            if (i > 0) const GhDivider(),
            _IssueRow(
              repo: widget.repo,
              issue: items[i],
              open: _open.contains(i),
              onTap: () => setState(() {
                if (!_open.remove(i)) _open.add(i);
              }),
            ),
          ],
          if (items.length > GithubLimits.initialVisible)
            GhTap(
              onTap: () => setState(() => _all = !_all),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Row(
                  children: [
                    AppIcon(
                      _all ? GithubIcons.collapse : GithubIcons.expand,
                      size: AppIconSize.sm,
                      color: p.textTertiary,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      _all ? GithubStrings.showLess : GithubStrings.loadMore,
                      style: t.caption.copyWith(color: p.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.xs),
        ],
      ),
    );
  }
}

class _IssueRow extends StatefulWidget {
  const _IssueRow({
    required this.repo,
    required this.issue,
    required this.open,
    required this.onTap,
  });

  final GhRef repo;
  final GhIssue issue;
  final bool open;
  final VoidCallback onTap;

  @override
  State<_IssueRow> createState() => _IssueRowState();
}

class _IssueRowState extends State<_IssueRow> {
  bool _files = false;
  bool _review = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final i = widget.issue;
    final open = widget.open;
    final (icon, color) = ghStateIcon(context, i);
    final sub = [
      GithubStrings.issueNumber(i.number),
      if (i.user != null) i.user!.login,
      GithubStrings.ago(i.updatedAt),
      if (i.isPr && i.head.isNotEmpty)
        '${i.head} ${GithubStrings.into} ${i.base}',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: GithubSizes.rowGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GhTap(
            onTap: widget.onTap,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xxs),
                  child: Octicon(icon, color: color),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        i.title,
                        maxLines: open ? null : 2,
                        overflow: open ? null : TextOverflow.ellipsis,
                        style: t.bodySmall.copyWith(
                          color: p.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.caption,
                      ),
                      if (i.labels.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Wrap(
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xs,
                          children: [
                            for (final l in i.labels)
                              GhChip(l.name, dot: ghLabelColor(l.color)),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (i.comments != null && i.comments! > 0) ...[
                  const SizedBox(width: AppSpacing.sm),
                  GhStat(
                    GithubOcticons.comment,
                    GithubStrings.commentsCount(i.comments!),
                  ),
                ],
                const SizedBox(width: AppSpacing.xs),
                AppIcon(
                  open ? GithubIcons.collapse : GithubIcons.expand,
                  size: AppIconSize.sm,
                  color: p.textTertiary,
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: GithubDurations.expand,
            alignment: Alignment.topCenter,
            child: !open
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(
                      top: AppSpacing.sm,
                      left: GithubSizes.octicon + AppSpacing.sm,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          i.body.isEmpty ? GithubStrings.emptyBody : i.body,
                          maxLines: GithubSizes.bodyLines,
                          overflow: TextOverflow.ellipsis,
                          style: t.bodySmall,
                        ),
                        if (_files)
                          GhFuture<List<GhFile>>(
                            load: () => GithubApi.instance.pullFiles(
                              widget.repo.owner,
                              widget.repo.repo,
                              i.number,
                            ),
                            builder: (context, files) => Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                GhSection(
                                  '${GithubStrings.files} ${files.length}',
                                ),
                                GhFilesList(
                                  files: files,
                                  moreUrl: '${i.url}/files',
                                ),
                              ],
                            ),
                          ),
                        if (_review)
                          GithubReviewInline(
                            owner: widget.repo.owner,
                            repo: widget.repo.repo,
                            number: i.number,
                          ),
                        const SizedBox(height: AppSpacing.sm),
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.xs,
                          children: [
                            if (i.isPr && !_review)
                              PlayfulButton(
                                label: GithubReviewStrings.review,
                                icon: GithubIcons.code,
                                primary: true,
                                onTap: () => setState(() => _review = true),
                              ),
                            PlayfulButton(
                              label: GithubStrings.visit,
                              icon: GithubIcons.visit,
                              onTap: () => ghVisit(context, i.url),
                            ),
                            if (i.isPr && !_files)
                              PlayfulButton(
                                label: GithubStrings.files,
                                icon: GithubIcons.compare,
                                onTap: () => setState(() => _files = true),
                              ),
                            PlayfulButton(
                              label: GithubStrings.copy,
                              icon: GithubIcons.copy,
                              onTap: () => ghCopy(context, i.url),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
