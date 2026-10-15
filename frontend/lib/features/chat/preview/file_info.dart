import 'package:flutter/material.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/preview.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/m3_kit_extras.dart';
import '../../../data/files_api.dart';
import '../widgets/attachment_views.dart';
import 'preview_type.dart';

/// "2026-10-11 18:32" in local time.
String formatFileDate(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}

/// Label / value pairs describing [f], skipping what is unknown.
List<(String, String)> fileInfoRows(FileInfo f) => [
  (PreviewStrings.infoName, f.name),
  (PreviewStrings.infoType, f.mime.isEmpty ? typeLabelOf(f) : f.mime),
  if (f.size > 0) (PreviewStrings.infoSize, formatBytes(f.size)),
  if (f.pages != null) (PreviewStrings.infoPages, '${f.pages}'),
  if (f.durationS != null)
    (PreviewStrings.infoDuration, formatDuration(f.durationS!)),
  if (f.width != null && f.height != null)
    (PreviewStrings.infoDimensions, '${f.width} × ${f.height}'),
  if (f.createdAt != null)
    (PreviewStrings.infoDate, formatFileDate(f.createdAt!)),
  if (f.conversationTitle != null && f.conversationTitle!.isNotEmpty)
    (PreviewStrings.infoChat, f.conversationTitle!),
];

/// The label / value list.
class FileInfoRows extends StatelessWidget {
  const FileInfoRows({super.key, required this.file});

  final FileInfo file;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    final p = context.palette;
    return Column(
      children: [
        for (final (label, value) in fileInfoRows(file))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: PreviewSizes.infoLabelWidth,
                  child: Text(label, style: t.caption),
                ),
                Expanded(
                  child: SelectableText(
                    value,
                    style: t.body.copyWith(color: p.textPrimary),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Bottom sheet with a file's details.
Future<void> showFileInfoSheet(BuildContext context, FileInfo file) {
  return showM3Sheet<void>(
    context,
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenPadding,
          0,
          AppSpacing.screenPadding,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [FileInfoRows(file: file)],
        ),
      ),
    ),
  );
}

/// Centered card for a file that cannot be drawn: icon, name, details and a
/// hint. [children] (actions) go underneath.
class FileInfoCard extends StatelessWidget {
  const FileInfoCard({
    super.key,
    required this.file,
    required this.title,
    required this.hint,
    this.children = const [],
  });

  final FileInfo file;
  final String title;
  final String hint;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: PreviewSizes.infoCardMaxWidth,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: PreviewSizes.infoCardCircle,
                height: PreviewSizes.infoCardCircle,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.surfaceContainerHigh,
                ),
                alignment: Alignment.center,
                child: AppIcon(
                  AppIcons.fileKind(file.name),
                  size: PreviewSizes.infoCardIcon,
                  color: p.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                hint,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              FileInfoRows(file: file),
              for (final c in children) ...[
                const SizedBox(height: AppSpacing.lg),
                c,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
