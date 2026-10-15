import '../../../data/file_insight.dart';

final _structured = RegExp(r'^\s*(#{1,6}\s|[-*•]\s|\d+[.)]\s|>|\||```|\t)');

/// Text a server extracted from a PDF or Office file (hard-wrapped lines,
/// stray spaces) as markdown that reads like a page: wrapped prose is joined
/// into paragraphs, short lines keep their breaks, lists / headings / tables
/// are left alone and runs of blank lines collapse.
String readableMarkdown(String raw) {
  final text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final out = <String>[];
  for (final block in text.split(RegExp(r'\n\s*\n'))) {
    final lines = [
      for (final l in block.split('\n'))
        if (l.trim().isNotEmpty) l.replaceAll(RegExp(r'[ \t]+$'), ''),
    ];
    if (lines.isEmpty) continue;
    if (lines.any(_structured.hasMatch)) {
      out.add(lines.join('\n'));
      continue;
    }
    final avg =
        lines.fold<int>(0, (n, l) => n + l.trim().length) / lines.length;
    if (lines.length == 1) {
      out.add(lines.first.trim());
    } else if (avg >= _proseLine) {
      out.add(lines.map((l) => l.trim()).join(' '));
    } else {
      out.add(lines.map((l) => l.trim()).join('  \n'));
    }
  }
  return out.join('\n\n');
}

/// Lines this long on average are wrapped prose, not poetry or a list.
const _proseLine = 48;

/// One row of a video timeline: a described frame or a stretch of speech.
class TimelineEntry {
  const TimelineEntry({
    required this.t,
    required this.text,
    required this.speech,
  });
  final double t;
  final String text;

  /// True for transcript text, false for a frame description.
  final bool speech;
}

/// Frame descriptions and transcript lines in the order they happen.
List<TimelineEntry> timelineOf(VideoTimeline v) {
  final all = [
    for (final f in v.frames)
      if ((f.caption ?? '').trim().isNotEmpty)
        TimelineEntry(t: f.t, text: f.caption!.trim(), speech: false),
    for (final s in v.segments)
      if (s.text.trim().isNotEmpty)
        TimelineEntry(t: s.start, text: s.text.trim(), speech: true),
  ];
  // Stable: a frame comes before the speech that starts at the same second.
  final indexed = all.indexed.toList()
    ..sort((a, b) {
      final c = a.$2.t.compareTo(b.$2.t);
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
  return [for (final e in indexed) e.$2];
}
