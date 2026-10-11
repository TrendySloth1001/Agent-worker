import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants/app_icons.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/constants/app_strings.dart';
import '../../core/constants/storage.dart';
import '../../core/haptics.dart';
import '../../core/notifications.dart';
import '../../core/theme/app_palette.dart';
import '../../core/widgets/app_icon.dart';
import '../../data/files_api.dart';
import '../chat/preview/file_preview.dart';
import '../chat/widgets/attachment_views.dart';
import 'storage_controller.dart';

enum StorageAction { open, share, download, openChat, select, rename, delete }

void storageNotice(BuildContext context, String text, {bool error = false}) {
  error ? Haptics.error() : Haptics.received();
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text, style: context.text.label)));
}

/// Long-press sheet of a file: OPEN, SHARE, DOWNLOAD, OPEN CHAT, SELECT,
/// RENAME, DELETE.
Future<void> showStorageActions(
  BuildContext context,
  StorageController controller,
  FileInfo file,
) async {
  Haptics.tap();
  final p = context.palette;
  final action = await showModalBottomSheet<StorageAction>(
    context: context,
    backgroundColor: p.surface,
    shape: RoundedRectangleBorder(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppRadius.lg),
      ),
      side: BorderSide(color: p.border),
    ),
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenPadding,
              AppSpacing.lg,
              AppSpacing.screenPadding,
              AppSpacing.sm,
            ),
            child: Text(
              file.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sheet.text.label,
            ),
          ),
          Divider(color: p.border),
          for (final (a, icon, label) in [
            (StorageAction.open, StorageIcons.open, StorageStrings.actionOpen),
            (StorageAction.share, StorageIcons.share, StorageStrings.share),
            (
              StorageAction.download,
              StorageIcons.download,
              StorageStrings.download,
            ),
            if (file.conversationId != null)
              (
                StorageAction.openChat,
                StorageIcons.openChat,
                StorageStrings.openChat,
              ),
            (StorageAction.select, StorageIcons.select, StorageStrings.select),
            (StorageAction.rename, StorageIcons.rename, StorageStrings.rename),
          ])
            _SheetRow(
              icon: icon,
              label: label,
              onTap: () => Navigator.pop(sheet, a),
            ),
          Divider(color: p.border),
          _SheetRow(
            icon: StorageIcons.delete,
            label: StorageStrings.delete,
            color: p.accent,
            onTap: () => Navigator.pop(sheet, StorageAction.delete),
          ),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case StorageAction.open:
      await openStorageFile(context, controller, file);
    case StorageAction.share:
      await shareStorageFile(context, file);
    case StorageAction.download:
      await downloadStorageFile(context, file);
    case StorageAction.openChat:
      openStorageChat(context, file);
    case StorageAction.select:
      controller.startSelecting(file.id);
    case StorageAction.rename:
      await renameStorageFile(context, controller, file);
    case StorageAction.delete:
      await confirmStorageDelete(context, controller, [file.id]);
  }
}

/// Full preview; images swipe through the loaded images.
Future<void> openStorageFile(
  BuildContext context,
  StorageController controller,
  FileInfo file,
) => openFilePreview(context, controller.files, file);

/// Jumps back to the chat screen and opens the chat the file is in.
void openStorageChat(BuildContext context, FileInfo file) {
  final id = file.conversationId;
  if (id == null) return;
  Haptics.tap();
  Navigator.of(context).popUntil((r) => r.isFirst);
  AppNotifications.instance.opened.value = id;
}

Future<File?> _fetch(BuildContext context, FileInfo file, Directory dir) async {
  try {
    await dir.create(recursive: true);
    return await FilesApi.instance.download(file, dir);
  } catch (_) {
    if (context.mounted) {
      storageNotice(context, StorageStrings.shareFailed, error: true);
    }
    return null;
  }
}

Future<void> _shareFile(File f, FileInfo file) => SharePlus.instance.share(
  ShareParams(
    files: [XFile(f.path, mimeType: file.mime.isEmpty ? null : file.mime)],
  ),
);

/// Downloads to a temp file and opens the system share sheet.
Future<void> shareStorageFile(BuildContext context, FileInfo file) async {
  Haptics.tap();
  final tmp = await getTemporaryDirectory();
  if (!context.mounted) return;
  final f = await _fetch(
    context,
    file,
    Directory('${tmp.path}${Platform.pathSeparator}${file.id}'),
  );
  if (f == null) return;
  Haptics.received();
  await _shareFile(f, file);
}

/// Saves into the app's downloads folder, then offers the share sheet so
/// the file can go anywhere on the device (Files, Drive…).
Future<void> downloadStorageFile(BuildContext context, FileInfo file) async {
  Haptics.tap();
  final base =
      await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
  if (!context.mounted) return;
  final f = await _fetch(
    context,
    file,
    Directory(
      '${base.path}${Platform.pathSeparator}${StorageConfig.downloadFolder}',
    ),
  );
  if (f == null || !context.mounted) return;
  storageNotice(context, StorageStrings.saved);
  await _shareFile(f, file);
}

Future<void> renameStorageFile(
  BuildContext context,
  StorageController controller,
  FileInfo file,
) async {
  final dot = file.name.lastIndexOf('.');
  final base = dot > 0 ? file.name.substring(0, dot) : file.name;
  final field = TextEditingController(text: base);
  final name = await showDialog<String>(
    context: context,
    builder: (dialog) => StorageDialog(
      title: StorageStrings.rename,
      confirm: AppStrings.save,
      onConfirm: () => Navigator.pop(dialog, field.text.trim()),
      child: TextField(
        controller: field,
        autofocus: true,
        maxLength: 200,
        style: dialog.text.body,
        decoration: const InputDecoration(
          hintText: StorageStrings.renameHint,
          counterText: '',
        ),
        onSubmitted: (v) => Navigator.pop(dialog, v.trim()),
      ),
    ),
  );
  field.dispose();
  if (name == null || name.isEmpty || name == base || !context.mounted) return;
  final ok = await controller.rename(file, name);
  if (!context.mounted) return;
  storageNotice(
    context,
    ok ? StorageStrings.renamed : StorageStrings.renameFailed,
    error: !ok,
  );
}

/// Confirms, then deletes [ids]. Returns true when they were deleted.
Future<bool> confirmStorageDelete(
  BuildContext context,
  StorageController controller,
  List<String> ids,
) async {
  if (ids.isEmpty) return false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialog) => StorageDialog(
      title: StorageStrings.deleteTitle(ids.length),
      confirm: StorageStrings.delete,
      destructive: true,
      onConfirm: () => Navigator.pop(dialog, true),
      child: Text(StorageStrings.deleteBody, style: dialog.text.bodySmall),
    ),
  );
  if (ok != true || !context.mounted) return false;
  final n = await controller.delete(ids);
  if (!context.mounted) return n != null;
  storageNotice(
    context,
    n == null ? StorageStrings.deleteFailed : StorageStrings.deleted(n),
    error: n == null,
  );
  return n != null;
}

/// Second line of a storage row: size, duration or pages, age, status.
String storageSubtitle(FileInfo f) {
  final parts = <String>[fileSubtitle(f)];
  if (f.status == FileStatus.processing) parts.add(StorageStrings.processing);
  if (f.status == FileStatus.failed) parts.add(StorageStrings.failed);
  return parts.where((s) => s.isNotEmpty).join(StorageStrings.separator);
}

class StorageDialog extends StatelessWidget {
  const StorageDialog({
    super.key,
    required this.title,
    required this.confirm,
    required this.onConfirm,
    required this.child,
    this.destructive = false,
  });

  final String title;
  final String confirm;
  final VoidCallback onConfirm;
  final Widget child;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AlertDialog(
      backgroundColor: p.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(color: p.border),
      ),
      title: Text(title, style: context.text.label),
      content: child,
      actions: [
        TextButton(
          onPressed: () {
            Haptics.tap();
            Navigator.pop(context);
          },
          child: Text(AppStrings.cancel, style: context.text.caption),
        ),
        TextButton(
          onPressed: () {
            Haptics.tap();
            onConfirm();
          },
          child: Text(
            confirm,
            style: context.text.caption.copyWith(
              color: destructive ? p.accent : p.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

class _SheetRow extends StatelessWidget {
  const _SheetRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final AppIconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return InkWell(
      onTap: () {
        Haptics.tap();
        onTap();
      },
      child: Container(
        height: AppSizes.sheetOptionHeight,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenPadding,
        ),
        child: Row(
          children: [
            AppIcon(
              icon,
              size: AppIconSize.md,
              color: color ?? p.textSecondary,
            ),
            const SizedBox(width: AppSpacing.md),
            Text(label, style: context.text.label.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}
