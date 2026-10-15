import '../core/constants/app_files.dart';
import 'files_api.dart';

/// A short reading of a file: what it is and what matters in it. Images also
/// carry a caption and the text read from the picture.
class FileInsight {
  const FileInsight({
    required this.summary,
    this.keyPoints = const [],
    this.caption,
    this.ocr,
  });

  final String summary;
  final List<String> keyPoints;
  final String? caption;
  final String? ocr;

  factory FileInsight.fromJson(Map<String, dynamic> j) => FileInsight(
    summary: j['summary'] as String? ?? '',
    keyPoints: [
      for (final p in j['keyPoints'] as List? ?? const [])
        if (p is String && p.trim().isNotEmpty) p,
    ],
    caption: _text(j['caption']),
    ocr: _text(j['ocr']),
  );

  static String? _text(Object? v) =>
      v is String && v.trim().isNotEmpty ? v : null;
}

/// One described frame of a video.
class TimelineFrame {
  const TimelineFrame({required this.t, this.caption});
  final double t;
  final String? caption;
}

/// One stretch of speech.
class TimelineSegment {
  const TimelineSegment({
    required this.start,
    required this.end,
    required this.text,
  });
  final double start;
  final double end;
  final String text;
}

/// A video's evidence pack: frame descriptions and the transcript by time.
class VideoTimeline {
  const VideoTimeline({
    required this.durationS,
    required this.captionStatus,
    required this.transcriptStatus,
    required this.frames,
    required this.segments,
  });

  final double durationS;

  /// pending, ok, partial or failed.
  final String captionStatus;

  /// ok, silent, failed or no_audio.
  final String transcriptStatus;
  final List<TimelineFrame> frames;
  final List<TimelineSegment> segments;

  bool get hasCaptions => frames.any((f) => (f.caption ?? '').isNotEmpty);

  factory VideoTimeline.fromJson(Map<String, dynamic> j) => VideoTimeline(
    durationS: (j['durationS'] as num?)?.toDouble() ?? 0,
    captionStatus: j['captionStatus'] as String? ?? 'pending',
    transcriptStatus: j['transcriptStatus'] as String? ?? 'silent',
    frames: [
      for (final f in j['frames'] as List? ?? const [])
        if (f is Map<String, dynamic>)
          TimelineFrame(
            t: (f['t'] as num?)?.toDouble() ?? 0,
            caption: f['caption'] as String?,
          ),
    ],
    segments: [
      for (final s in j['segments'] as List? ?? const [])
        if (s is Map<String, dynamic>)
          TimelineSegment(
            start: (s['start'] as num?)?.toDouble() ?? 0,
            end: (s['end'] as num?)?.toDouble() ?? 0,
            text: s['text'] as String? ?? '',
          ),
    ],
  );
}

/// GET /files/:id/insight.
class InsightData {
  const InsightData({
    required this.hasText,
    required this.chars,
    this.processing = false,
    this.failed = false,
    this.insight,
    this.video,
  });

  /// The server has extracted text (or a transcript) for the file.
  final bool hasText;
  final int chars;

  /// sparky is still reading the file.
  final bool processing;
  final bool failed;
  final FileInsight? insight;
  final VideoTimeline? video;

  factory InsightData.fromJson(Map<String, dynamic> j) {
    final i = j['insight'];
    final v = j['video'];
    return InsightData(
      hasText: j['hasText'] == true,
      chars: (j['chars'] as num?)?.toInt() ?? 0,
      processing: j['status'] == 'processing',
      failed: j['status'] == 'failed',
      insight: i is Map<String, dynamic> ? FileInsight.fromJson(i) : null,
      video: v is Map<String, dynamic> ? VideoTimeline.fromJson(v) : null,
    );
  }
}

/// What the sparky view of a preview reads. The default asks the server;
/// tests swap in a fake.
abstract class FileUnderstanding {
  static FileUnderstanding instance = _ApiUnderstanding();

  Future<InsightData> insight(String id);
  Future<InsightData> read(String id);
  Future<FileText> text(
    String id, {
    int offset = 0,
    int limit = AppFiles.textPreviewLimit,
  });
}

class _ApiUnderstanding implements FileUnderstanding {
  @override
  Future<InsightData> insight(String id) => FilesApi.instance.insight(id);

  @override
  Future<InsightData> read(String id) => FilesApi.instance.generateInsight(id);

  @override
  Future<FileText> text(
    String id, {
    int offset = 0,
    int limit = AppFiles.textPreviewLimit,
  }) => FilesApi.instance.text(id, offset: offset, limit: limit);
}
