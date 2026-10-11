import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/widget_github.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../data/github_api.dart';
import '../rich/rich_frame.dart';
import 'github_commits_card.dart';
import 'github_common.dart';

final _spec = RegExp(r'^(\S+)\s+(\S+?)\.{2,3}(\S+)$');
final _urlSpec = RegExp(
  r'github\.com/([\w-]+)/([\w.-]+)/compare/(\S+?)\.{2,3}(\S+)$',
);

/// ```github-compare block (`owner/repo base...head`): ahead/behind, commits
/// and file diffs between two refs.
class GithubCompareCard extends StatelessWidget {
  const GithubCompareCard({super.key, required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    final lines = ghLines(source);
    final line = lines.isEmpty ? '' : lines.first;
    GhRef? repo;
    String base = '', head = '';
    final u = _urlSpec.firstMatch(line);
    final m = _spec.firstMatch(line);
    if (u != null) {
      repo = GhRef(u[1]!, u[2]!);
      base = u[3]!;
      head = u[4]!;
    } else if (m != null) {
      repo = parseGhRef(m[1]!);
      base = m[2]!;
      head = m[3]!;
    }
    if (repo == null) {
      return GhBadBlock(
        title: GithubStrings.compare,
        source: source,
        hint: GithubStrings.badCompare,
      );
    }
    final r = repo;
    final webUrl = '${r.url}/compare/$base...$head';
    return RichCard(
      title: GithubStrings.titled(GithubStrings.compare, r.full.toUpperCase()),
      leading: const Octicon(GithubOcticons.compare),
      actions: [
        ghVisitAction(context, webUrl),
        RichAction.copy(text: webUrl),
      ],
      child: GhFuture<GhCompare>(
        skeletonRows: 5,
        load: () => GithubApi.instance.compare(r.owner, r.repo, base, head),
        builder: (context, c) =>
            _CompareBody(repo: r, base: base, head: head, data: c),
      ),
    );
  }
}

class _CompareBody extends StatelessWidget {
  const _CompareBody({
    required this.repo,
    required this.base,
    required this.head,
    required this.data,
  });

  final GhRef repo;
  final String base, head;
  final GhCompare data;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final c = data;
    return Padding(
      padding: const EdgeInsets.all(GithubSizes.pad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              GhChip(base, icon: GithubOcticons.branch),
              Text(
                GithubStrings.into,
                style: t.caption.copyWith(color: p.textSecondary),
              ),
              GhChip(head, icon: GithubOcticons.branch),
            ],
          ),
          const SizedBox(height: GithubSizes.pad),
          Wrap(
            spacing: GithubSizes.pad,
            runSpacing: AppSpacing.xs,
            children: [
              GhStat(
                GithubOcticons.commit,
                '${c.totalCommits} ${GithubStrings.commitsShort}',
              ),
              GhStat(
                GithubOcticons.fileCode,
                '${c.changedFiles} ${GithubStrings.changed}',
              ),
              if (c.aheadBy > 0)
                GhStat(
                  GithubOcticons.added,
                  '${c.aheadBy} ${GithubStrings.ahead}',
                ),
              if (c.behindBy > 0)
                GhStat(
                  GithubOcticons.removed,
                  '${c.behindBy} ${GithubStrings.behind}',
                  accent: true,
                ),
              GhDelta(add: c.additions, del: c.deletions),
            ],
          ),
          if (c.commits.isNotEmpty) ...[
            const GhSection(GithubStrings.commits),
            GhCommitTimeline(repo: repo, commits: c.commits, padded: false),
          ],
          if (c.files.isNotEmpty) ...[
            const GhSection(GithubStrings.files),
            GhFilesList(
              files: c.files,
              truncated: c.filesTruncated,
              moreUrl: c.url,
            ),
          ],
        ],
      ),
    );
  }
}
