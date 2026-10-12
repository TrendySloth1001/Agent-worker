import 'package:flutter/material.dart';

import '../../core/constants/app_sizes.dart';
import '../../core/constants/github_detail.dart';
import '../../core/constants/widget_github.dart';
import '../../core/haptics.dart';
import '../../core/theme/app_palette.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/m3_kit_extras.dart';
import '../../data/github_api.dart';
import '../chat/widgets/github/github_common.dart';
import 'gh_actions.dart';
import 'widgets/diff_view.dart';
import 'widgets/gh_rows.dart';

/// One commit, in-app: message, author, size and every changed file with
/// its diff. Ask Sparky about the commit or one file.
class GithubCommitScreen extends StatefulWidget {
  const GithubCommitScreen({
    super.key,
    required this.owner,
    required this.repo,
    required this.sha,
    this.seedMessage = '',
    this.api,
  });

  final String owner, repo, sha;
  final String seedMessage;

  /// Test seam; defaults to [GithubApi.instance].
  final GithubApi? api;

  @override
  State<GithubCommitScreen> createState() => _GithubCommitScreenState();
}

class _GithubCommitScreenState extends State<GithubCommitScreen> {
  GithubApi get _api => widget.api ?? GithubApi.instance;
  GhCommit? _commit;
  Object? _error;

  String get _full => '${widget.owner}/${widget.repo}';
  String get _short =>
      widget.sha.length > 7 ? widget.sha.substring(0, 7) : widget.sha;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final c = await _api.commit(widget.owner, widget.repo, widget.sha);
      if (mounted) setState(() => _commit = c);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _ask() => askSparky(
    context,
    GhPrompts.commit(_full, widget.sha, _commit?.message ?? widget.seedMessage),
  );

  @override
  Widget build(BuildContext context) {
    final c = _commit;
    return M3Page(
      title: '${GhDetailStrings.commitTitle} $_short',
      onRefresh: _load,
      actions: [
        IconButton(
          tooltip: GhDetailStrings.askSparky,
          onPressed: _ask,
          icon: const AppIcon(GhDetailIcons.ask, size: AppIconSize.lg),
        ),
        PopupMenuButton<int>(
          tooltip: GhDetailStrings.more,
          icon: const AppIcon(GhDetailIcons.more, size: AppIconSize.lg),
          onSelected: (v) {
            Haptics.tap();
            if (v == 0) ghCopy(context, widget.sha);
            if (v == 1) {
              ghVisit(
                context,
                c?.url.isNotEmpty == true
                    ? c!.url
                    : 'https://github.com/$_full/commit/${widget.sha}',
              );
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 0, child: Text(GithubStrings.copy)),
            PopupMenuItem(value: 1, child: Text(GhDetailStrings.openOnGithub)),
          ],
        ),
      ],
      slivers: [
        M3Body(
          children: [
            const SizedBox(height: AppSpacing.sm),
            _Header(
              repo: _full,
              shortSha: _short,
              message: c?.message ?? widget.seedMessage,
              commit: c,
              onAsk: _ask,
            ),
            const SizedBox(height: AppSpacing.lg),
            if (c != null)
              c.files.isEmpty
                  ? const M3Empty(
                      icon: GhDetailIcons.commit,
                      title: GhDetailStrings.noFiles,
                    )
                  : GhDiffView(
                      files: c.files,
                      truncated: c.filesTruncated,
                      onAskFile: (f) => askSparky(
                        context,
                        GhPrompts.commitFile(_full, widget.sha, f.filename),
                      ),
                    )
            else if (_error != null)
              M3Empty(
                icon: GhDetailIcons.warning,
                title: GhDetailStrings.loadFailed,
                hint: ghErrorText(_error!),
                action: FilledButton.tonal(
                  onPressed: ghNeedsReconnect(_error)
                      ? () => ghReconnect(context)
                      : _load,
                  child: Text(
                    ghNeedsReconnect(_error)
                        ? GhDetailStrings.reconnect
                        : GhDetailStrings.retry,
                  ),
                ),
              )
            else
              const GhSkeletonCells(count: 3),
          ],
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.repo,
    required this.shortSha,
    required this.message,
    required this.commit,
    required this.onAsk,
  });

  final String repo, shortSha, message;
  final GhCommit? commit;
  final VoidCallback onAsk;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final c = commit;
    final body = c == null
        ? ''
        : c.body
              .split('\n')
              .skip(c.body.startsWith(c.message) ? 1 : 0)
              .join('\n')
              .trim();
    return M3Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GhChip(shortSha, icon: GithubOcticons.commit),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  repo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.caption.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(message, style: tt.titleLarge),
          if (body.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              body,
              style: tt.bodyMedium!.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
          if (c != null) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                GhAvatar(
                  c.author?.avatar ?? '',
                  size: GhDetailSizes.avatarSmall,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    [
                      c.who,
                      if (c.date != null)
                        GhDetailStrings.ago(
                          GithubStrings.ago(c.date).toLowerCase(),
                        ),
                    ].join('  ·  '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodyMedium!.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                GhDelta(add: c.additions ?? 0, del: c.deletions ?? 0),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          FilledButton.icon(
            onPressed: onAsk,
            icon: const AppIcon(GhDetailIcons.ask, size: AppIconSize.md),
            label: const Text(GhDetailStrings.askSparky),
          ),
        ],
      ),
    );
  }
}
