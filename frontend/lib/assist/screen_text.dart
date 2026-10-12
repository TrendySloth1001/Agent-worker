import '../core/constants/assist.dart';

/// One text node the system reported for the screen behind the overlay.
class ScreenNode {
  const ScreenNode(this.text, {this.description = false});

  final String text;

  /// A content description (an image or icon label), not visible text.
  final bool description;

  static List<ScreenNode> fromChannel(Object? raw) => [
    for (final n in raw is List ? raw : const [])
      if (n is Map && n[AssistChannel.nodeText] is String)
        ScreenNode(
          n[AssistChannel.nodeText] as String,
          description: n[AssistChannel.nodeDesc] == true,
        ),
  ];
}

/// What the user shared from the screen ("Share screen with sparky").
class ScreenContext {
  const ScreenContext({
    this.text = '',
    this.app,
    this.package,
    this.url,
    this.screenshotPath,
    this.structureArrived = false,
  });

  /// Trimmed, deduped visible text (see [buildScreenText]).
  final String text;
  final String? app;
  final String? package;
  final String? url;

  /// A JPEG in the app's cache; only when "Use screenshot" is on.
  final String? screenshotPath;

  /// False when the system sent no view structure (text from screen off).
  final bool structureArrived;

  bool get hasScreenshot => screenshotPath != null;
  bool get isEmpty => text.isEmpty && url == null && !hasScreenshot;

  /// The app's name for the chip, falling back to its package.
  String? get appName {
    final a = app?.trim();
    if (a != null && a.isNotEmpty) return a;
    final p = package?.trim();
    return p == null || p.isEmpty ? null : p;
  }

  factory ScreenContext.fromChannel(Map<Object?, Object?> m) {
    String? s(String k) {
      final v = m[k];
      return v is String && v.trim().isNotEmpty ? v.trim() : null;
    }

    return ScreenContext(
      text: buildScreenText(ScreenNode.fromChannel(m[AssistChannel.nodes])),
      app: s(AssistChannel.app),
      package: s(AssistChannel.package),
      url: s(AssistChannel.url),
      screenshotPath: s(AssistChannel.screenshot),
      structureArrived: m[AssistChannel.structureArrived] == true,
    );
  }

  /// The `screen` field of a chat request.
  Map<String, Object> toJson() => {
    AssistWire.text: text,
    AssistWire.app: ?app,
    AssistWire.package: ?package,
    AssistWire.url: ?url,
    if (hasScreenshot) AssistWire.screenshot: true,
  };
}

final _space = RegExp(r'\s+');
final _invisible = RegExp('[​-‏⁠﻿]');

/// Visible text of a screen as one block: whitespace collapsed per line,
/// exact and contained duplicates dropped (lists repeat titles, a parent
/// often repeats its children), short content descriptions (button labels
/// such as "Back") skipped, long lines cut, and the whole capped at
/// [maxChars] on a line boundary.
String buildScreenText(
  List<ScreenNode> nodes, {
  int maxChars = AssistConfig.maxScreenChars,
}) {
  final lines = <String>[];
  final seen = <String>{};
  var total = 0;
  for (final node in nodes) {
    var line = node.text
        .replaceAll(_invisible, '')
        .replaceAll(_space, ' ')
        .trim();
    if (line.isEmpty) continue;
    if (node.description &&
        line.split(' ').length < AssistConfig.minDescriptionWords) {
      continue;
    }
    if (line.length > AssistConfig.maxLineChars) {
      line = '${line.substring(0, AssistConfig.maxLineChars).trimRight()}…';
    }
    final key = line.toLowerCase();
    if (!seen.add(key)) continue;
    // Already said by a longer line just before (a container and its label).
    if (lines.isNotEmpty && lines.last.toLowerCase().contains(key)) continue;
    // This line contains the previous one: keep the fuller text only.
    if (lines.isNotEmpty && key.contains(lines.last.toLowerCase())) {
      total -= lines.removeLast().length + 1;
    }
    if (total + line.length + 1 > maxChars) {
      final room = maxChars - total - 1;
      // A long first line still gives something; otherwise stop cleanly.
      if (lines.isEmpty && room > 0) {
        lines.add('${line.substring(0, room - 1).trimRight()}…');
      }
      break;
    }
    lines.add(line);
    total += line.length + 1;
  }
  return lines.join('\n');
}
