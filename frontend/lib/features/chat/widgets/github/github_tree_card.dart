import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/widget_github.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../data/github_api.dart';
import '../markdown/code_block.dart';
import '../rich/playful_common.dart';
import '../rich/rich_frame.dart';
import 'github_common.dart';

/// ```github-tree block (`owner/repo[@ref][:path]`): collapsible file tree;
/// tap a file to read it with syntax highlighting.
class GithubTreeCard extends StatelessWidget {
  const GithubTreeCard({super.key, required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    final lines = ghLines(source);
    final ref = lines.isEmpty ? null : parseGhRef(lines.first.split(' ').first);
    if (ref == null) {
      return GhBadBlock(
        title: GithubStrings.tree,
        source: source,
        hint: GithubStrings.badSpec,
      );
    }
    return _TreeBrowser(repo: ref);
  }
}

class _TreeBrowser extends StatefulWidget {
  const _TreeBrowser({required this.repo});

  final GhRef repo;

  @override
  State<_TreeBrowser> createState() => _TreeBrowserState();
}

class _TreeBrowserState extends State<_TreeBrowser> {
  GhEntry? _file;

  /// GitHub resolves HEAD to the default branch in web links.
  String get _branchOrHead => widget.repo.ref ?? 'HEAD';

  String get _webUrl {
    final r = widget.repo;
    final f = _file;
    if (f != null) return '${r.url}/blob/$_branchOrHead/${f.path}';
    return '${r.url}/tree/$_branchOrHead'
        '${r.path.isEmpty ? '' : '/${r.path}'}';
  }

  /// The ref to read; without one the default branch is looked up first.
  Future<String> _resolve() async {
    final r = widget.repo;
    return r.ref ??
        (await GithubApi.instance.repo(r.owner, r.repo)).defaultBranch;
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.repo;
    final detail = [
      r.full,
      if (r.ref != null) '@${r.ref}',
      if (r.path.isNotEmpty) ':${r.path}',
    ].join();
    final file = _file;
    return RichCard(
      title: GithubStrings.titled(GithubStrings.tree, detail.toUpperCase()),
      leading: Octicon(
        file == null ? GithubOcticons.dirOpen : GithubOcticons.fileCode,
      ),
      actions: [
        ghVisitAction(context, _webUrl),
        RichAction.copy(text: file?.path ?? _webUrl),
      ],
      child: GhFuture<String>(
        load: _resolve,
        builder: (context, branch) => file == null
            ? Padding(
                padding: const EdgeInsets.all(GithubSizes.pad),
                child: _DirListing(
                  repo: r,
                  branch: branch,
                  path: r.path,
                  depth: 0,
                  onFile: (e) => setState(() => _file = e),
                ),
              )
            : _FileView(
                repo: r,
                branch: branch,
                entry: file,
                onBack: () => setState(() => _file = null),
              ),
      ),
    );
  }
}

class _DirListing extends StatelessWidget {
  const _DirListing({
    required this.repo,
    required this.branch,
    required this.path,
    required this.depth,
    required this.onFile,
  });

  final GhRef repo;
  final String branch, path;
  final int depth;
  final ValueChanged<GhEntry> onFile;

  @override
  Widget build(BuildContext context) {
    return GhFuture<GhTree>(
      skeletonRows: depth == 0 ? 5 : 2,
      load: () =>
          GithubApi.instance.tree(repo.owner, repo.repo, branch, path: path),
      builder: (context, tree) => _Entries(
        tree: tree,
        depth: depth,
        repo: repo,
        branch: branch,
        onFile: onFile,
      ),
    );
  }
}

class _Entries extends StatefulWidget {
  const _Entries({
    required this.tree,
    required this.depth,
    required this.repo,
    required this.branch,
    required this.onFile,
  });

  final GhTree tree;
  final int depth;
  final GhRef repo;
  final String branch;
  final ValueChanged<GhEntry> onFile;

  @override
  State<_Entries> createState() => _EntriesState();
}

class _EntriesState extends State<_Entries> {
  final _open = <String>{};
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final entries = widget.tree.entries;
    if (entries.isEmpty) {
      return Text(GithubStrings.noResults, style: t.caption);
    }
    final cap = GithubLimits.initialVisible * 2;
    final shown = _all ? entries.length : entries.length.clamp(0, cap);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final e in entries.take(shown)) ...[
          GhTap(
            onTap: () {
              if (e.type == GhEntryType.dir) {
                setState(() {
                  if (!_open.remove(e.path)) _open.add(e.path);
                });
              } else if (e.type == GhEntryType.file ||
                  e.type == GhEntryType.symlink) {
                widget.onFile(e);
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                children: [
                  Octicon(
                    switch (e.type) {
                      GhEntryType.dir =>
                        _open.contains(e.path)
                            ? GithubOcticons.dirOpen
                            : GithubOcticons.dir,
                      GhEntryType.submodule => GithubOcticons.submodule,
                      GhEntryType.symlink => GithubOcticons.symlink,
                      GhEntryType.file => GithubOcticons.file,
                    },
                    color: e.type == GhEntryType.dir
                        ? p.textSecondary
                        : p.textTertiary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      e.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.code.copyWith(
                        color: e.type == GhEntryType.dir
                            ? p.textPrimary
                            : p.textSecondary,
                      ),
                    ),
                  ),
                  if (e.type == GhEntryType.file)
                    Text(GithubStrings.bytes(e.size), style: t.caption)
                  else if (e.type == GhEntryType.dir)
                    AppIcon(
                      _open.contains(e.path)
                          ? GithubIcons.collapse
                          : GithubIcons.expand,
                      size: AppIconSize.sm,
                      color: p.textTertiary,
                    ),
                ],
              ),
            ),
          ),
          if (e.type == GhEntryType.dir && _open.contains(e.path))
            Container(
              margin: const EdgeInsets.only(left: GithubSizes.octicon / 2),
              padding: const EdgeInsets.only(left: GithubSizes.treeIndent),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: p.border, width: AppBorder.thin),
                ),
              ),
              child: _DirListing(
                repo: widget.repo,
                branch: widget.branch,
                path: e.path,
                depth: widget.depth + 1,
                onFile: widget.onFile,
              ),
            ),
        ],
        if (entries.length > cap)
          GhTap(
            onTap: () => setState(() => _all = !_all),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Text(
                _all ? GithubStrings.showLess : GithubStrings.loadMore,
                style: t.caption.copyWith(color: p.textSecondary),
              ),
            ),
          ),
        if (widget.tree.truncated)
          Text(GithubStrings.treeTruncated, style: t.caption),
      ],
    );
  }
}

/// File contents with syntax colors, height capped (scrolls inside).
class _FileView extends StatelessWidget {
  const _FileView({
    required this.repo,
    required this.branch,
    required this.entry,
    required this.onBack,
  });

  final GhRef repo;
  final String branch;
  final GhEntry entry;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GhTap(
          onTap: onBack,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: GithubSizes.pad,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: p.border)),
            ),
            child: Row(
              children: [
                AppIcon(
                  GithubIcons.back,
                  size: AppIconSize.sm,
                  color: p.textSecondary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    entry.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.code.copyWith(color: p.textPrimary),
                  ),
                ),
                Text(GithubStrings.bytes(entry.size), style: t.caption),
              ],
            ),
          ),
        ),
        GhFuture<GhContent>(
          skeletonRows: 6,
          load: () => GithubApi.instance.contents(
            repo.owner,
            repo.repo,
            branch,
            entry.path,
          ),
          builder: (context, c) {
            if (c.binary || c.tooLarge) {
              return Padding(
                padding: const EdgeInsets.all(GithubSizes.pad),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        c.binary
                            ? GithubStrings.binaryFile
                            : GithubStrings.largeFile,
                        style: t.bodySmall,
                      ),
                    ),
                    PlayfulButton(
                      label: GithubStrings.visit,
                      icon: GithubIcons.visit,
                      onTap: () => ghVisit(context, c.url),
                    ),
                  ],
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: GithubSizes.pad),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: GithubSizes.codeMaxHeight,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CodeBlock(
                        code: c.text,
                        language: c.language.isEmpty ? null : c.language,
                        headerLabel: c.name.toUpperCase(),
                      ),
                      if (c.truncated)
                        Text(GithubStrings.fileTruncated, style: t.caption),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
