import '../../core/constants/live_voice.dart';

final _fence = RegExp(r'```[\s\S]*?(```|$)');
final _image = RegExp(r'!\[[^\]]*\]\([^)]*\)');
final _link = RegExp(r'\[([^\]]+)\]\([^)]*\)');
final _cite = RegExp(r'\[(?:[A-Z]{0,2}\d+(?:,\s*)?)+\]');
final _marks = RegExp(r'[*_`~#>|]');
final _bullet = RegExp(r'^\s*(?:[-+]|\d+[.)])\s+', multiLine: true);
final _url = RegExp(r'https?://\S+');
final _space = RegExp(r'[ \t]+');
final _lines = RegExp(r'\s*\n+\s*');
final _spaceBeforeMark = RegExp(r'\s+([.,!?;:])');
final _doubleStop = RegExp(r'([.!?])(\.\s*)+');

/// Markdown as it should be read aloud: no code, links read by their text,
/// no citation tags, emphasis marks, bullets or bare URLs.
String speakable(String markdown) {
  var s = markdown
      .replaceAll(_fence, ' ')
      .replaceAll(_image, ' ')
      .replaceAllMapped(_link, (m) => m[1]!)
      .replaceAll(_cite, '')
      .replaceAll(_url, '')
      .replaceAll(_bullet, '')
      .replaceAll(_marks, '');
  s = s.replaceAll(_space, ' ').replaceAll(_lines, '. ').trim();
  return s
      .replaceAllMapped(_spaceBeforeMark, (m) => m[1]!)
      .replaceAllMapped(_doubleStop, (m) => '${m[1]} ')
      .trim();
}

/// The next part of a streaming answer to speak, cut after the last
/// finished sentence of [text] from [from] (all of it once [done]). A code
/// fence still open is never cut into. Returns the speakable chunk (may be
/// empty) and the new offset into [text].
(String, int) nextChunk(String text, int from, {required bool done}) {
  if (from >= text.length) return ('', from);
  var end = text.length;
  final rest = text.substring(from);
  // An unfinished fence: stop before it until it closes.
  final fences = '```'.allMatches(rest).toList();
  if (fences.length.isOdd) end = from + fences.last.start;
  if (!done || end < text.length) {
    final segment = text.substring(from, end);
    final cut = _lastBoundary(segment);
    if (cut < LiveConfig.minChunkChars) return ('', from);
    end = from + cut;
  }
  return (speakable(text.substring(from, end)), end);
}

/// Index just after the last sentence end (". ", "! ", "? ", a newline).
int _lastBoundary(String s) {
  for (var i = s.length - 1; i > 0; i--) {
    final c = s[i];
    if (c == '\n') return i + 1;
    if ((c == ' ') && '.!?'.contains(s[i - 1])) return i + 1;
  }
  return 0;
}

final _word = RegExp(r"[\p{L}\p{N}']+", unicode: true);

/// Whether [heard] (what the mic picked up while sparky talks) is the user
/// talking over it, not the phone's own voice: more than
/// [LiveConfig.bargeInWords] words that are not in what sparky [said].
bool isBargeIn(String heard, String said) {
  final own = {for (final w in _word.allMatches(said.toLowerCase())) w[0]!};
  var foreign = 0;
  for (final w in _word.allMatches(heard.toLowerCase())) {
    if (!own.contains(w[0]!)) foreign++;
  }
  return foreign > LiveConfig.bargeInWords;
}
