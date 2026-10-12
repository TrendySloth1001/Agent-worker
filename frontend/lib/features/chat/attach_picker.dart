import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants/app_files.dart';
import '../../core/constants/app_strings.dart';
import '../../core/haptics.dart';
import 'attachments_controller.dart';
import 'widgets/chat_input.dart' show AttachChoice, showAttachSheet;

typedef PickedFile = ({String path, String name, int size});

/// Picks documents (PDF, Office, text, …); the system file picker by default.
typedef DocumentPicker = Future<List<PickedFile>> Function();

/// The "+" of the composer: photos and videos from the gallery, the camera,
/// or any document, added to an [AttachmentsController] (which uploads them
/// with progress and checks sizes and types). Shared by the app's chat and
/// the assistant overlay so both accept the same files.
class AttachPicker {
  AttachPicker({ImagePicker? images, DocumentPicker? documents})
    : _images = images ?? ImagePicker(),
      _documents = documents ?? _systemDocuments;

  final ImagePicker _images;
  final DocumentPicker _documents;

  static Future<List<PickedFile>> _systemDocuments() async {
    final list = await FilePicker.pickFiles();
    return [
      for (final f in list)
        if (f.path != null) pickedFile(f.path!, f.name),
    ];
  }

  /// Shows the sheet, picks and adds. [say] shows a short message (too big,
  /// unsupported, too many).
  Future<void> pick(
    BuildContext context,
    AttachmentsController files, {
    required void Function(String text) say,
  }) async {
    Haptics.tap();
    if (files.isFull) {
      say(AppStrings.attachMax);
      return;
    }
    final choice = await showAttachSheet(context);
    if (choice == null || !context.mounted) return;
    try {
      final picked = switch (choice) {
        AttachChoice.media => await _media(files.free),
        AttachChoice.photo => await _fromX([
          ?await _images.pickImage(source: ImageSource.camera),
        ]),
        AttachChoice.video => await _fromX([
          ?await _images.pickVideo(source: ImageSource.camera),
        ]),
        AttachChoice.document => await _documents(),
      };
      if (picked.isEmpty) return;
      final problem = files.add(picked);
      if (files.skipped > 0) {
        Haptics.error();
        say(AppStrings.attachSkipped(files.skipped, AppFiles.maxPerMessage));
      } else if (problem != null) {
        Haptics.error();
        say(
          problem == 'big'
              ? AppStrings.attachTooBig
              : AppStrings.attachUnsupported,
        );
      }
    } catch (_) {
      Haptics.error();
      say(AppStrings.attachUnsupported);
    }
  }

  Future<List<PickedFile>> _media(int free) async => _fromX(
    free < 2
        ? [?await _images.pickMedia()]
        : await _images.pickMultipleMedia(limit: free),
  );

  static Future<List<PickedFile>> _fromX(Iterable<XFile> xs) async => [
    for (final x in xs) (path: x.path, name: x.name, size: await x.length()),
  ];
}
