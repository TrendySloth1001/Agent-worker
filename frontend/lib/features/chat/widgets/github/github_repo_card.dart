import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/widget_github.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../data/github_api.dart';
import '../open_url.dart';
import '../rich/rich_frame.dart';
import 'github_common.dart';

/// ```github-repo block (`owner/repo`): live repository overview.
class GithubRepoCard extends StatelessWidget {
  const GithubRepoCard({super.key, required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    final lines = ghLines(source);
    final ref = lines.isEmpty ? null : parseGhRef(lines.first.split(' ').first);
    if (ref == null) {
      return GhBadBlock(
        title: GithubStrings.repo,
        source: source,
        hint: GithubStrings.badSpec,
      );
    }
    return RichCard(
      title: GithubStrings.titled(GithubStrings.repo, ref.full.toUpperCase()),
      leading: const Octicon(GithubOcticons.repo),
      actions: [
        ghVisitAction(context, ref.url),
        RichAction.copy(text: ref.url),
      ],
      child: GhFuture<GhRepo>(
        skeletonRows: 4,
        load: () => GithubApi.instance.repo(ref.owner, ref.repo),
        builder: (context, r) => GhRepoBody(repo: r),
      ),
    );
  }
}

/// Repository details (also used by expanded search results).
class GhRepoBody extends StatelessWidget {
  const GhRepoBody({super.key, required this.repo, this.compact = false});

  final GhRepo repo;

  /// Search results: no header row (the result row already shows it).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final r = repo;
    final parts = r.fullName.split('/');
    return Padding(
      padding: EdgeInsets.all(compact ? 0 : GithubSizes.pad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!compact)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GhAvatar(r.avatar, size: GithubSizes.avatarLarge),
                const SizedBox(width: GithubSizes.pad),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '${parts.first}/',
                              style: TextStyle(color: p.textTertiary),
                            ),
                            TextSpan(text: parts.last),
                          ],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.title.copyWith(color: p.textPrimary),
                      ),
                      if (r.archived)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.xs),
                          child: Text(
                            GithubStrings.archived,
                            style: t.caption.copyWith(color: p.accent),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          if (r.description.isNotEmpty) ...[
            SizedBox(height: compact ? 0 : GithubSizes.rowGap),
            Text(
              r.description,
              maxLines: compact ? null : GithubSizes.descriptionLines * 2,
              overflow: compact ? null : TextOverflow.ellipsis,
              style: t.bodySmall,
            ),
          ],
          const SizedBox(height: GithubSizes.pad),
          Wrap(
            spacing: GithubSizes.pad,
            runSpacing: AppSpacing.xs,
            children: [
              GhStat(GithubOcticons.star, GithubStrings.countOf(r.stars)),
              GhStat(GithubOcticons.fork, GithubStrings.countOf(r.forks)),
              if (r.watchers != null)
                GhStat(GithubOcticons.eye, GithubStrings.countOf(r.watchers!)),
              GhStat(
                GithubOcticons.issueOpen,
                GithubStrings.countOf(r.openIssues),
              ),
              if (r.license != null) GhStat(GithubOcticons.law, r.license!),
              if (r.defaultBranch.isNotEmpty)
                GhStat(GithubOcticons.branch, r.defaultBranch),
              if (r.pushedAt != null)
                GhStat(GithubOcticons.commit, GithubStrings.ago(r.pushedAt)),
            ],
          ),
          if (r.languages.isNotEmpty) ...[
            const GhSection(GithubStrings.languages),
            _LanguageBar(languages: r.languages),
          ] else if (r.language != null) ...[
            const GhSection(GithubStrings.languages),
            Text(r.language!, style: t.label),
          ],
          if (r.topics.isNotEmpty) ...[
            const GhSection(GithubStrings.topics),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final topic in r.topics.take(GithubLimits.topics))
                  GhChip(topic),
              ],
            ),
          ],
          if (r.latestRelease != null) ...[
            const GhSection(GithubStrings.latestRelease),
            GhTap(
              onTap: () => openUrl(context, r.latestRelease!.url),
              child: Row(
                children: [
                  const Octicon(GithubOcticons.tag),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      r.latestRelease!.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.label,
                    ),
                  ),
                  Text(
                    GithubStrings.ago(r.latestRelease!.publishedAt),
                    style: t.caption,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Monochrome stacked bar (alpha steps) with a legend.
class _LanguageBar extends StatelessWidget {
  const _LanguageBar({required this.languages});

  final List<(String, double)> languages;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final langs = languages.take(GithubLimits.languages).toList();
    Color shade(int i) => p.textPrimary.withValues(
      alpha: GithubSizes.langAlphas[i % GithubSizes.langAlphas.length],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: SizedBox(
            height: GithubSizes.langBar,
            child: Row(
              children: [
                for (var i = 0; i < langs.length; i++) ...[
                  if (i > 0) const SizedBox(width: GithubSizes.langGap),
                  Expanded(
                    flex: (langs[i].$2 * 10).round().clamp(1, 1000),
                    child: ColoredBox(color: shade(i)),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: GithubSizes.pad,
          runSpacing: AppSpacing.xs,
          children: [
            for (var i = 0; i < langs.length; i++)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: GithubSizes.labelDot,
                    height: GithubSizes.labelDot,
                    decoration: BoxDecoration(
                      color: shade(i),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    langs[i].$1,
                    style: t.label.copyWith(color: p.textSecondary),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(GithubStrings.pct(langs[i].$2), style: t.caption),
                ],
              ),
          ],
        ),
      ],
    );
  }
}
