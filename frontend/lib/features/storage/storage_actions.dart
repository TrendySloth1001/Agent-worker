import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants/app_strings.dart';
import '../../core/constants/storage.dart';
import '../../core/haptics.dart';
import '../../core/notify/notification_center.dart';
import '../../core/notify/notify_target.dart';
import '../../core/theme/app_palette.dart';
import '../../core/widgets/m3_kit_extras.dart';
import '../../data/files_api.dart';
import '../chat/preview/file_preview.dart';
import '../settings/widgets/settings_kit.dart';
import '../chat/widgets/attachment_views.dart';
import 'storage_controller.dart';
import '../../core/widgets/confirm_sheet.dart';
import '../../core/widgets/illustration.dart';
import '../../core/constants/confirm_copy.dart';
import '../../core/widgets/input_sheet.dart';

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
  final action = await showM3Sheet<StorageAction>(
    context,
    builder: (sheet) => M3ActionSheet(
      title: file.name,
      rows: [
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
          SettingsTile(
            icon: icon,
            title: label,
            onTap: () => Navigator.pop(sheet, a),
          ),
        SettingsTile(
          icon: StorageIcons.delete,
          title: StorageStrings.delete,
          iconColor: sheet.palette.accent,
          titleColor: sheet.palette.accent,
          onTap: () => Navigator.pop(sheet, StorageAction.delete),
        ),
      ],
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
  NotificationCenter.instance.open(ChatTarget(id));
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
  final accepted = await InputSheet.show(
    context,
    kicker: ConfirmCopy.kickerRename,
    title: StorageStrings.rename,
    confirmLabel: AppStrings.save,
    field: (sheet, submit) => TextField(
      controller: field,
      autofocus: true,
      maxLength: 200,
      style: sheet.text.body,
      decoration: const InputDecoration(
        hintText: StorageStrings.renameHint,
        counterText: '',
      ),
      onSubmitted: (_) => submit(),
    ),
  );
  // The controller is left to the garbage collector: the sheet is still
  // animating out when this resumes.
  final name = accepted ? field.text.trim() : null;
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
  final ok = await ConfirmSheet.show(
    context,
    illustration: IllustrationKind.emptyKnowledge,
    kicker: ConfirmCopy.kickerDelete,
    title: StorageStrings.deleteTitle(ids.length),
    body: StorageStrings.deleteBody,
    confirmLabel: StorageStrings.delete,
    destructive: true,
  );
  if (!ok || !context.mounted) return false;
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
