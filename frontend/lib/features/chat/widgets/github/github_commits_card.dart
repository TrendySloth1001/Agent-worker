import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/widget_github.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../data/github_api.dart';
import '../rich/playful_common.dart';
import '../rich/rich_frame.dart';
import 'github_common.dart';

/// ```github-commits block (`owner/repo[@branch][:path]`): commit timeline;
/// tap a commit to see its changed files and diffs.
class GithubCommitsCard extends StatelessWidget {
  const GithubCommitsCard({super.key, required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    final lines = ghLines(source);
    final ref = lines.isEmpty ? null : parseGhRef(lines.first.split(' ').first);
    if (ref == null) {
      return GhBadBlock(
        title: GithubStrings.commits,
        source: source,
        hint: GithubStrings.badSpec,
      );
    }
    final detail = [
      ref.full,
      if (ref.ref != null) '@${ref.ref}',
      if (ref.path.isNotEmpty) ':${ref.path}',
    ].join();
    final webUrl = ref.ref == null
        ? '${ref.url}/commits'
        : '${ref.url}/commits/${ref.ref}${ref.path.isEmpty ? '' : '/${ref.path}'}';
    return RichCard(
      title: GithubStrings.titled(GithubStrings.commits, detail.toUpperCase()),
      leading: const Octicon(GithubOcticons.commit),
      actions: [
        ghVisitAction(context, webUrl),
        RichAction.copy(text: webUrl),
      ],
      child: GhFuture<List<GhCommit>>(
        skeletonRows: 5,
        load: () => GithubApi.instance.commits(
          ref.owner,
          ref.repo,
          sha: ref.ref,
          path: ref.path.isEmpty ? null : ref.path,
        ),
        builder: (context, list) => GhCommitTimeline(repo: ref, commits: list),
      ),
    );
  }
}

/// Vertical rail of commits; each expands into its files (loaded lazily).
class GhCommitTimeline extends StatefulWidget {
  const GhCommitTimeline({
    super.key,
    required this.repo,
    required this.commits,
    this.padded = true,
  });

  final GhRef repo;
  final List<GhCommit> commits;

  /// False when the parent already pads (compare card).
  final bool padded;

  @override
  State<GhCommitTimeline> createState() => _GhCommitTimelineState();
}

class _GhCommitTimelineState extends State<GhCommitTimeline> {
  final _open = <int>{};
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final list = widget.commits;
    if (list.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(GithubSizes.pad),
        child: Text(GithubStrings.noResults, style: t.bodySmall),
      );
    }
    final shown = _all
        ? list.length
        : list.length.clamp(0, GithubLimits.initialVisible);
    return Padding(
      padding: EdgeInsets.all(widget.padded ? GithubSizes.pad : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < shown; i++)
            _CommitRow(
              repo: widget.repo,
              commit: list[i],
              first: i == 0,
              last: i == shown - 1,
              open: _open.contains(i),
              onTap: () => setState(() {
                if (!_open.remove(i)) _open.add(i);
              }),
            ),
          if (list.length > GithubLimits.initialVisible)
            GhTap(
              onTap: () => setState(() => _all = !_all),
              child: Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
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
        ],
      ),
    );
  }
}

class _CommitRow extends StatelessWidget {
  const _CommitRow({
    required this.repo,
    required this.commit,
    required this.first,
    required this.last,
    required this.open,
    required this.onTap,
  });

  final GhRef repo;
  final GhCommit commit;
  final bool first, last, open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final c = commit;
    const center = GithubSizes.avatar / 2;
    final dot = Container(
      width: GithubSizes.avatar,
      height: GithubSizes.avatar,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: p.codeBackground,
        border: Border.all(
          color: open ? p.accent : p.borderStrong,
          width: AppBorder.thick,
        ),
      ),
      child: GhAvatar(c.author?.avatar ?? '', size: GithubSizes.avatarSmall),
    );
    return Stack(
      children: [
        if (!(first && last && !open))
          Positioned(
            left: center - AppBorder.thin / 2,
            top: first ? center : 0,
            bottom: last && !open ? null : 0,
            height: last && !open ? center : null,
            child: Container(width: AppBorder.thin, color: p.borderStrong),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            dot,
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: GithubSizes.pad),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    GhTap(
                      onTap: onTap,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.message,
                            maxLines: open ? null : 2,
                            overflow: open ? null : TextOverflow.ellipsis,
                            style: t.bodySmall.copyWith(
                              color: p.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Row(
                            children: [
                              GhChip(c.shortSha),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  '${c.who} · ${GithubStrings.ago(c.date)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: t.caption,
                                ),
                              ),
                              if (c.additions != null && c.deletions != null)
                                GhDelta(add: c.additions!, del: c.deletions!),
                              const SizedBox(width: AppSpacing.xs),
                              AppIcon(
                                open
                                    ? GithubIcons.collapse
                                    : GithubIcons.expand,
                                size: AppIconSize.sm,
                                color: p.textTertiary,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    AnimatedSize(
                      duration: GithubDurations.expand,
                      alignment: Alignment.topCenter,
                      child: open
                          ? GhCommitDetail(repo: repo, sha: c.sha)
                          : const SizedBox(width: double.infinity),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Body of the commit and its changed files (loaded on demand); shared with
/// the git graph.
class GhCommitDetail extends StatelessWidget {
  const GhCommitDetail({super.key, required this.repo, required this.sha});

  final GhRef repo;
  final String sha;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    return GhFuture<GhCommit>(
      load: () => GithubApi.instance.commit(repo.owner, repo.repo, sha),
      builder: (context, c) {
        final body = c.body
            .split('\n')
            .skip(c.body.startsWith(c.message) ? 1 : 0)
            .join('\n')
            .trim();
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (body.isNotEmpty)
                Text(
                  body,
                  maxLines: GithubSizes.bodyLines,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodySmall,
                ),
              GhSection(
                '${GithubStrings.files} ${c.files.length}',
                trailing: GhDelta(add: c.additions ?? 0, del: c.deletions ?? 0),
              ),
              GhFilesList(
                files: c.files,
                truncated: c.filesTruncated,
                moreUrl: c.url,
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  PlayfulButton(
                    label: GithubStrings.visit,
                    icon: GithubIcons.visit,
                    onTap: () => ghVisit(context, c.url),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  PlayfulButton(
                    label: GithubStrings.copy,
                    icon: GithubIcons.copy,
                    onTap: () => ghCopy(context, c.sha),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
