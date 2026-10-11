import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/widget_github.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../data/github_api.dart';
import '../open_url.dart';
import '../rich/playful_common.dart';
import '../rich/rich_frame.dart';
import 'github_common.dart';
import 'github_repo_card.dart';

enum _Kind { repos, code, issues, commits }

class _Query {
  const _Query(this.kind, this.q, this.sort);
  final _Kind kind;
  final String q;
  final String? sort;

  String get webUrl {
    final type = switch (kind) {
      _Kind.repos => 'repositories',
      _Kind.code => 'code',
      _Kind.issues => 'issues',
      _Kind.commits => 'commits',
    };
    return Uri.https('github.com', '/search', {
      'q': q,
      'type': type,
    }).toString();
  }
}

_Query? _parse(String source) {
  var kind = _Kind.repos;
  var q = '';
  String? sort;
  for (final line in ghLines(source)) {
    final kv = playfulKeyValue(line);
    switch (kv?.$1) {
      case GithubStrings.keyType:
        final v = kv!.$2.toLowerCase();
        // Pull requests are searched as issues (`is:pr`).
        kind = v.startsWith('pr') || v.startsWith('pull')
            ? _Kind.issues
            : _Kind.values.firstWhere(
                (k) => v.startsWith(k.name.substring(0, 4)),
                orElse: () => _Kind.repos,
              );
      case GithubStrings.keyQuery || GithubStrings.keyQueryLong:
        q = kv!.$2;
      case GithubStrings.keySort:
        sort = kv!.$2.toLowerCase();
      default:
        if (q.isEmpty) q = line;
    }
  }
  if (q.trim().isEmpty) return null;
  return _Query(kind, q.trim(), sort);
}

/// ```github-search block (`type:` + `q:`): live GitHub search results.
class GithubSearchCard extends StatelessWidget {
  const GithubSearchCard({super.key, required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    final query = _parse(source);
    if (query == null) {
      return GhBadBlock(
        title: GithubStrings.search,
        source: source,
        hint: GithubStrings.badSearch,
      );
    }
    final api = GithubApi.instance;
    return RichCard(
      title: GithubStrings.titled(
        GithubStrings.search,
        query.kind.name.toUpperCase(),
      ),
      leading: const Octicon(GithubOcticons.search),
      actions: [
        ghVisitAction(context, query.webUrl),
        RichAction.copy(text: query.q),
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
            child: Text(
              query.q,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.text.code.copyWith(
                color: context.palette.textPrimary,
              ),
            ),
          ),
          switch (query.kind) {
            _Kind.repos => GhFuture<GhSearch<GhRepo>>(
              load: () => api.searchRepos(query.q, sort: query.sort),
              builder: (context, s) => _Results(
                total: s.total,
                count: s.items.length,
                row: (i, open) => _RepoRow(repo: s.items[i], open: open),
              ),
            ),
            _Kind.code => GhFuture<GhSearch<GhCodeHit>>(
              load: () => api.searchCode(query.q),
              builder: (context, s) => _Results(
                total: s.total,
                count: s.items.length,
                row: (i, open) => _CodeRow(hit: s.items[i], open: open),
              ),
            ),
            _Kind.issues => GhFuture<GhSearch<GhIssue>>(
              load: () => api.searchIssues(query.q),
              builder: (context, s) => _Results(
                total: s.total,
                count: s.items.length,
                row: (i, open) => _IssueRow(issue: s.items[i], open: open),
              ),
            ),
            _Kind.commits => GhFuture<GhSearch<GhCommit>>(
              load: () => api.searchCommits(query.q),
              builder: (context, s) => _Results(
                total: s.total,
                count: s.items.length,
                row: (i, open) => _CommitRow(commit: s.items[i], open: open),
              ),
            ),
          },
        ],
      ),
    );
  }
}

/// Result list: tap a row to expand it; SHOW MORE past the first few.
class _Results extends StatefulWidget {
  const _Results({required this.total, required this.count, required this.row});

  final int total, count;
  final Widget Function(int index, bool open) row;

  @override
  State<_Results> createState() => _ResultsState();
}

class _ResultsState extends State<_Results> {
  final _open = <int>{};
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    final p = context.palette;
    if (widget.count == 0) {
      return Padding(
        padding: const EdgeInsets.all(GithubSizes.pad),
        child: Text(GithubStrings.noResults, style: t.bodySmall),
      );
    }
    final shown = _all
        ? widget.count
        : widget.count.clamp(0, GithubLimits.initialVisible);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: GithubSizes.pad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Text(
              '${GithubStrings.countOf(widget.total)} ${GithubStrings.total}',
              style: t.caption,
            ),
          ),
          for (var i = 0; i < shown; i++) ...[
            if (i > 0) const GhDivider(),
            GhTap(
              onTap: () => setState(() {
                if (!_open.remove(i)) _open.add(i);
              }),
              child: AnimatedSize(
                duration: GithubDurations.expand,
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: GithubSizes.rowGap,
                  ),
                  child: widget.row(i, _open.contains(i)),
                ),
              ),
            ),
          ],
          if (widget.count > GithubLimits.initialVisible)
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

/// Row header shared by the result kinds.
class _Head extends StatelessWidget {
  const _Head({
    required this.lead,
    required this.title,
    required this.sub,
    this.trailing,
    required this.open,
  });

  final Widget lead;
  final String title, sub;
  final Widget? trailing;
  final bool open;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xxs),
          child: lead,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: open ? null : 2,
                overflow: open ? null : TextOverflow.ellipsis,
                style: t.bodySmall.copyWith(
                  color: p.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (sub.isNotEmpty)
                Text(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.caption,
                ),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: AppSpacing.sm),
          trailing!,
        ],
        AppIcon(
          open ? GithubIcons.collapse : GithubIcons.expand,
          size: AppIconSize.sm,
          color: p.textTertiary,
        ),
      ],
    );
  }
}

/// Expanded body: text plus OPEN / VISIT.
class _Body extends StatelessWidget {
  const _Body({required this.url, this.text = '', this.child});

  final String url, text;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ?child,
          if (text.isNotEmpty)
            Text(
              text,
              maxLines: GithubSizes.bodyLines,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodySmall,
            ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              PlayfulButton(
                label: GithubStrings.visit,
                icon: GithubIcons.visit,
                onTap: () => visitUrl(context, url),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RepoRow extends StatelessWidget {
  const _RepoRow({required this.repo, required this.open});

  final GhRepo repo;
  final bool open;

  @override
  Widget build(BuildContext context) {
    final r = repo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Head(
          lead: GhAvatar(r.avatar, size: GithubSizes.avatarSmall),
          title: r.fullName,
          sub: open ? '' : r.description,
          trailing: GhStat(GithubOcticons.star, GithubStrings.countOf(r.stars)),
          open: open,
        ),
        if (open)
          _Body(
            url: r.url,
            child: GhRepoBody(repo: r, compact: true),
          ),
      ],
    );
  }
}

class _CodeRow extends StatelessWidget {
  const _CodeRow({required this.hit, required this.open});

  final GhCodeHit hit;
  final bool open;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Head(
          lead: const Octicon(GithubOcticons.fileCode),
          title: hit.path,
          sub: hit.repo,
          open: open,
        ),
        if (open)
          _Body(
            url: hit.url,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final f in hit.fragments)
                  Container(
                    margin: const EdgeInsets.only(bottom: AppSpacing.xs),
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: p.background,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(color: p.border),
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Text(
                        f,
                        maxLines: GithubSizes.fragmentLines,
                        style: context.text.code,
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _IssueRow extends StatelessWidget {
  const _IssueRow({required this.issue, required this.open});

  final GhIssue issue;
  final bool open;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = ghStateIcon(context, issue);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Head(
          lead: Octicon(icon, color: color),
          title: issue.title,
          sub:
              '${issue.repo} ${GithubStrings.issueNumber(issue.number)} · '
              '${GithubStrings.ago(issue.updatedAt)}',
          open: open,
        ),
        if (open)
          _Body(
            url: issue.url,
            text: issue.body.isEmpty ? GithubStrings.emptyBody : issue.body,
          ),
      ],
    );
  }
}

class _CommitRow extends StatelessWidget {
  const _CommitRow({required this.commit, required this.open});

  final GhCommit commit;
  final bool open;

  @override
  Widget build(BuildContext context) {
    final c = commit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Head(
          lead: const Octicon(GithubOcticons.commit),
          title: c.message,
          sub: '${c.repo} · ${c.shortSha} · ${GithubStrings.ago(c.date)}',
          open: open,
        ),
        if (open) _Body(url: c.url, text: c.body),
      ],
    );
  }
}
