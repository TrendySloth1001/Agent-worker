import '../../../core/constants/voice_fix.dart';
import 'transcript_lexicon.dart';
import 'word_diff.dart';

/// The on-device pass over a dictated segment: no network, a few
/// milliseconds. Spoken punctuation, pauses as punctuation, capitals,
/// numbers, dates, times and money, common mishearings, fillers, stutters,
/// one spelling per Hinglish word and the user's own names.
class LocalFix {
  const LocalFix(
    this.text, {
    this.edits = 0,
    this.confident = false,
    this.hinglish = false,
  });

  final String text;

  /// Word-level changes made (punctuation and capitals not counted).
  final int edits;

  /// Trusted as is: the model pass is skipped.
  final bool confident;
  final bool hinglish;
}

class _Tok {
  _Tok(this.w, {this.pause = false, this.punct = false});

  String w;

  /// The speaker paused after this word.
  bool pause;

  /// Punctuation said aloud ("comma") or a line break.
  final bool punct;

  String get lower => w.toLowerCase();
}

final _devanagari = RegExp(r'[ऀ-ॿ]');
final _digits = RegExp(r'^\d+$');
final _terminal = {'.', '?', '!', '।'};

/// Runs the local pass. [pauses] are indices of words in [raw] after which
/// the speaker paused; [exact] only adds punctuation and capitals.
LocalFix normalizeTranscript(
  String raw, {
  Iterable<String> vocab = const [],
  Set<int> pauses = const {},
  bool exact = false,
  double? confidence,
}) {
  final words = raw.trim().split(RegExp(r'\s+'));
  if (raw.trim().isEmpty) return const LocalFix('');
  var toks = <_Tok>[
    for (var i = 0; i < words.length; i++)
      _Tok(words[i], pause: pauses.contains(i)),
  ];
  toks = _spokenPunctuation(toks);
  final hinglish = _isHinglish(toks);
  if (!exact) {
    toks = _dropFillers(toks);
    toks = _collapseStutters(toks);
    toks = _replacePhrases(toks, Lexicon.phrases);
    if (hinglish) _hinglishSpelling(toks);
    toks = _numbers(toks, hinglish: hinglish);
    toks = _vocab(toks, vocab);
  }
  final text = _assemble(toks, hinglish: hinglish);
  final count = toks.where((t) => !t.punct).length;
  final asr = confidence ?? 0;
  return LocalFix(
    text,
    edits: exact ? 0 : diffWords(raw, text).edits,
    confident:
        asr >= VoiceFixConfig.confidentAsr &&
        count <= VoiceFixConfig.confidentMaxWords,
    hinglish: hinglish,
  );
}

int _maxWords(Iterable<String> keys) =>
    keys.fold(1, (n, k) => k.split(' ').length > n ? k.split(' ').length : n);

/// Replaces word runs found in [table] (lowercase keys). [when] can veto a match.
List<_Tok> _replacePhrases(
  List<_Tok> toks,
  Map<String, String> table, {
  bool Function(List<_Tok> toks, int start, int len)? when,
  bool punct = false,
}) {
  final longest = _maxWords(table.keys);
  final out = <_Tok>[];
  var i = 0;
  outer:
  while (i < toks.length) {
    for (var len = longest; len >= 1; len--) {
      if (i + len > toks.length) continue;
      final run = toks.sublist(i, i + len);
      if (run.any((t) => t.punct)) continue;
      final key = run.map((t) => t.lower).join(' ');
      final to = table[key];
      if (to == null) continue;
      if (when != null && !when(toks, i, len)) continue;
      out.add(_Tok(to, pause: run.last.pause, punct: punct));
      i += len;
      continue outer;
    }
    out.add(toks[i++]);
  }
  return out;
}

List<_Tok> _spokenPunctuation(List<_Tok> toks) {
  final said = _replacePhrases(toks, Lexicon.spokenPunctuation, punct: true);
  // "period" only as the very last word.
  if (said.isNotEmpty && !said.last.punct) {
    final mark = Lexicon.finalOnlyPunctuation[said.last.lower];
    if (mark != null && said.length > 1) {
      said[said.length - 1] = _Tok(mark, punct: true);
    }
  }
  return said;
}

bool _isHinglish(List<_Tok> toks) =>
    toks.any((t) => Lexicon.hinglishMarkers.contains(t.lower));

bool _sentenceStart(List<_Tok> toks, int i) =>
    i == 0 || toks[i - 1].pause || (toks[i - 1].punct && toks[i - 1].w != ',');

List<_Tok> _dropFillers(List<_Tok> toks) {
  final out = <_Tok>[];
  for (var i = 0; i < toks.length; i++) {
    final t = toks[i];
    final next = i + 1 < toks.length ? toks[i + 1] : null;
    final prev = out.isEmpty ? null : out.last;
    var drop = false;
    if (!t.punct) {
      final w = t.lower;
      if (Lexicon.fillers.contains(w)) {
        drop = true;
      } else if (w == 'matlab' &&
          _sentenceStart(toks, i) &&
          next != null &&
          !next.punct &&
          !Lexicon.matlabKeepBefore.contains(next.lower)) {
        drop = true;
      } else if (w == 'like' &&
          prev != null &&
          next != null &&
          Lexicon.likeFillerAfter.contains(prev.lower) &&
          Lexicon.likeFillerBefore.contains(next.lower)) {
        drop = true;
      }
    }
    if (drop) {
      if (t.pause && prev != null) prev.pause = true;
      continue;
    }
    out.add(t);
  }
  return out;
}

List<_Tok> _collapseStutters(List<_Tok> toks) {
  final out = <_Tok>[];
  for (final t in toks) {
    final prev = out.isEmpty ? null : out.last;
    if (prev != null &&
        !t.punct &&
        !prev.punct &&
        t.lower == prev.lower &&
        Lexicon.stutterWords.contains(t.lower)) {
      prev.pause = prev.pause || t.pause;
      continue;
    }
    out.add(t);
  }
  return out;
}

void _hinglishSpelling(List<_Tok> toks) {
  for (final t in toks) {
    if (t.punct) continue;
    final to = Lexicon.hinglish[t.lower];
    if (to == null) continue;
    final upper = t.w.isNotEmpty && t.w[0] != t.w[0].toLowerCase();
    t.w = upper ? to[0].toUpperCase() + to.substring(1) : to;
  }
}

// ---- numbers -------------------------------------------------------------------

/// A cardinal number spelled out (or in digits) starting at [i]: its value
/// and how many tokens it used.
(int, int)? _cardinal(List<_Tok> toks, int i) {
  var total = 0, current = 0, used = 0;
  var any = false;
  String? last; // 'u', 't', 's'
  var j = i;
  while (j < toks.length && !toks[j].punct) {
    final w = toks[j].lower;
    final u = w == 'oh' ? null : Lexicon.units[w];
    final t = Lexicon.tens[w];
    final s = Lexicon.scales[w];
    if (!any && _digits.hasMatch(w) && w.length <= 9) {
      current = int.parse(w);
      last = 'u';
    } else if (u != null) {
      if (last == 'u' || (last == 't' && (u >= 10 || u == 0))) break;
      current += u;
      last = 'u';
    } else if (t != null) {
      if (last == 'u' || last == 't') break;
      if (current % 100 != 0) break;
      current += t;
      last = 't';
    } else if (s != null) {
      if (!any || current == 0) break;
      current *= s;
      if (s >= 1000) {
        total += current;
        current = 0;
      }
      last = 's';
    } else if (w == 'and' &&
        last == 's' &&
        j + 1 < toks.length &&
        (Lexicon.units.containsKey(toks[j + 1].lower) ||
            Lexicon.tens.containsKey(toks[j + 1].lower))) {
      j++;
      continue;
    } else {
      break;
    }
    any = true;
    j++;
    used = j - i;
  }
  if (!any) return null;
  return (total + current, used);
}

/// An ordinal ("fifth", "twenty first", "21st") at [i]: value and length.
(int, int)? _ordinal(List<_Tok> toks, int i) {
  if (i >= toks.length || toks[i].punct) return null;
  final w = toks[i].lower;
  final suffixed = RegExp(r'^(\d{1,2})(st|nd|rd|th)$').firstMatch(w);
  if (suffixed != null) return (int.parse(suffixed.group(1)!), 1);
  final o = Lexicon.ordinals[w];
  if (o != null) return (o, 1);
  final t = Lexicon.tens[w];
  if (t != null && i + 1 < toks.length) {
    final o2 = Lexicon.ordinals[toks[i + 1].lower];
    if (o2 != null && o2 < 10) return (t + o2, 2);
  }
  return null;
}

String _ordinalText(int n) {
  final mod100 = n % 100;
  final suffix = mod100 >= 11 && mod100 <= 13
      ? 'th'
      : switch (n % 10) {
          1 => 'st',
          2 => 'nd',
          3 => 'rd',
          _ => 'th',
        };
  return '$n$suffix';
}

String _grouped(int n) {
  if (n < 10000) return '$n';
  final s = '$n';
  final buf = StringBuffer();
  for (var k = 0; k < s.length; k++) {
    if (k > 0 && (s.length - k) % 3 == 0) buf.write(',');
    buf.write(s[k]);
  }
  return buf.toString();
}

/// "pm", "p.m.", "p m" at [i]: the marker and its length.
(String, int)? _meridiem(List<_Tok> toks, int i) {
  if (i >= toks.length || toks[i].punct) return null;
  final w = toks[i].lower.replaceAll('.', '');
  if (w == 'am' || w == 'pm') return (w.toUpperCase(), 1);
  if ((w == 'a' || w == 'p') &&
      i + 1 < toks.length &&
      toks[i + 1].lower.replaceAll('.', '') == 'm') {
    return ('${w.toUpperCase()}M', 2);
  }
  return null;
}

/// Minutes after an hour: "thirty", "oh five", "15".
(int, int)? _minutes(List<_Tok> toks, int i) {
  if (i >= toks.length || toks[i].punct) return null;
  final w = toks[i].lower;
  if (w == 'oh' && i + 1 < toks.length) {
    final u = Lexicon.units[toks[i + 1].lower];
    if (u != null && u > 0 && u < 10) return (u, 2);
    return null;
  }
  final c = _cardinal(toks, i);
  if (c != null && c.$1 >= 10 && c.$1 < 60) return c;
  return null;
}

List<_Tok> _numbers(List<_Tok> toks, {required bool hinglish}) {
  final out = <_Tok>[];
  var i = 0;
  while (i < toks.length) {
    final t = toks[i];
    if (t.punct) {
      out.add(toks[i++]);
      continue;
    }
    final w = t.lower;

    // Dates: "January fifth", "the fifth of January".
    final month = Lexicon.months[w];
    if (month != null) {
      // "may" and "march" are verbs too: only a spoken ordinal makes them dates.
      final verb = w == 'may' || w == 'march';
      final o = _ordinal(toks, i + 1) ?? (verb ? null : _cardinal(toks, i + 1));
      if (o != null && o.$1 >= 1 && o.$1 <= 31) {
        final end = i + o.$2;
        out.add(_Tok('$month ${o.$1}', pause: toks[end].pause));
        i = end + 1;
        continue;
      }
    }
    final ord = _ordinal(toks, i);
    if (ord != null) {
      final ofAt = i + ord.$2;
      final mon = ofAt + 1 < toks.length && toks[ofAt].lower == 'of'
          ? Lexicon.months[toks[ofAt + 1].lower]
          : null;
      if (mon != null && ord.$1 <= 31) {
        out.add(_Tok('${ord.$1} $mon', pause: toks[ofAt + 1].pause));
        i = ofAt + 2;
        continue;
      }
      if (ord.$1 >= 10 && !RegExp(r'^\d').hasMatch(w)) {
        out.add(_Tok(_ordinalText(ord.$1), pause: toks[i + ord.$2 - 1].pause));
        i += ord.$2;
        continue;
      }
    }

    // Romanized Hindi numbers before a unit: "do baje" -> "2 baje".
    if (hinglish) {
      final h = Lexicon.hindiNumbers[w];
      if (h != null &&
          i + 1 < toks.length &&
          Lexicon.hindiUnits.contains(toks[i + 1].lower)) {
        out.add(_Tok('$h', pause: t.pause));
        i++;
        continue;
      }
    }

    final c = _cardinal(toks, i);
    if (c == null) {
      out.add(toks[i++]);
      continue;
    }
    final (v, len) = c;
    final after = i + len;
    final lastTok = toks[after - 1];
    final next = after < toks.length && !toks[after].punct
        ? toks[after].lower
        : null;

    // Times: "five thirty pm", "ten am", "7 o'clock".
    if (v >= 1 && v <= 12 && !lastTok.pause) {
      final m = _minutes(toks, after);
      final mer = _meridiem(toks, after + (m?.$2 ?? 0));
      if (mer != null) {
        final mm = m == null ? '' : ':${m.$1.toString().padLeft(2, '0')}';
        final end = after + (m?.$2 ?? 0) + mer.$2;
        out.add(_Tok('$v$mm ${mer.$1}', pause: toks[end - 1].pause));
        i = end;
        continue;
      }
      final prev = i > 0 ? toks[i - 1].lower : '';
      if (m != null && (prev == 'at' || prev == 'by')) {
        final end = after + m.$2;
        final mm = m.$1.toString().padLeft(2, '0');
        out.add(_Tok('$v:$mm', pause: toks[end - 1].pause));
        i = end;
        continue;
      }
      if (next == "o'clock" || next == 'oclock') {
        out.add(_Tok("$v o'clock", pause: toks[after].pause));
        i = after + 1;
        continue;
      }
    }
    // Money and percentages.
    final cur = next == null ? null : Lexicon.currencies[next];
    if (cur != null && !lastTok.pause) {
      out.add(_Tok('$cur${_grouped(v)}', pause: toks[after].pause));
      i = after + 1;
      continue;
    }
    if (next == 'percent' && !lastTok.pause) {
      out.add(_Tok('${_grouped(v)}%', pause: toks[after].pause));
      i = after + 1;
      continue;
    }
    final spelled = !_digits.hasMatch(w);
    final quantity = next != null && Lexicon.quantityUnits.contains(next);
    if (spelled &&
        (v >= 10 || quantity) &&
        !(v < 10 && len == 1 && !quantity)) {
      out.add(_Tok(_grouped(v), pause: lastTok.pause));
    } else {
      out.addAll(toks.sublist(i, after));
    }
    i = after;
  }
  return out;
}

// ---- the user's names ------------------------------------------------------------

final _parts = RegExp(r'[-_\s.]+|(?<=[a-z])(?=[A-Z])');
const _repoCues = {'repo', 'repository', 'project', 'branch'};

int _distance(String a, String b) {
  if ((a.length - b.length).abs() > 1) return 2;
  var prev = List<int>.generate(b.length + 1, (k) => k);
  for (var x = 1; x <= a.length; x++) {
    final cur = List<int>.filled(b.length + 1, 0)..[0] = x;
    for (var y = 1; y <= b.length; y++) {
      final cost = a[x - 1] == b[y - 1] ? 0 : 1;
      cur[y] = [
        prev[y] + 1,
        cur[y - 1] + 1,
        prev[y - 1] + cost,
      ].reduce((p, q) => p < q ? p : q);
    }
    prev = cur;
  }
  return prev[b.length];
}

List<_Tok> _vocab(List<_Tok> toks, Iterable<String> vocab) {
  final single = <String, String>{};
  final multi = <String, String>{};
  for (final term in vocab) {
    final t = term.trim();
    if (t.length < 2) continue;
    final parts = t
        .split(_parts)
        .where((p) => p.isNotEmpty)
        .map((p) => p.toLowerCase())
        .toList();
    if (parts.length == 1) {
      single[parts.first] = t;
    } else {
      multi[parts.join(' ')] = t;
    }
  }
  if (single.isEmpty && multi.isEmpty) return toks;
  var out = toks;
  if (multi.isNotEmpty) {
    // "the agent worker repo" -> "the Agent-worker repo"; prose stays prose.
    out = _replacePhrases(
      out,
      multi,
      when: (all, start, len) {
        final before = start > 0 ? all[start - 1].lower : '';
        final after = start + len < all.length ? all[start + len].lower : '';
        return _repoCues.contains(before) || _repoCues.contains(after);
      },
    );
  }
  for (final t in out) {
    if (t.punct) continue;
    final w = t.lower;
    final exact = single[w];
    if (exact != null) {
      t.w = exact;
      continue;
    }
    if (w.length < 5) continue;
    for (final e in single.entries) {
      final name = e.value;
      // Only names (capitalized) are matched loosely: "nikil" -> "Nikhil".
      if (name.length < 5 || name[0] == name[0].toLowerCase()) continue;
      if (e.key[0] != w[0] || _distance(e.key, w) > 1) continue;
      t.w = name;
      break;
    }
  }
  return out;
}

// ---- sentences ---------------------------------------------------------------------

bool _isQuestion(List<String> words, {required bool hinglish}) {
  if (words.isEmpty) return false;
  final first = words.first;
  if (Lexicon.questionStarts.contains(first)) {
    // "Do the dishes" / "Don't forget" are orders; "Do you" / "Is the" ask.
    final second = words.length > 1 ? words[1] : '';
    if (Lexicon.doWords.contains(first)) {
      return Lexicon.pronouns.contains(second);
    }
    if (Lexicon.auxiliaries.contains(first)) {
      return Lexicon.pronouns.contains(second) ||
          Lexicon.determiners.contains(second);
    }
    return true;
  }
  return words.any(
    (w) =>
        Lexicon.questionAnywhere.contains(w) &&
        (hinglish || _devanagari.hasMatch(w)),
  );
}

bool _capitalizable(String w) =>
    w.isNotEmpty &&
    w[0] != w[0].toUpperCase() &&
    !w.substring(1).contains(RegExp(r'[A-Z]'));

String _assemble(List<_Tok> toks, {required bool hinglish}) {
  final hindi =
      toks.where((t) => _devanagari.hasMatch(t.w)).length * 2 > toks.length;
  final out = <String>[];
  var sentence = <String>[];
  var totalWords = 0;

  String terminal() =>
      _isQuestion(sentence, hinglish: hinglish) ? '?' : (hindi ? '।' : '.');

  void addPunct(String mark) {
    if (out.isEmpty && !mark.startsWith('\n')) return;
    if (out.isNotEmpty && out.last.startsWith('\n') && !mark.startsWith('\n')) {
      return;
    }
    // A spoken mark replaces one we inferred ("stop, full stop" -> one ".").
    if (out.isNotEmpty &&
        (out.last == ',' || _terminal.contains(out.last)) &&
        !mark.startsWith('\n')) {
      out.removeLast();
    }
    out.add(mark);
    if (_terminal.contains(mark) || mark.startsWith('\n')) sentence = [];
  }

  for (var i = 0; i < toks.length; i++) {
    final t = toks[i];
    if (t.punct) {
      // A spoken "?" or "." after a question keeps the user's choice.
      if (t.w == '.' && _isQuestion(sentence, hinglish: hinglish)) {
        addPunct('?');
      } else {
        addPunct(t.w);
      }
      continue;
    }
    out.add(t.w);
    sentence.add(t.lower);
    totalWords++;
    final next = i + 1 < toks.length ? toks[i + 1] : null;
    if (!t.pause || next == null || next.punct) continue;
    if (Lexicon.noBreakAfter.contains(t.lower)) continue;
    if (Lexicon.continuers.contains(next.lower) ||
        sentence.length < VoiceFixConfig.minSentenceWords) {
      addPunct(',');
    } else {
      addPunct(terminal());
    }
  }
  if (out.isNotEmpty && out.last == ',') out.removeLast();
  if (out.isNotEmpty &&
      !out.last.startsWith('\n') &&
      !_terminal.contains(out.last) &&
      sentence.isNotEmpty) {
    // A short command stays bare ("open settings"); a short question gets its "?".
    final multiSentence = out.any(_terminal.contains);
    if (totalWords >= VoiceFixConfig.minSentenceWords || multiSentence) {
      out.add(terminal());
    } else if (_isQuestion(sentence, hinglish: hinglish)) {
      out.add('?');
    }
  }

  // Join, then capitalize sentence starts and "i".
  final buf = StringBuffer();
  var capNext = true;
  for (final piece in out) {
    if (piece.startsWith('\n')) {
      buf.write(piece);
      capNext = true;
      continue;
    }
    if (piece == ',' ||
        _terminal.contains(piece) ||
        piece == ':' ||
        piece == ';') {
      buf.write(piece);
      if (_terminal.contains(piece)) capNext = true;
      continue;
    }
    if (buf.isNotEmpty && !buf.toString().endsWith('\n')) buf.write(' ');
    var w = piece;
    final lw = w.toLowerCase();
    if (lw == 'i' || lw.startsWith("i'")) {
      w = 'I${w.substring(1)}';
    } else if (Lexicon.weekdays.containsKey(lw)) {
      w = Lexicon.weekdays[lw]!;
    } else if (Lexicon.months.containsKey(lw) && lw != 'may' && lw != 'march') {
      w = Lexicon.months[lw]!;
    }
    if (capNext && _capitalizable(w)) w = w[0].toUpperCase() + w.substring(1);
    capNext = false;
    buf.write(w);
  }
  return buf.toString();
}
