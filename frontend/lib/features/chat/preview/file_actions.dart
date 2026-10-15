import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/confirm_copy.dart';
import '../../../core/constants/preview.dart';
import '../../../core/constants/storage.dart';
import '../../../core/haptics.dart';
import '../../../core/platform/browsers.dart';
import '../../../core/widgets/confirm_sheet.dart';
import '../../../core/widgets/illustration.dart';
import '../../../data/file_cache.dart';
import '../../../data/files_api.dart';
import '../chat_launch.dart';

void previewNotice(BuildContext context, String text, {bool error = false}) {
  error ? Haptics.error() : Haptics.received();
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// Can this file be deleted from here? Only stored files of the account
/// (Drive or knowledge items are not in storage).
bool canDeleteFile(FileInfo f) => f.id.isNotEmpty && !f.deleted;

/// Can a chat attach this file? It must be on the server.
bool canAskAboutFile(FileInfo f) =>
    f.id.isNotEmpty && !f.deleted && f.status != FileStatus.failed;

/// Starts a new chat with [file] attached (the same attach path as a sent
/// message) and leaves the preview.
void askAboutFile(BuildContext context, FileInfo file) {
  if (!canAskAboutFile(file)) return;
  Haptics.tap();
  Navigator.of(context).popUntil((r) => r.isFirst);
  ChatLaunch.instance.ask(PreviewStrings.askPrompt(file.name), files: [file]);
}

/// The bytes on disk, with a notice when they cannot be fetched.
Future<File?> _file(BuildContext context, FileInfo file) async {
  try {
    return await FileCache.instance.fetch(file);
  } catch (_) {
    if (context.mounted) {
      previewNotice(context, PreviewStrings.actionFailed, error: true);
    }
    return null;
  }
}

/// Hands the cached file to the system share sheet.
Future<void> shareFile(BuildContext context, FileInfo file) async {
  Haptics.tap();
  final f = await _file(context, file);
  if (f == null) return;
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(f.path, mimeType: file.mime.isEmpty ? null : file.mime)],
    ),
  );
}

/// Copies the file into the app's downloads folder.
Future<void> downloadFile(BuildContext context, FileInfo file) async {
  Haptics.tap();
  final f = await _file(context, file);
  if (f == null || !context.mounted) return;
  try {
    final base =
        await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    final dir = Directory(
      '${base.path}${Platform.pathSeparator}${StorageConfig.downloadFolder}',
    );
    await dir.create(recursive: true);
    await f.copy(
      '${dir.path}${Platform.pathSeparator}${safeFileName(file.name)}',
    );
    if (context.mounted) previewNotice(context, PreviewStrings.saved);
  } catch (_) {
    if (context.mounted) {
      previewNotice(context, PreviewStrings.actionFailed, error: true);
    }
  }
}

/// "Open with…": the Android chooser for the file's type.
Future<void> openFileWith(BuildContext context, FileInfo file) async {
  Haptics.tap();
  final f = await _file(context, file);
  if (f == null) return;
  final staged = await FileCache.instance.staged(file, f);
  final ok = await Browsers.openFile(
    staged.path,
    file.mime.isEmpty ? mimeFor(file.name) : file.mime,
  );
  if (!ok && context.mounted) {
    previewNotice(context, PreviewStrings.noApp, error: true);
  }
}

/// Confirms, deletes through the storage API and closes the preview.
/// Returns true when the file is gone.
Future<bool> deleteFileWithConfirm(BuildContext context, FileInfo file) async {
  if (!canDeleteFile(file)) return false;
  final ok = await ConfirmSheet.show(
    context,
    illustration: IllustrationKind.emptyKnowledge,
    kicker: ConfirmCopy.kickerDelete,
    title: PreviewStrings.deleteTitle,
    body: PreviewStrings.deleteBody,
    confirmLabel: StorageStrings.delete,
    destructive: true,
  );
  if (!ok || !context.mounted) return false;
  try {
    await FilesApi.instance.delete(file.id);
    await FileCache.instance.evict(file.id);
  } catch (_) {
    if (context.mounted) {
      previewNotice(context, PreviewStrings.deleteFailed, error: true);
    }
    return false;
  }
  if (context.mounted) {
    previewNotice(context, StorageStrings.deleted(1));
    Navigator.of(context).pop();
  }
  return true;
}
