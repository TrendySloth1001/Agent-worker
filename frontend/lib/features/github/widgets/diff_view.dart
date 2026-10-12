import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/github_detail.dart';
import '../../../core/constants/widget_github.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/m3_kit_extras.dart';
import '../../../data/github_api.dart';
import '../../chat/widgets/github/github_common.dart';
import '../../chat/widgets/rich/diff_block.dart';
import '../gh_actions.dart';

String _statusIcon(String status) => switch (status) {
  'added' => GithubOcticons.added,
  'removed' => GithubOcticons.removed,
  'renamed' => GithubOcticons.renamed,
  _ => GithubOcticons.modified,
};

/// Changed files of a pull request or commit: a summary line, then one
/// collapsible cell per file with its unified diff (colored lines, line
/// numbers, sideways scroll for long lines). Each file can be sent to
/// Sparky.
class GhDiffView extends StatefulWidget {
  const GhDiffView({
    super.key,
    required this.files,
    this.truncated = false,
    required this.onAskFile,
  });

  final List<GhFile> files;
  final bool truncated;
  final void Function(GhFile file) onAskFile;

  @override
  State<GhDiffView> createState() => _GhDiffViewState();
}

class _GhDiffViewState extends State<GhDiffView> {
  late final Set<String> _open = _initial();

  /// Small changes open expanded; big ones start collapsed.
  Set<String> _initial() {
    final f = widget.files;
    final lines = f.fold<int>(
      0,
      (n, x) => n + ('\n'.allMatches(x.patch ?? '').length),
    );
    if (f.length <= GhDetailSizes.autoExpandFiles &&
        lines <= GhDetailSizes.autoExpandLines) {
      return {for (final x in f) x.filename};
    }
    return {};
  }

  void _toggle(String name) {
    Haptics.tap();
    setState(() => _open.contains(name) ? _open.remove(name) : _open.add(name));
  }

  @override
  Widget build(BuildContext context) {
    final files = widget.files;
    final scheme = Theme.of(context).colorScheme;
    final add = files.fold<int>(0, (n, f) => n + f.additions);
    final del = files.fold<int>(0, (n, f) => n + f.deletions);
    final allOpen = _open.length == files.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.xs,
            bottom: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Text(
                GhDetailStrings.files(files.length),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(width: AppSpacing.md),
              GhDelta(add: add, del: del),
              const Spacer(),
              TextButton(
                onPressed: () {
                  Haptics.tap();
                  setState(() {
                    if (allOpen) {
                      _open.clear();
                    } else {
                      _open.addAll(files.map((f) => f.filename));
                    }
                  });
                },
                child: Text(
                  allOpen
                      ? GhDetailStrings.collapseAll
                      : GhDetailStrings.expandAll,
                ),
              ),
            ],
          ),
        ),
        for (var i = 0; i < files.length; i++)
          M3Cell(
            index: i,
            count: files.length,
            child: _FileCell(
              file: files[i],
              open: _open.contains(files[i].filename),
              onToggle: () => _toggle(files[i].filename),
              onAsk: () => widget.onAskFile(files[i]),
            ),
          ),
        if (widget.truncated)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Text(
              GhDetailStrings.filesTruncated,
              style: context.text.caption.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _FileCell extends StatelessWidget {
  const _FileCell({
    required this.file,
    required this.open,
    required this.onToggle,
    required this.onAsk,
  });

  final GhFile file;
  final bool open;
  final VoidCallback onToggle, onAsk;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final scheme = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final f = file;
    final slash = f.filename.lastIndexOf('/');
    final dir = slash < 0 ? '' : f.filename.substring(0, slash + 1);
    final base = f.filename.substring(slash + 1);
    final statusColor = switch (f.status) {
      'added' => ghStateColor(context, 'open'),
      'removed' => p.accent,
      _ => scheme.onSurfaceVariant,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.xs,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                Octicon(
                  _statusIcon(f.status),
                  size: GithubSizes.octicon,
                  color: statusColor,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        base,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.titleSmall,
                      ),
                      if (dir.isNotEmpty)
                        Text(
                          dir,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.caption.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      if (f.previousFilename != null)
                        Text(
                          GhDetailStrings.renamedFrom(f.previousFilename!),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.caption.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      const SizedBox(height: AppSpacing.xxs),
                      GhDelta(add: f.additions, del: f.deletions),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: GhDetailStrings.askFile,
                  onPressed: onAsk,
                  icon: AppIcon(
                    GhDetailIcons.ask,
                    size: AppIconSize.md,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                PopupMenuButton<int>(
                  tooltip: GhDetailStrings.more,
                  icon: AppIcon(
                    GhDetailIcons.more,
                    size: AppIconSize.md,
                    color: scheme.onSurfaceVariant,
                  ),
                  onSelected: (v) async {
                    if (v == 0) {
                      onAsk();
                      return;
                    }
                    await Clipboard.setData(ClipboardData(text: f.filename));
                    if (context.mounted) {
                      ghToast(context, GhDetailStrings.pathCopied);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 0,
                      child: Text(GhDetailStrings.askFile),
                    ),
                    PopupMenuItem(
                      value: 1,
                      child: Text(GhDetailStrings.copyPath),
                    ),
                  ],
                ),
                AppIcon(
                  open ? GhDetailIcons.collapse : GhDetailIcons.expand,
                  size: AppIconSize.sm,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
            ),
          ),
        ),
        if (open) _Patch(file: f),
      ],
    );
  }
}

class _Patch extends StatelessWidget {
  const _Patch({required this.file});

  final GhFile file;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final patch = file.patch;
    if (patch == null || patch.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        child: Text(
          file.additions + file.deletions == 0
              ? GhDetailStrings.binary
              : GhDetailStrings.noPatch,
          style: context.text.caption,
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: p.codeBackground,
        border: Border(
          top: BorderSide(color: p.border, width: AppBorder.thin),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DiffLines(code: patch, wrap: false),
          if (file.patchTruncated)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Text(
                GhDetailStrings.patchTruncated,
                style: context.text.caption,
              ),
            ),
        ],
      ),
    );
  }
}
