import 'dart:convert';

import '../../../core/constants/suggest.dart';

/// Word frequencies from the user's own messages: the instant, offline
/// source of next-word chips while the server is slow or unreachable.
class LocalWords {
  LocalWords([String? stored]) {
    if (stored == null) return;
    try {
      final json = jsonDecode(stored);
      if (json is! Map<String, dynamic>) return;
      _fromJson(json['u'], _words);
      final pairs = json['b'];
      if (pairs is Map<String, dynamic>) {
        pairs.forEach((k, v) {
          final into = _after.putIfAbsent(k, () => {});
          _fromJson(v, into);
        });
      }
    } catch (_) {}
  }

  final Map<String, int> _words = {};
  final Map<String, Map<String, int>> _after = {};

  static void _fromJson(Object? raw, Map<String, int> into) {
    if (raw is! Map) return;
    raw.forEach((k, v) {
      if (k is String && v is int) into[k] = v;
    });
  }

  static final _split = RegExp(r"[^\p{L}\p{N}'’-]+", unicode: true);

  static List<String> tokens(String text) => [
    for (final w in text.toLowerCase().split(_split))
      if (w.length >= SuggestConfig.memoryMinWordLength &&
          !w.startsWith('http'))
        w,
  ];

  bool get isEmpty => _words.isEmpty;

  /// Counts the words of a message the user sent.
  void learn(String text) {
    for (final sentence in text.split(RegExp(r'[.!?\n]+'))) {
      final list = tokens(sentence);
      for (var i = 0; i < list.length; i++) {
        _words.update(list[i], (n) => n + 1, ifAbsent: () => 1);
        if (i > 0) {
          _after
              .putIfAbsent(list[i - 1], () => {})
              .update(list[i], (n) => n + 1, ifAbsent: () => 1);
        }
      }
    }
    _trim();
  }

  void _trim() {
    if (_words.length <= SuggestConfig.memoryMaxWords * 1.5) return;
    final keep = _top(_words, SuggestConfig.memoryMaxWords).toSet();
    _words.removeWhere((k, _) => !keep.contains(k));
    _after.removeWhere((k, _) => !keep.contains(k));
    for (final m in _after.values) {
      m.removeWhere((k, _) => !keep.contains(k));
    }
  }

  static List<String> _top(Map<String, int> counts, int n) {
    final entries = counts.entries.toList()
      ..sort((a, b) {
        final c = b.value.compareTo(a.value);
        return c != 0 ? c : a.key.compareTo(b.key);
      });
    return [for (final e in entries.take(n)) e.key];
  }

  /// Likely next words for [text]: after a finished word, what usually
  /// follows it; while a word is half typed, the words that start with it.
  List<String> suggest(String text, {int max = SuggestConfig.maxWords}) {
    if (_words.isEmpty || text.trim().isEmpty) return const [];
    final endsOpen = !RegExp(r'\s$').hasMatch(text);
    final list = tokens(text);
    if (list.isEmpty && !endsOpen) return const [];
    if (endsOpen) {
      if (list.isEmpty) return const [];
      final partial = list.last;
      final matches = <String, int>{
        for (final e in _words.entries)
          if (e.key.startsWith(partial) && e.key != partial) e.key: e.value,
      };
      return _top(matches, max);
    }
    final follows = _after[list.last];
    if (follows == null || follows.isEmpty) return const [];
    return _top(follows, max);
  }

  String toStorage() {
    final keep = _top(_words, SuggestConfig.memoryMaxWords).toSet();
    return jsonEncode({
      'u': {for (final k in keep) k: _words[k]},
      'b': {
        for (final e in _after.entries)
          if (keep.contains(e.key))
            e.key: {
              for (final f in e.value.entries)
                if (keep.contains(f.key)) f.key: f.value,
            },
      },
    });
  }
}
