/// Word-level diff for the passage edit preview.
enum DocDiffKind { same, removed, added }

typedef DocDiffPiece = (DocDiffKind kind, String text);

/// Beyond this many words per side the diff is skipped (the preview then
/// shows plain before/after text).
const docDiffMaxWords = 400;

/// Words of [a] and [b] compared with a longest common subsequence;
/// whitespace stays attached to the word before it. Null when either side
/// is too long to diff.
List<DocDiffPiece>? docWordDiff(String a, String b) {
  final x = _words(a);
  final y = _words(b);
  if (x.length > docDiffMaxWords || y.length > docDiffMaxWords) return null;
  final n = x.length;
  final m = y.length;
  // lcs[i][j]: common length of x[i..] and y[j..].
  final lcs = List.generate(n + 1, (_) => List.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      lcs[i][j] = _key(x[i]) == _key(y[j])
          ? lcs[i + 1][j + 1] + 1
          : (lcs[i + 1][j] >= lcs[i][j + 1] ? lcs[i + 1][j] : lcs[i][j + 1]);
    }
  }
  final out = <DocDiffPiece>[];
  void add(DocDiffKind k, String s) {
    if (out.isNotEmpty && out.last.$1 == k) {
      out[out.length - 1] = (k, out.last.$2 + s);
    } else {
      out.add((k, s));
    }
  }

  var i = 0;
  var j = 0;
  while (i < n && j < m) {
    if (_key(x[i]) == _key(y[j])) {
      add(DocDiffKind.same, y[j]);
      i++;
      j++;
    } else if (lcs[i + 1][j] >= lcs[i][j + 1]) {
      add(DocDiffKind.removed, x[i++]);
    } else {
      add(DocDiffKind.added, y[j++]);
    }
  }
  while (i < n) {
    add(DocDiffKind.removed, x[i++]);
  }
  while (j < m) {
    add(DocDiffKind.added, y[j++]);
  }
  return out;
}

final _word = RegExp(r'\S+\s*');

List<String> _words(String s) => [for (final m in _word.allMatches(s)) m[0]!];

String _key(String w) => w.trim();
