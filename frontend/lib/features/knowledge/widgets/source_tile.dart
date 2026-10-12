import 'package:flutter/material.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/m3_copy.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/time_ago.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../data/kb_source.dart';
import 'source_icon.dart';

String kindLabel(String type) => switch (type) {
  'github' => KnowledgeCopy.kindGithub,
  'stackoverflow' => KnowledgeCopy.kindStack,
  'reddit' => KnowledgeCopy.kindReddit,
  'hackernews' => KnowledgeCopy.kindHn,
  'note' => KnowledgeCopy.kindNote,
  'file' => KnowledgeCopy.kindFile,
  'doc' => KnowledgeCopy.kindDocument,
  'google_drive' => KnowledgeCopy.kindDrive,
  'notion' => KnowledgeCopy.kindNotion,
  _ => KnowledgeCopy.kindWeb,
};

/// Which group of the list a source type belongs to.
enum SourceGroup {
  documents(KnowledgeCopy.groupDocuments),
  web(KnowledgeCopy.groupWeb),
  github(KnowledgeCopy.groupGithub),
  notes(KnowledgeCopy.groupNotes);

  const SourceGroup(this.title);

  final String title;

  static SourceGroup of(String type) => switch (type) {
    'doc' || 'file' || 'google_drive' || 'notion' => documents,
    'github' => github,
    'note' => notes,
    _ => web,
  };
}

enum SourceAction { refresh, delete }

/// One grouped row: kind icon, title, human counts and a small status line
/// (dot + word, a thin progress line while indexing). Refresh and delete live
/// in the overflow menu.
class SourceTile extends StatelessWidget {
  const SourceTile({
    super.key,
    required this.source,
    required this.onRefresh,
    required this.onDelete,
    this.now,
    this.imageFor,
  });

  final KbSource source;
  final VoidCallback onRefresh;
  final VoidCallback onDelete;

  /// Test seam for the icon image source.
  final ImageProvider Function(String url)? imageFor;

  /// Test seam for the relative time.
  final DateTime? now;

  /// Notes, files and docs have an internal id as address, not worth showing.
  bool get _hasInternalUri =>
      const {'note', 'file', 'doc'}.contains(source.type);

  double? get _fraction =>
      source.progressTotal != null &&
          source.progressTotal! > 0 &&
          source.progressDone != null
      ? (source.progressDone! / source.progressTotal!).clamp(0.0, 1.0)
      : null;

  String _status() {
    switch (source.status) {
      case 'running':
        final f = _fraction;
        return f == null
            ? KnowledgeCopy.indexing
            : '${KnowledgeCopy.indexing} ${(f * 100).round()}%';
      case 'ready':
        return source.chunkCount == 0
            ? KnowledgeCopy.nothingIndexed
            : KnowledgeCopy.ready;
      case 'failed':
        return KnowledgeCopy.failed;
      default:
        return KnowledgeCopy.queued;
    }
  }

  String _summary() {
    final parts = <String>[
      kindLabel(source.type),
      if (source.chunkCount > 0) KnowledgeCopy.passages(source.chunkCount),
    ];
    final at = source.lastIngestedAt;
    if (at != null && source.status == 'ready') {
      parts.add(
        KnowledgeCopy.updated(timeAgo(at.toLocal(), now ?? DateTime.now())),
      );
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final scheme = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final muted = tt.bodySmall!.copyWith(color: scheme.onSurfaceVariant);
    final failed = source.status == 'failed';
    final canRefresh =
        source.type != 'note' && (source.status == 'ready' || failed);
    final hasTitle = source.title?.isNotEmpty == true;
    final statusColor = failed
        ? p.error
        : source.isActive
        ? p.accent
        : scheme.onSurfaceVariant;
    return ListTile(
      onLongPress: onDelete,
      leading: SourceIcon(source: source, imageFor: imageFor),
      title: Text(
        hasTitle ? source.title! : source.uri,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasTitle && !_hasInternalUri)
            Text(
              source.uri,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: muted,
            ),
          Text(_summary(), style: muted, maxLines: 1),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Container(
                width: KnowledgeSizes.statusDot,
                height: KnowledgeSizes.statusDot,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: statusColor,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  _status(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: muted.copyWith(color: statusColor),
                ),
              ),
            ],
          ),
          if (source.status == 'running') ...[
            const SizedBox(height: AppSpacing.sm),
            LinearProgressIndicator(
              minHeight: KnowledgeSizes.progressHeight,
              value: _fraction,
              stopIndicatorColor: Colors.transparent,
              color: p.accent,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ],
          if (failed && source.error != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                source.error!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: muted.copyWith(color: p.error),
              ),
            ),
        ],
      ),
      trailing: PopupMenuButton<SourceAction>(
        tooltip: KnowledgeCopy.moreActions,
        icon: AppIcon(
          AppIcons.more,
          size: AppIconSize.md,
          color: scheme.onSurfaceVariant,
        ),
        onOpened: Haptics.tap,
        onSelected: (a) => switch (a) {
          SourceAction.refresh => onRefresh(),
          SourceAction.delete => onDelete(),
        },
        itemBuilder: (context) => [
          if (canRefresh)
            PopupMenuItem(
              value: SourceAction.refresh,
              child: Text(failed ? KnowledgeCopy.retry : KnowledgeCopy.refresh),
            ),
          PopupMenuItem(
            value: SourceAction.delete,
            child: Text(
              KnowledgeCopy.deleteSource,
              style: TextStyle(color: p.error),
            ),
          ),
        ],
      ),
    );
  }
}
