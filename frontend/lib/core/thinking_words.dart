import 'dart:math';

import 'constants/thinking_words.dart';

/// Builds short playful "thinking" lines from small banks, loosely related
/// to what the user asked. Deterministic for a given seed.
abstract final class ThinkingWords {
  /// Lines already shown this session, so replies do not repeat them.
  static final Set<String> sessionUsed = {};

  /// A stable 32-bit hash (FNV-1a), so a seed never changes between runs.
  static int seedOf(String text) {
    var h = 0x811c9dc5;
    for (final unit in text.codeUnits) {
      h = ((h ^ unit) * 0x01000193) & 0xffffffff;
    }
    return h;
  }

  /// The topic of [prompt]: the one with the most keyword hits, else general.
  static String topicOf(String? prompt) {
    final words = [
      for (final m in RegExp(
        r'[a-z]+',
      ).allMatches((prompt ?? '').toLowerCase()))
        m.group(0)!,
    ];
    var best = ThinkingBank.general;
    var bestScore = 0;
    for (final entry in ThinkingBank.keywords.entries) {
      var score = 0;
      for (final w in words) {
        if (entry.value.any(w.startsWith)) score++;
      }
      if (score > bestScore) {
        best = entry.key;
        bestScore = score;
      }
    }
    return best;
  }

  static bool _topical(String line, String topic) =>
      topic != ThinkingBank.general &&
      (ThinkingBank.stems[topic] ?? const <String>[]).any(
        (s) => line.toLowerCase().contains(s.toLowerCase()),
      );

  /// Every line the banks can make for [topic], within the length cap.
  static List<String> pool(String topic) {
    final stems = [
      ...?ThinkingBank.stems[topic],
      if (topic != ThinkingBank.general) ...ThinkingBank.stems['general']!,
    ];
    final objects = [
      ...?ThinkingBank.objects[topic],
      if (topic != ThinkingBank.general) ...ThinkingBank.objects['general']!,
    ];
    final out = <String>{};
    String line(String s) => '$s${ThinkingBank.ellipsis}';
    for (final stem in stems) {
      final verb = '$stem${ThinkingBank.suffix}';
      out.add(line(verb));
      for (final o in objects) {
        out.add(line('$verb $o'));
      }
      for (final a in ThinkingBank.adverbs) {
        out.add(line('$a ${verb.toLowerCase()}'));
      }
    }
    for (final f in ThinkingBank.fixed) {
      out.add(line(f));
    }
    return [
      for (final l in out)
        if (l.length <= ThinkingBank.maxLength) l,
    ];
  }

  /// The next line: on-topic ones first, in a stable shuffle from [seed],
  /// skipping anything already in [used] (default: this session). The chosen
  /// line is added to [used]; when every line was used, it starts over.
  static String next({required int seed, String? prompt, Set<String>? used}) {
    final seen = used ?? sessionUsed;
    final topic = topicOf(prompt);
    final all = pool(topic)..sort();
    all.shuffle(Random(seed));
    final ordered = [
      ...all.where((l) => _topical(l, topic)),
      ...all.where((l) => !_topical(l, topic)),
    ];
    var fresh = [
      for (final l in ordered)
        if (!seen.contains(l)) l,
    ];
    if (fresh.isEmpty) {
      seen.clear();
      fresh = ordered;
    }
    final line = fresh.first;
    seen.add(line);
    return line;
  }
}
