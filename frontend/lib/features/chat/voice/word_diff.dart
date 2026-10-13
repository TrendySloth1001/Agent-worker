import 'package:flutter/painting.dart' show TextRange;

/// What changed between a heard and a fixed transcript, word by word.
/// Case and punctuation are not word changes ("hello" -> "Hello," is not).
class WordDiff {
  const WordDiff(this.changed, this.edits);

  /// Ranges in the fixed text that are new or replaced words.
  final List<TextRange> changed;

  /// Replaced, inserted or removed runs of words.
  final int edits;

  static const none = WordDiff([], 0);
}

final _space = RegExp(r'\S+');
final _notWord = RegExp(r"[^\p{L}\p{N}\p{M}']", unicode: true);

String _key(String w) => w.toLowerCase().replaceAll(_notWord, '');

/// Longest common subsequence of word keys; the rest is what changed.
WordDiff diffWords(String from, String to) {
  if (from == to) return WordDiff.none;
  final a = [for (final m in _space.allMatches(from)) _key(m.group(0)!)];
  final bm = _space.allMatches(to).toList();
  final b = [for (final m in bm) _key(m.group(0)!)];
  final n = a.length, m = b.length;
  if (n * m > 200000) {
    return WordDiff([TextRange(start: 0, end: to.length)], 1);
  }
  final dp = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      dp[i][j] = a[i] == b[j]
          ? dp[i + 1][j + 1] + 1
          : (dp[i + 1][j] >= dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1]);
    }
  }
  final changed = <TextRange>[];
  var edits = 0;
  var i = 0, j = 0;
  var removed = <String>[];
  var added = <int>[];
  void flush() {
    if (removed.isEmpty && added.isEmpty) return;
    final addedKey = added.map((k) => b[k]).where((k) => k.isNotEmpty).join();
    final removedKey = removed.where((k) => k.isNotEmpty).join();
    // "in put" -> "input" is a change; an emptied punctuation token is not.
    final same = addedKey == removedKey && added.length == removed.length;
    if (!same && (addedKey.isNotEmpty || removedKey.isNotEmpty)) {
      edits++;
      for (final k in added) {
        if (b[k].isEmpty) continue;
        changed.add(TextRange(start: bm[k].start, end: bm[k].end));
      }
    }
    removed = [];
    added = [];
  }

  while (i < n || j < m) {
    if (i < n && j < m && a[i] == b[j]) {
      flush();
      i++;
      j++;
    } else if (j < m && (i >= n || dp[i][j + 1] >= dp[i + 1][j])) {
      added.add(j++);
    } else {
      removed.add(a[i++]);
    }
  }
  flush();
  return WordDiff(_merge(changed, to), edits);
}

/// Joins ranges separated only by a space, so a phrase highlights as one.
List<TextRange> _merge(List<TextRange> ranges, String text) {
  final out = <TextRange>[];
  for (final r in ranges) {
    if (out.isNotEmpty &&
        text.substring(out.last.end, r.start).trim().isEmpty) {
      out[out.length - 1] = TextRange(start: out.last.start, end: r.end);
    } else {
      out.add(r);
    }
  }
  return out;
}
