import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_palette.dart';
import '../../../data/kb_source.dart';
import '../../../core/constants/app_icons.dart';
import '../../../core/widgets/icon_label.dart';

String kindLabel(String type) => switch (type) {
  'github' => AppStrings.kindGithub,
  'stackoverflow' => AppStrings.kindStack,
  'reddit' => AppStrings.kindReddit,
  'hackernews' => AppStrings.kindHn,
  'note' => AppStrings.kindNote,
  _ => AppStrings.kindWeb,
};

/// One flat row: kind and status on top, title, address, counts.
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

  String _status() {
    switch (source.status) {
      case 'running':
        final done = source.progressDone;
        final total = source.progressTotal;
        if (done == null) return AppStrings.running;
        return total == null
            ? '${AppStrings.running} $done'
            : '${AppStrings.running} $done/$total';
      case 'ready':
        return source.chunkCount == 0 ? AppStrings.empty : AppStrings.ready;
      case 'failed':
        return AppStrings.failed;
      default:
        return AppStrings.queued;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final failed = source.status == 'failed';
    final statusColor = failed || source.isActive ? p.accent : p.textSecondary;
    final canRefresh =
        source.type != 'note' && (source.status == 'ready' || failed);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: p.background,
          border: Border(bottom: BorderSide(color: p.border)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconLabel(
                  icon: AppIcons.sourceKind(source.type),
                  text: kindLabel(source.type),
                  style: t.caption,
                ),
                const Spacer(),
                Text(_status(), style: t.caption.copyWith(color: statusColor)),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              source.title?.isNotEmpty == true ? source.title! : source.uri,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.body,
            ),
            if (source.title?.isNotEmpty == true && source.type != 'note')
              Text(
                source.uri,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.caption,
              ),
            if (source.status == 'running') ...[
              const SizedBox(height: AppSpacing.sm),
              LinearProgressIndicator(
                minHeight: AppBorder.thick,
                value:
                    source.progressTotal != null &&
                        source.progressTotal! > 0 &&
                        source.progressDone != null
                    ? source.progressDone! / source.progressTotal!
                    : null,
                color: p.accent,
                backgroundColor: p.border,
              ),
            ],
            if (failed && source.error != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                source.error!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: t.caption.copyWith(color: p.accent),
              ),
            ],
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${source.docCount} ${AppStrings.documents} · '
                    '${source.chunkCount} ${AppStrings.chunksShort}',
                    style: t.caption,
                  ),
                ),
                if (canRefresh)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onRefresh,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.xs,
                      ),
                      child: Text(
                        failed ? AppStrings.retry : AppStrings.refresh,
                        style: t.caption.copyWith(color: p.textSecondary),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
