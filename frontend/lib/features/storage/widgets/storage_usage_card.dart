import 'package:flutter/material.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/storage.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/dot_meter.dart';
import '../../../core/widgets/icon_label.dart';
import '../../../data/files_api.dart';
import '../../chat/widgets/attachment_views.dart';
import '../../settings/widgets/section_header.dart';

String kindLabel(FileKind? k) => switch (k) {
  null => StorageStrings.all,
  FileKind.image => StorageStrings.images,
  FileKind.video => StorageStrings.videos,
  FileKind.audio => StorageStrings.audio,
  FileKind.document => StorageStrings.documents,
};

/// Used bytes against the limit as a dot meter, plus counts per kind.
/// With [onOpen] it is the Settings entry (compact, tappable).
class StorageUsageCard extends StatelessWidget {
  const StorageUsageCard({
    super.key,
    required this.usage,
    this.onOpen,
    this.loading = false,
  });

  final StorageUsage? usage;
  final VoidCallback? onOpen;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final u = usage;
    final limit = u?.limitBytes;
    final full = u?.full ?? false;
    return FlatCard(
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: IconLabel(
                  icon: StorageIcons.section,
                  text: StorageStrings.title,
                  style: t.label,
                  iconSize: AppIconSize.sm,
                  expand: true,
                ),
              ),
              if (u != null && limit == null)
                const MetaChip(StorageStrings.unlimited, emphasis: true)
              else if (full)
                const MetaChip(StorageStrings.full, emphasis: true),
              if (onOpen != null) ...[
                const SizedBox(width: AppSpacing.sm),
                AppIcon(
                  AppIcons.chevronRight,
                  size: AppIconSize.xs,
                  color: p.textTertiary,
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    u == null ? AppStrings.dash : formatBytes(u.totalBytes),
                    style: t.metric.copyWith(
                      color: u == null ? p.textTertiary : null,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Text(
                  limit == null
                      ? StorageStrings.used
                      : '${StorageStrings.of} ${formatBytes(limit)}',
                  style: t.caption,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          DotMeter(
            fraction: u?.fraction ?? 0,
            litColor: full ? p.error : p.textPrimary,
          ),
          if (u != null) ...[
            const SizedBox(height: AppSpacing.sm),
            for (final k in FileKind.values)
              if (onOpen == null || (u.byKind[k]?.count ?? 0) > 0)
                InfoRow(
                  kindLabel(k),
                  _kindValue(u.byKind[k]),
                  icon: fileIcon(k),
                ),
            InfoRow(
              StorageStrings.uploadsToday,
              u.uploadsPerDay == null
                  ? '${u.uploadsToday}'
                  : '${u.uploadsToday} / ${u.uploadsPerDay}',
            ),
          ] else if (loading)
            const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }

  static String _kindValue(({int count, int bytes})? v) {
    final n = v?.count ?? 0;
    return '$n ${n == 1 ? StorageStrings.file : StorageStrings.files}'
        '${StorageStrings.separator}${formatBytes(v?.bytes ?? 0)}';
  }
}

/// Settings entry: loads usage on its own and opens the Storage screen.
class StorageEntryCard extends StatefulWidget {
  const StorageEntryCard({super.key, required this.onOpen});

  final VoidCallback onOpen;

  @override
  State<StorageEntryCard> createState() => _StorageEntryCardState();
}

class _StorageEntryCardState extends State<StorageEntryCard> {
  StorageUsage? _usage;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    FilesApi.instance.changes.addListener(_load);
  }

  @override
  void dispose() {
    FilesApi.instance.changes.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final u = await FilesApi.instance.usage();
      if (mounted) setState(() => _usage = u);
    } catch (_) {
      /* the card shows the last value */
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) =>
      StorageUsageCard(usage: _usage, loading: _loading, onOpen: widget.onOpen);
}
