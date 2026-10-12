import 'package:flutter/material.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/m3_copy.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/m3_kit_extras.dart';
import '../../../data/kb_source.dart';
import '../../settings/widgets/settings_kit.dart';

String kindLabel(String type) => switch (type) {
  'github' => KnowledgeCopy.kindGithub,
  'stackoverflow' => KnowledgeCopy.kindStack,
  'reddit' => KnowledgeCopy.kindReddit,
  'hackernews' => KnowledgeCopy.kindHn,
  'note' => KnowledgeCopy.kindNote,
  'file' => KnowledgeCopy.kindFile,
  'doc' => KnowledgeCopy.kindDoc,
  _ => KnowledgeCopy.kindWeb,
};

/// One grouped row: kind icon, title, address, counts and a status chip.
class SourceTile extends StatelessWidget {
  const SourceTile({
    super.key,
    required this.source,
    required this.onRefresh,
    required this.onLongPress,
  });

  final KbSource source;
  final VoidCallback onRefresh;
  final VoidCallback onLongPress;

  /// Notes, files and docs have an internal id as address, not worth showing.
  bool get _hasInternalUri =>
      const {'note', 'file', 'doc'}.contains(source.type);

  String _status() {
    switch (source.status) {
      case 'running':
        final done = source.progressDone;
        final total = source.progressTotal;
        if (done == null) return KnowledgeCopy.running;
        return total == null
            ? '${KnowledgeCopy.running} $done'
            : '${KnowledgeCopy.running} $done/$total';
      case 'ready':
        return source.chunkCount == 0
            ? KnowledgeCopy.empty
            : KnowledgeCopy.ready;
      case 'failed':
        return KnowledgeCopy.failed;
      default:
        return KnowledgeCopy.queued;
    }
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
    return ListTile(
      onLongPress: onLongPress,
      leading: SettingsIconCircle(AppIcons.sourceKind(source.type)),
      title: Text(
        hasTitle ? source.title! : source.uri,
        maxLines: 1,
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
          Text(
            '${kindLabel(source.type)} · ${source.docCount} '
            '${KnowledgeCopy.docs} · ${source.chunkCount} '
            '${KnowledgeCopy.chunks}',
            style: muted,
          ),
          if (source.status == 'running') ...[
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: LinearProgressIndicator(
                minHeight: KnowledgeSizes.progressHeight,
                value:
                    source.progressTotal != null &&
                        source.progressTotal! > 0 &&
                        source.progressDone != null
                    ? source.progressDone! / source.progressTotal!
                    : null,
                color: p.accent,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ),
          ],
          if (failed && source.error != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                source.error!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: muted.copyWith(color: p.accent),
              ),
            ),
          if (canRefresh)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onRefresh,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(
                    0,
                    AppSizes.rowHeight - AppSpacing.xl,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  failed ? KnowledgeCopy.retry : KnowledgeCopy.refresh,
                ),
              ),
            ),
        ],
      ),
      trailing: M3Tag(_status(), accent: failed || source.isActive),
    );
  }
}
