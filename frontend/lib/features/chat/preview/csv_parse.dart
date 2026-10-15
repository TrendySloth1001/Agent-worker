/// A small CSV reader for the table preview: quoted cells with commas and
/// line breaks, doubled quotes, comma / tab / semicolon delimiters.
List<List<String>> parseCsv(String text, {String? delimiter}) {
  final d = delimiter ?? detectDelimiter(text);
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  var i = 0;

  void endCell() {
    row.add(cell.toString());
    cell.clear();
  }

  void endRow() {
    endCell();
    // A blank line is no row.
    if (!(row.length == 1 && row.first.isEmpty)) rows.add(row);
    row = <String>[];
  }

  while (i < text.length) {
    final c = text[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cell.write(c);
      }
    } else if (c == '"' && cell.isEmpty) {
      quoted = true;
    } else if (c == d) {
      endCell();
    } else if (c == '\n') {
      endRow();
    } else if (c == '\r') {
      if (i + 1 < text.length && text[i + 1] == '\n') i++;
      endRow();
    } else {
      cell.write(c);
    }
    i++;
  }
  if (cell.isNotEmpty || row.isNotEmpty) endRow();
  return rows;
}

/// The delimiter used most on the first line.
String detectDelimiter(String text) {
  final end = text.indexOf('\n');
  final line = end < 0 ? text : text.substring(0, end);
  var best = ',';
  var most = 0;
  for (final d in const [',', '\t', ';']) {
    final n = d.allMatches(line).length;
    if (n > most) {
      most = n;
      best = d;
    }
  }
  return best;
}
