import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../core/constants/suggest.dart';
import '../../../data/chat_api.dart';
import '../../../data/suggest_api.dart';
import 'local_words.dart';

/// Ghost-text completion and next-word chips for the composer.
///
/// Local words show instantly; the server answer replaces them when it
/// arrives. Requests are debounced, the previous one is cancelled, answers
/// are cached, and the server is left alone for a while after a 429.
class AutocompleteController extends ChangeNotifier {
  AutocompleteController({
    required this.fetch,
    required this.local,
    this.conversationId,
    this.enabled = true,
    this.debounce = SuggestConfig.debounce,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final CompleteCall Function(String text, String? conversationId) fetch;
  final LocalWords local;
  final Duration debounce;
  final DateTime Function() _now;

  String? conversationId;
  bool enabled;

  String _text = '';
  String _ghost = '';
  List<String> _words = const [];
  Timer? _timer;
  CompleteCall? _call;
  int _generation = 0;
  DateTime? _blockedUntil;
  bool _disposed = false;
  final _cache = <String, Completion>{};

  /// Rest of the current sentence, shown after the cursor.
  String get ghost => _ghost;

  /// Next-word chips (replace the half-typed word when there is one).
  List<String> get words => _words;

  /// The text the current suggestions were made for.
  String get text => _text;

  /// The ghost text, only while the field still holds the text it was made for.
  String ghostFor(String fieldText) => fieldText == _text ? _ghost : '';

  bool get hasAnything => _ghost.isNotEmpty || _words.isNotEmpty;

  static bool endsOpen(String text) =>
      text.isNotEmpty && !RegExp(r'\s$').hasMatch(text);

  /// True when the last word of [text] is (the start of) a link.
  static bool endsInUrl(String text) {
    final last = text.split(RegExp(r'\s')).last;
    return RegExp(
      r'^(https?://|www\.)\S*$',
      caseSensitive: false,
    ).hasMatch(last);
  }

  static bool shouldSkip(String text) =>
      text.trim().length < SuggestConfig.minChars || endsInUrl(text);

  String _key(String text) {
    final tail = text.length > SuggestConfig.contextChars
        ? text.substring(text.length - SuggestConfig.contextChars)
        : text;
    return '${conversationId ?? ''}|$tail';
  }

  /// Call with the field's text on every change.
  void update(String text) {
    if (text == _text) return;
    final prev = _text;
    _text = text;
    _timer?.cancel();
    _cancelCall();
    if (!enabled || shouldSkip(text)) {
      _set('', const []);
      return;
    }
    // Typing the ghost text itself keeps the rest of it.
    var keep = '';
    if (_ghost.isNotEmpty &&
        text.length > prev.length &&
        text.startsWith(prev)) {
      final typed = text.substring(prev.length);
      if (_ghost.startsWith(typed)) keep = _ghost.substring(typed.length);
    }
    final cached = _cache[_key(text)];
    if (cached != null) {
      _apply(text, cached);
      return;
    }
    _set(keep, _merge(text, const []));
    if (keep.isNotEmpty) return;
    final blocked = _blockedUntil;
    if (blocked != null && _now().isBefore(blocked)) return;
    _timer = Timer(debounce, () => _request(text));
  }

  void _request(String text) {
    if (_disposed || text != _text) return;
    final generation = ++_generation;
    final call = fetch(text, conversationId);
    _call = call;
    call.result.then(
      (result) {
        if (_disposed || generation != _generation || text != _text) return;
        _call = null;
        _cache[_key(text)] = result;
        while (_cache.length > SuggestConfig.cacheSize) {
          _cache.remove(_cache.keys.first);
        }
        _apply(text, result);
      },
      onError: (Object e) {
        if (generation != _generation) return;
        _call = null;
        if (e is ApiException && e.status == 429) {
          _blockedUntil = _now().add(SuggestConfig.backoff);
        }
      },
    );
  }

  void _apply(String text, Completion result) {
    _set(result.completion, _merge(text, result.nextWords));
  }

  /// Server words that fit the text, then local ones, up to the chip limit.
  List<String> _merge(String text, List<String> server) {
    final open = endsOpen(text);
    final partial = open ? text.split(RegExp(r'\s')).last.toLowerCase() : '';
    final out = <String>[];
    void add(String w) {
      if (out.length >= SuggestConfig.maxWords) return;
      if (open && !w.toLowerCase().startsWith(partial)) return;
      if (open && w.toLowerCase() == partial) return;
      if (!out.any((o) => o.toLowerCase() == w.toLowerCase())) out.add(w);
    }

    server.forEach(add);
    local.suggest(text).forEach(add);
    return out;
  }

  void _set(String ghost, List<String> words) {
    if (ghost == _ghost && _sameWords(words)) return;
    _ghost = ghost;
    _words = words;
    if (!_disposed) notifyListeners();
  }

  bool _sameWords(List<String> other) =>
      other.length == _words.length &&
      [
        for (var i = 0; i < other.length; i++) other[i] == _words[i],
      ].every((b) => b);

  void _cancelCall() {
    _generation++;
    _call?.cancel();
    _call = null;
  }

  /// Appends the ghost text to [field]. Returns false when there is none.
  bool accept(TextEditingController field) {
    if (_ghost.isEmpty || field.text != _text) return false;
    final text = field.text + _ghost;
    field.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    return true;
  }

  /// Puts [word] into [field]: replaces a half-typed word, else appends.
  void insertWord(TextEditingController field, String word) {
    final text = field.text;
    final base = endsOpen(text)
        ? text.substring(0, text.length - text.split(RegExp(r'\s')).last.length)
        : text;
    final next = '$base$word ';
    field.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  /// Forgets the current text (after sending).
  void reset() {
    _timer?.cancel();
    _cancelCall();
    _text = '';
    _set('', const []);
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _cancelCall();
    super.dispose();
  }
}
