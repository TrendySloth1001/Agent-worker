import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/constants/error_copy.dart';
import '../../core/constants/app_files.dart';
import '../../core/notify/job_watch.dart';
import '../../data/chat_api.dart';
import '../../data/files_api.dart';

enum PendingState { uploading, uploaded, failed }

/// One file in the composer, from pick to upload.
class PendingAttachment {
  PendingAttachment({
    required this.localPath,
    required this.name,
    required this.size,
  }) : kind = guessKind(name);

  final String localPath;
  final String name;
  final int size;
  final FileKind kind;

  PendingState state = PendingState.uploading;
  double progress = 0;
  FileInfo? info;
  String? error;
  final cancel = UploadCancel();
  Future<void>? task;

  /// What previews and bubbles show: server info once uploaded, else the
  /// local file alone.
  FileInfo get asFile =>
      info?.withLocalPath(localPath) ??
      FileInfo(
        id: '',
        name: name,
        mime: mimeFor(name),
        size: size,
        kind: kind,
        localPath: localPath,
      );

  bool get processing =>
      state == PendingState.uploaded && info?.status == FileStatus.processing;
  bool get failed =>
      state == PendingState.failed || info?.status == FileStatus.failed;
}

/// Files being attached to the next message.
class AttachmentsController extends ChangeNotifier {
  AttachmentsController({FilesApi? files})
    : _files = files ?? FilesApi.instance;

  /// Uploads go here (a fake in tests).
  final FilesApi _files;

  final List<PendingAttachment> items = [];

  bool get isFull => items.length >= AppFiles.maxPerMessage;
  int get free => AppFiles.maxPerMessage - items.length;
  bool get hasUploaded => items.any((a) => a.info != null && !a.failed);
  bool get uploading => items.any((a) => a.state == PendingState.uploading);
  bool get hasFailed => items.any((a) => a.failed);

  /// Files dropped by the last [add] because the message was full.
  int skipped = 0;

  /// Returns a problem key ('big', 'type') for the first rejected file.
  String? add(Iterable<({String path, String name, int size})> picked) {
    String? problem;
    skipped = 0;
    for (final f in picked) {
      if (isFull) {
        skipped++;
        continue;
      }
      final kind = guessKind(f.name);
      if (mimeFor(f.name) == AppFiles.fallbackMime &&
          kind == FileKind.document) {
        problem ??= 'type';
        continue;
      }
      if (f.size > maxBytesFor(kind)) {
        problem ??= 'big';
        continue;
      }
      final a = PendingAttachment(
        localPath: f.path,
        name: f.name,
        size: f.size,
      );
      items.add(a);
      _start(a);
    }
    notifyListeners();
    return problem;
  }

  void _start(PendingAttachment a) {
    a
      ..state = PendingState.uploading
      ..progress = 0
      ..error = null;
    var last = 0.0;
    a.task = _files
        .upload(
          a.localPath,
          name: a.name,
          cancel: a.cancel,
          onProgress: (p) {
            if (p - last < 0.02 && p < 1) return;
            last = p;
            a.progress = p;
            notifyListeners();
          },
        )
        .then((info) {
          if (a.cancel.cancelled) {
            unawaited(_files.delete(info.id).catchError((Object _) {}));
            return;
          }
          a.info = info.withLocalPath(a.localPath);
          a.state = PendingState.uploaded;
          notifyListeners();
          if (info.status == FileStatus.processing) {
            _poll(a);
            // Keeps watching after the composer is gone or the app is left.
            JobWatch.instance.watchFile(info);
          }
        })
        .catchError((Object e) {
          if (a.cancel.cancelled) return;
          a.state = PendingState.failed;
          a.error = e is ApiException ? friendlyException(e) : null;
          notifyListeners();
        });
  }

  /// Watches processing until the server marks the file ready or failed.
  Future<void> _poll(PendingAttachment a) async {
    for (var i = 0; i < 60; i++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (a.cancel.cancelled || !items.contains(a)) return;
      try {
        final fresh = await _files.get(a.info!.id, force: true);
        a.info = a.info!.withFresh(fresh);
        notifyListeners();
        if (fresh.status != FileStatus.processing) return;
      } catch (_) {
        return;
      }
    }
  }

  void retry(PendingAttachment a) {
    if (!a.failed) return;
    final old = a.info?.id;
    if (old != null) {
      unawaited(_files.delete(old).catchError((Object _) {}));
    }
    a.info = null;
    _start(a);
    notifyListeners();
  }

  void remove(PendingAttachment a) {
    items.remove(a);
    a.cancel.cancel();
    final id = a.info?.id;
    if (id != null) {
      unawaited(_files.delete(id).catchError((Object _) {}));
    }
    notifyListeners();
  }

  /// Waits for running uploads. Returns the files to send, or null when a
  /// file failed and the user must fix it first.
  Future<List<FileInfo>?> settle() async {
    await Future.wait([
      for (final a in items)
        if (a.task != null) a.task!,
    ]);
    if (items.any((a) => a.failed)) return null;
    return [
      for (final a in items)
        if (a.info != null) a.info!,
    ];
  }

  /// Forgets the files after they were sent (the server keeps them).
  void clearSent() {
    items.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    for (final a in items) {
      a.cancel.cancel();
    }
    super.dispose();
  }
}

/// Reads a picked path into the record [AttachmentsController.add] takes.
({String path, String name, int size}) pickedFile(String path, [String? name]) {
  final n = name ?? path.split(Platform.pathSeparator).last;
  return (path: path, name: n, size: File(path).lengthSync());
}
