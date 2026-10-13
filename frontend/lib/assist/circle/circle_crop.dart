import 'dart:io';
import 'dart:ui' show Rect, Size;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../../core/constants/circle_search.dart';
import 'circle_geometry.dart';

/// Cuts the selection out of the frozen screenshot and writes it as a JPEG
/// next to it. An interface so widget tests crop without files.
abstract class CircleCropper {
  /// The cut-out's path, or null when it could not be made.
  Future<String?> crop(String screenshot, Rect selection, Size view);
}

class JpegCircleCropper implements CircleCropper {
  const JpegCircleCropper();

  @override
  Future<String?> crop(String screenshot, Rect selection, Size view) async {
    final out =
        '${File(screenshot).parent.path}${Platform.pathSeparator}'
        '${CircleConfig.cropPrefix}${DateTime.now().microsecondsSinceEpoch}.jpg';
    try {
      return await compute(
        cropJpeg,
        CropJob(
          source: screenshot,
          target: out,
          left: selection.left,
          top: selection.top,
          right: selection.right,
          bottom: selection.bottom,
          viewWidth: view.width,
          viewHeight: view.height,
        ),
      );
    } catch (e) {
      debugPrint('circle: crop isolate failed: $e');
      return null;
    }
  }
}

/// One crop, sent to a background isolate.
class CropJob {
  const CropJob({
    required this.source,
    required this.target,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.viewWidth,
    required this.viewHeight,
  });

  final String source, target;
  final double left, top, right, bottom, viewWidth, viewHeight;
}

/// Decodes the screenshot, cuts out the padded selection and writes it.
/// Returns [CropJob.target], or null for an unreadable image or a selection
/// too small to mean anything.
Future<String?> cropJpeg(CropJob job) async {
  final bytes = await File(job.source).readAsBytes();
  final image = img.decodeImage(bytes);
  if (image == null) return null;
  final rect = cropRectFor(
    Rect.fromLTRB(job.left, job.top, job.right, job.bottom),
    view: Size(job.viewWidth, job.viewHeight),
    image: Size(image.width.toDouble(), image.height.toDouble()),
  );
  if (rect == null) return null;
  final cut = img.copyCrop(
    image,
    x: rect.left.toInt(),
    y: rect.top.toInt(),
    width: rect.width.toInt(),
    height: rect.height.toInt(),
  );
  await File(
    job.target,
  ).writeAsBytes(img.encodeJpg(cut, quality: CircleSizes.jpegQuality));
  return job.target;
}
