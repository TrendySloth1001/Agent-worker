import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/constants/app_icons.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/constants/apps.dart';
import '../../core/constants/widget_github.dart';
import '../../core/theme/app_palette.dart';
import '../../core/widgets/m3_kit_extras.dart';
import '../../data/github_api.dart';
import '../chat/widgets/github/github_common.dart';
import 'github_controller.dart';
import 'github_repo_screen.dart';
import 'widgets/gh_rows.dart';

enum _Scope { repos, code }

/// Search GitHub for repositories or code.
class GithubSearchScreen extends StatefulWidget {
  const GithubSearchScreen({super.key});

  @override
  State<GithubSearchScreen> createState() => _GithubSearchScreenState();
}

class _GithubSearchScreenState extends State<GithubSearchScreen> {
  _Scope _scope = _Scope.repos;
  String _q = '';
  Timer? _debounce;
  int _gen = 0;

  final _repos = Loadable<List<GhRepo>>();
  final _code = Loadable<List<GhCodeHit>>();

  @override
  void dispose() {
    _gen++;
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(AppDurations.searchDebounce, () {
      final q = text.trim();
      if (q == _q) return;
      _q = q;
      _run();
    });
  }

  Future<void> _run() async {
    final gen = ++_gen;
    final q = _q;
    final repos = _scope == _Scope.repos;
    if (q.isEmpty) {
      setState(() {
        _repos.data = null;
        _code.data = null;
        _repos.error = _code.error = null;
      });
      return;
    }
    final slot = repos ? _repos : _code;
    setState(() {
      slot.loading = true;
      slot.error = null;
      slot.data = null;
    });
    try {
      if (repos) {
        _repos.data = (await GithubApi.instance.searchRepos(q)).items;
      } else {
        _code.data = (await GithubApi.instance.searchCode(q)).items;
      }
    } catch (e) {
      if (gen == _gen) slot.error = e;
    }
    if (mounted && gen == _gen) setState(() => slot.loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final repos = _scope == _Scope.repos;
    final searched = _q.isNotEmpty;
    return M3Page(
      title: GithubHubStrings.searchTitle,
      slivers: [
        M3Body(
          children: [
            GhPillSearch(
              hint: GithubHubStrings.searchHint,
              autofocus: true,
              onChanged: _onChanged,
            ),
            const SizedBox(height: AppSpacing.md),
            SegmentedButton<_Scope>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: _Scope.repos,
                  label: Text(GithubHubStrings.searchRepos),
                ),
                ButtonSegment(
                  value: _Scope.code,
                  label: Text(GithubHubStrings.searchCode),
                ),
              ],
              selected: {_scope},
              onSelectionChanged: (s) {
                setState(() => _scope = s.first);
                if (searched) _run();
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            if (!searched)
              const M3Empty(
                icon: AppIcons.search,
                title: GithubHubStrings.searchStart,
                hint: GithubHubStrings.searchStartHint,
              )
            else if (repos)
              GhLoadableList<GhRepo>(
                state: _repos,
                onRetry: _run,
                cell: (c, r) => GhRepoTile(
                  repo: r,
                  onTap: () => Navigator.of(c).push(
                    MaterialPageRoute<void>(
                      builder: (_) => GithubRepoScreen(seed: r),
                    ),
                  ),
                ),
                emptyTitle: GithubHubStrings.searchNone,
                emptyHint: GithubHubStrings.noMatchesHint(_q),
                emptyIcon: AppIcons.search,
              )
            else
              GhLoadableList<GhCodeHit>(
                state: _code,
                onRetry: _run,
                cell: (c, hit) => _CodeTile(hit: hit, scheme: scheme),
                emptyTitle: GithubHubStrings.searchNone,
                emptyHint: GithubHubStrings.noMatchesHint(_q),
                emptyIcon: AppIcons.search,
              ),
          ],
        ),
      ],
    );
  }
}

class _CodeTile extends StatelessWidget {
  const _CodeTile({required this.hit, required this.scheme});

  final GhCodeHit hit;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return InkWell(
      onTap: () => ghVisit(context, hit.url),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Octicon(GithubOcticons.fileCode),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    hit.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              hit.repo,
              style: context.text.caption.copyWith(color: p.textSecondary),
            ),
            if (hit.fragments.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppRadius.sm * 2),
                ),
                child: Text(
                  hit.fragments.first.trim(),
                  maxLines: GithubSizes.fragmentLines,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.caption.copyWith(color: p.textPrimary),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
