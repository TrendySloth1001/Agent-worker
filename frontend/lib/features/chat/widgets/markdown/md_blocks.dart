/// Splits reply markdown into the blocks that get a custom widget (lists,
/// tables, callouts) and plain markdown in between. Fenced code is never
/// inspected.
sealed class MdBlock {
  const MdBlock();
}

class MdText extends MdBlock {
  const MdText(this.text);
  final String text;
}

class MdListBlock extends MdBlock {
  const MdListBlock(this.list);
  final MdList list;
}

class MdTableBlock extends MdBlock {
  const MdTableBlock({
    required this.header,
    required this.rows,
    required this.source,
  });
  final List<String> header;
  final List<List<String>> rows;

  /// The table as written, for copying.
  final String source;
}

/// A picture the model asked for on its own line: `{{image:QUERY|CAPTION}}`.
class MdImageBlock extends MdBlock {
  const MdImageBlock(this.query, this.caption);
  final String query;
  final String? caption;
}

/// Display math: `$$…$$`, `\[…\]` or a ```math / ```latex / ```tex fence.
class MdMathBlock extends MdBlock {
  const MdMathBlock(this.tex);
  final String tex;
}

/// A section title: `## text`, or a line that is only bold text (the model's
/// "pseudo heading"), optionally led by an `{{icon:…}}`.
class MdHeadingBlock extends MdBlock {
  const MdHeadingBlock(this.level, this.text, {this.icon});
  final int level;
  final String text;

  /// `set:name` of a leading icon, if any.
  final String? icon;
}

enum CalloutKind { note, tip, important, warning, caution, summary }

class MdCalloutBlock extends MdBlock {
  const MdCalloutBlock(this.kind, this.body);
  final CalloutKind kind;
  final String body;
}

class MdList {
  MdList({required this.ordered});
  final bool ordered;
  final List<MdItem> items = [];

  /// Any item led by an icon: the whole level then uses icon-sized markers.
  bool get hasIcons => items.any((i) => i.icon != null);
}

// The model sometimes wraps the icon in emphasis: `**{{icon:…}}** text`.
final _leadIconRe = RegExp(
  r'^(?:\*\*|__|\*|_)?\{\{icon:([a-z0-9]+(?:-[a-z0-9]+)*):([a-z0-9]+(?:-[a-z0-9]+)*)\}\}(?:\*\*|__|\*|_)?\s*',
);

class MdItem {
  MdItem({required this.number, required this.text, this.checked});
  final int number;
  String text;
  final bool? checked;
  MdList? children;

  /// `set:name` when the item starts with `{{icon:set:name}}`; it becomes
  /// the item's marker. Checklist items keep their checkbox.
  String? get icon {
    if (checked != null) return null;
    final m = _leadIconRe.firstMatch(text);
    return m == null ? null : '${m[1]}:${m[2]}';
  }

  /// The text without its leading icon.
  String get body => icon == null ? text : text.replaceFirst(_leadIconRe, '');
}

final _imageLineRe = RegExp(
  r'^\s*\{\{image:([^}|]{2,120})(?:\|([^}]{1,160}))?\}\}\s*$',
);

final _mathFenceLangRe = RegExp(r'^(?:math|latex|tex)$', caseSensitive: false);

/// A display-math block starting at [start]: `$$` or `\[` on its own, with
/// the closer either on the same line or on a later line that ends the block.
(MdMathBlock, int)? _tryMath(List<String> lines, int start) {
  final first = lines[start].trim();
  final String open, close;
  if (first.startsWith(r'$$')) {
    open = r'$$';
    close = r'$$';
  } else if (first.startsWith(r'\[')) {
    open = r'\[';
    close = r'\]';
  } else {
    return null;
  }
  final body = <String>[];
  var rest = first.substring(open.length);
  var j = start;
  while (true) {
    final k = rest.indexOf(close);
    if (k >= 0) {
      // Text after the closer means this is inline math inside a sentence.
      if (rest.substring(k + close.length).trim().isNotEmpty) return null;
      body.add(rest.substring(0, k));
      final tex = body.join('\n').trim();
      if (tex.isEmpty) return null;
      return (MdMathBlock(tex), j + 1);
    }
    body.add(rest);
    j++;
    if (j >= lines.length) return null;
    rest = lines[j];
  }
}

final _fenceRe = RegExp(r'^(\s*)(`{3,}|~{3,})');
final _markerRe = RegExp(r'^(\s*)([-*+]|\d{1,9}[.)])(\s+)(.*)$');
final _hrRe = RegExp(r'^\s{0,3}([-*_])(?:\s*\1){2,}\s*$');
final _taskRe = RegExp(r'^\[( |x|X)\]\s+');
final _breakRe = RegExp(r'^\s{0,1}(#{1,6}\s|>)');
final _calloutRe = RegExp(
  r'^\s{0,3}>\s?\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION|SUMMARY)\]\s*(.*)$',
  caseSensitive: false,
);
final _quoteRe = RegExp(r'^\s{0,3}>\s?');
final _headingRe = RegExp(r'^\s{0,3}(#{1,4})\s+(.+?)\s*#*\s*$');
final _boldLineRe = RegExp(r'^\s{0,3}\*\*([^*\n]{2,80})\*\*\s*:?\s*$');

/// A heading line, or a whole-line bold title, as a block; null otherwise.
MdHeadingBlock? _tryHeading(String line) {
  var rest = line.trim();
  String? icon;
  final h = _headingRe.firstMatch(line);
  var level = 3;
  if (h != null) {
    level = h[1]!.length;
    rest = h[2]!.trim();
  }
  final lead = _leadIconRe.firstMatch(rest);
  if (lead != null) {
    icon = '${lead[1]}:${lead[2]}';
    rest = rest.substring(lead.end).trim();
  }
  if (h == null) {
    final b = _boldLineRe.firstMatch(rest);
    if (b == null) return null;
    rest = b[1]!.trim();
  } else {
    // "## **Title**" reads the same as "## Title".
    final b = _boldLineRe.firstMatch(rest);
    if (b != null) rest = b[1]!.trim();
  }
  rest = rest.replaceFirst(RegExp(r':$'), '');
  if (rest.isEmpty) return null;
  return MdHeadingBlock(level, rest, icon: icon);
}

final _delimCellRe = RegExp(r'^\s*:?-+:?\s*$');

int _indentOf(String line) {
  var n = 0;
  while (n < line.length && line.codeUnitAt(n) == 0x20) {
    n++;
  }
  return n;
}

/// Returns the fence marker (char + length) if [line] opens/closes a fence.
({String char, int len, bool bare})? _fenceOf(String line) {
  final m = _fenceRe.firstMatch(line);
  if (m == null) return null;
  final marker = m[2]!;
  final rest = line.substring(m.end);
  return (char: marker[0], len: marker.length, bare: rest.trim().isEmpty);
}

List<MdBlock> parseBlocks(String src) {
  final lines = src.split('\n');
  final out = <MdBlock>[];
  final buf = <String>[];

  void flush() {
    final text = buf.join('\n');
    if (text.trim().isNotEmpty) out.add(MdText(text));
    buf.clear();
  }

  var i = 0;
  while (i < lines.length) {
    final line = lines[i];

    final fence = _fenceOf(line);
    if (fence != null) {
      final lang = line.trim().replaceFirst(RegExp(r'^[`~]+'), '').trim();
      if (_mathFenceLangRe.hasMatch(lang)) {
        var j = i + 1;
        final body = <String>[];
        var closed = false;
        while (j < lines.length) {
          final f = _fenceOf(lines[j]);
          j++;
          if (f != null &&
              f.bare &&
              f.char == fence.char &&
              f.len >= fence.len) {
            closed = true;
            break;
          }
          body.add(lines[j - 1]);
        }
        if (closed && body.join('').trim().isNotEmpty) {
          flush();
          out.add(MdMathBlock(body.join('\n').trim()));
          i = j;
          continue;
        }
      }
      buf.add(line);
      i++;
      while (i < lines.length) {
        final l = lines[i];
        buf.add(l);
        i++;
        final f = _fenceOf(l);
        if (f != null && f.bare && f.char == fence.char && f.len >= fence.len) {
          break;
        }
      }
      continue;
    }

    final math = _tryMath(lines, i);
    if (math != null) {
      flush();
      out.add(math.$1);
      i = math.$2;
      continue;
    }

    final table = _tryTable(lines, i);
    if (table != null) {
      flush();
      out.add(table.$1);
      i = table.$2;
      continue;
    }

    final image = _imageLineRe.firstMatch(line);
    if (image != null) {
      flush();
      final caption = image[2]?.trim();
      out.add(
        MdImageBlock(
          image[1]!.trim(),
          caption == null || caption.isEmpty ? null : caption,
        ),
      );
      i++;
      continue;
    }

    final callout = _calloutRe.firstMatch(line);
    if (callout != null) {
      flush();
      final body = <String>[];
      if (callout[2]!.trim().isNotEmpty) body.add(callout[2]!);
      i++;
      while (i < lines.length && _quoteRe.hasMatch(lines[i])) {
        body.add(lines[i].replaceFirst(_quoteRe, ''));
        i++;
      }
      out.add(
        MdCalloutBlock(
          CalloutKind.values.byName(callout[1]!.toLowerCase()),
          body.join('\n').trim(),
        ),
      );
      continue;
    }

    final heading = _tryHeading(line);
    if (heading != null) {
      flush();
      out.add(heading);
      i++;
      continue;
    }

    final m = _markerRe.firstMatch(line);
    if (m != null && m[1]!.length <= 3 && !_hrRe.hasMatch(line)) {
      flush();
      final r = _parseList(lines, i);
      out.add(MdListBlock(r.$1));
      i = r.$2;
      continue;
    }

    buf.add(line);
    i++;
  }
  flush();
  return out;
}

/// End index (exclusive) of a `$...$` math span opening at [k] in [s], or -1.
/// Mirrors the inline rule: the opener is followed by a non-space, the closer
/// follows a non-space and is not followed by a digit.
int _mathSpanEnd(String s, int k) {
  if (k + 1 >= s.length || s[k + 1] == ' ' || s[k + 1] == r'$') return -1;
  if (k > 0 && RegExp(r'[\w\\]').hasMatch(s[k - 1])) return -1;
  for (var j = k + 1; j < s.length; j++) {
    if (s[j] == r'\') {
      j++;
      continue;
    }
    if (s[j] == r'$') {
      final prevOk = s[j - 1] != ' ';
      final nextOk = j + 1 >= s.length || !RegExp(r'\d').hasMatch(s[j + 1]);
      if (prevOk && nextOk && j > k + 1) return j + 1;
      return -1;
    }
  }
  return -1;
}

/// Splits a table row on `|`, treating `|` inside `$...$` math, inside
/// backtick code and escaped as `\|` as literal text.
List<String> _splitRow(String line) {
  var s = line.trim();
  if (s.startsWith('|')) s = s.substring(1);
  if (s.endsWith('|') && !s.endsWith(r'\|')) s = s.substring(0, s.length - 1);
  final cells = <String>[];
  final cur = StringBuffer();
  var inCode = false;
  for (var k = 0; k < s.length; k++) {
    final ch = s[k];
    if (ch == r'\' && k + 1 < s.length && s[k + 1] == '|') {
      cur.write('|');
      k++;
    } else if (ch == '`') {
      inCode = !inCode;
      cur.write(ch);
    } else if (ch == r'$' && !inCode) {
      final end = _mathSpanEnd(s, k);
      if (end < 0) {
        cur.write(ch);
      } else {
        // Math is copied verbatim (TeX `\|` stays `\|`).
        cur.write(s.substring(k, end));
        k = end - 1;
      }
    } else if (ch == '|' && !inCode) {
      cells.add(cur.toString().trim());
      cur.clear();
    } else {
      cur.write(ch);
    }
  }
  cells.add(cur.toString().trim());
  return cells;
}

(MdTableBlock, int)? _tryTable(List<String> lines, int i) {
  if (i + 1 >= lines.length) return null;
  final head = lines[i];
  final delim = lines[i + 1];
  if (!head.contains('|') || !delim.contains('-')) return null;
  if (_indentOf(head) > 3) return null;
  final delimCells = _splitRow(delim);
  if (!delimCells.every(_delimCellRe.hasMatch)) return null;
  final header = _splitRow(head);
  if (header.length != delimCells.length) return null;
  final cols = header.length;
  final rows = <List<String>>[];
  var j = i + 2;
  while (j < lines.length &&
      lines[j].trim().isNotEmpty &&
      lines[j].contains('|')) {
    final cells = _splitRow(lines[j]);
    while (cells.length < cols) {
      cells.add('');
    }
    rows.add(cells.sublist(0, cols));
    j++;
  }
  return (
    MdTableBlock(
      header: header,
      rows: rows,
      source: lines.sublist(i, j).join('\n'),
    ),
    j,
  );
}

class _Entry {
  _Entry({
    required this.indent,
    required this.contentIndent,
    required this.depth,
    required this.ordered,
    required this.item,
  });
  final int indent;
  final int contentIndent;
  final int depth;
  final bool ordered;
  final MdItem item;
  final List<String> lines = [];
}

(MdList, int) _parseList(List<String> lines, int start) {
  final entries = <_Entry>[];
  final stack = <int>[];
  var j = start;
  String? fenceChar;
  var fenceLen = 0;

  void addLine(String l) {
    final e = entries.last;
    final strip = _indentOf(l) < e.contentIndent
        ? _indentOf(l)
        : e.contentIndent;
    e.lines.add(l.substring(strip));
  }

  loop:
  while (j < lines.length) {
    final line = lines[j];

    if (fenceChar != null) {
      addLine(line);
      final f = _fenceOf(line);
      if (f != null && f.bare && f.char == fenceChar && f.len >= fenceLen) {
        fenceChar = null;
      }
      j++;
      continue;
    }

    if (line.trim().isEmpty) {
      var k = j + 1;
      while (k < lines.length && lines[k].trim().isEmpty) {
        k++;
      }
      if (k >= lines.length) break;
      final next = lines[k];
      final continues =
          _indentOf(next) >= 2 ||
          (_markerRe.hasMatch(next) &&
              _indentOf(next) <= 3 &&
              !_hrRe.hasMatch(next));
      if (!continues) break;
      for (var b = j; b < k; b++) {
        entries.last.lines.add('');
      }
      j = k;
      continue;
    }

    final m = _markerRe.firstMatch(line);
    if (m != null && !_hrRe.hasMatch(line)) {
      final indent = m[1]!.length;
      if (stack.isEmpty) {
        stack.add(indent);
      } else if (indent >= stack.last + 2) {
        stack.add(indent);
      } else {
        while (stack.length > 1 && indent <= stack.last - 2) {
          stack.removeLast();
        }
      }
      final marker = m[2]!;
      final ordered = RegExp(r'^\d').hasMatch(marker);
      // A different kind of marker at the top level starts a new list.
      if (stack.length == 1 &&
          entries.isNotEmpty &&
          ordered != entries.first.ordered) {
        break;
      }
      var text = m[4]!;
      bool? checked;
      final task = _taskRe.firstMatch(text);
      if (task != null) {
        checked = task[1] != ' ';
        text = text.substring(task.end);
      }
      final number = ordered
          ? int.parse(marker.replaceAll(RegExp(r'\D'), ''))
          : 0;
      final e = _Entry(
        indent: indent,
        contentIndent: indent + marker.length + m[3]!.length,
        depth: stack.length - 1,
        ordered: ordered,
        item: MdItem(number: number, text: '', checked: checked),
      );
      e.lines.add(text);
      entries.add(e);
      j++;
      continue;
    }

    // Not a marker: continuation of the last item, or the end of the list.
    final prevBlank =
        entries.isNotEmpty && j > start && lines[j - 1].trim().isEmpty;
    if (!prevBlank && _breakRe.hasMatch(line) && _indentOf(line) < 2) {
      break loop;
    }
    final f = _fenceOf(line);
    if (f != null) {
      fenceChar = f.char;
      fenceLen = f.len;
    }
    addLine(line);
    j++;
  }

  // Build the tree.
  final root = MdList(ordered: entries.first.ordered);
  final lists = <MdList>[root];
  for (final e in entries) {
    while (lists.length > e.depth + 1) {
      lists.removeLast();
    }
    if (lists.length == e.depth) {
      final parent = lists.last.items.last;
      final sub = MdList(ordered: e.ordered);
      parent.children = sub;
      lists.add(sub);
    }
    e.item.text = e.lines.join('\n').trimRight();
    lists.last.items.add(e.item);
  }
  return (root, j);
}
