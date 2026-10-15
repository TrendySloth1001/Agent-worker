import 'package:app/data/file_insight.dart';
import 'package:app/data/files_api.dart';

/// A stand-in for the server's reading of a file (insight and text pages).
class FakeUnderstanding implements FileUnderstanding {
  InsightData data = const InsightData(hasText: false, chars: 0);
  InsightData? afterRead;
  List<String> pages = const [''];
  bool failInsight = false;
  bool failRead = false;
  int insightCalls = 0;
  int readCalls = 0;
  final offsets = <int>[];

  @override
  Future<InsightData> insight(String id) async {
    insightCalls++;
    if (failInsight) throw StateError('offline');
    return data;
  }

  @override
  Future<InsightData> read(String id) async {
    readCalls++;
    if (failRead) throw StateError('nope');
    data = afterRead ?? data;
    return data;
  }

  @override
  Future<FileText> text(String id, {int offset = 0, int limit = 0}) async {
    offsets.add(offset);
    var start = 0;
    var i = 0;
    while (i < pages.length - 1 && start + pages[i].length <= offset) {
      start += pages[i].length;
      i++;
    }
    final total = pages.fold<int>(0, (n, p) => n + p.length);
    return FileText(
      text: pages[i],
      truncated: i < pages.length - 1,
      chars: total,
      offset: offset,
    );
  }
}

InsightData docData({
  String? summary,
  List<String> points = const [],
  int chars = 40,
}) => InsightData(
  hasText: true,
  chars: chars,
  insight: summary == null
      ? null
      : FileInsight(summary: summary, keyPoints: points),
);

InsightData imageData() => const InsightData(
  hasText: false,
  chars: 0,
  insight: FileInsight(
    summary: 'A receipt on a wooden table.',
    caption: 'A receipt on a wooden table.',
    ocr: 'TOTAL 12.40',
    keyPoints: ['Cafe receipt'],
  ),
);

InsightData videoData() => const InsightData(
  hasText: true,
  chars: 20,
  insight: FileInsight(
    summary: 'A short clip of a dog on a beach.',
    keyPoints: ['Dog runs', 'Sunny day'],
  ),
  video: VideoTimeline(
    durationS: 42,
    captionStatus: 'ok',
    transcriptStatus: 'ok',
    frames: [
      TimelineFrame(t: 0, caption: 'A dog runs across a beach.'),
      TimelineFrame(t: 20, caption: 'The dog jumps into the waves.'),
    ],
    segments: [TimelineSegment(start: 3, end: 8, text: 'Look at him go')],
  ),
);
