import 'dart:async';

import 'package:flutter/painting.dart' show TextRange;

import '../../../core/constants/voice_fix.dart';
import '../../../data/transcript_fix_api.dart';
import 'transcript_normalizer.dart';
import 'word_diff.dart';

/// A dictated segment after correction, with what changed against what the
/// recognizer heard (for the highlight and "Undo fix").
class VoiceFix {
  const VoiceFix({
    required this.raw,
    required this.text,
    this.changed = const [],
    this.edits = 0,
    this.source = 'local',
  });

  /// What the recognizer heard.
  final String raw;
  final String text;

  /// Corrected words, as ranges in [text].
  final List<TextRange> changed;
  final int edits;

  /// 'local' (on-device only) or 'llm'.
  final String source;

  bool get hasEdits => edits > 0;
}

/// Two passes over each finished segment: the instant on-device one, then
/// the fast model on the server within [timeout]; any failure keeps the
/// local text. Reads its settings on every call so changes apply at once.
class TranscriptFixer {
  TranscriptFixer({
    TranscriptFixApi? api,
    required this.enabled,
    required this.exact,
    this.context,
    this.timeout = VoiceFixConfig.llmTimeout,
  }) : _api = api ?? TranscriptFixApi();

  final TranscriptFixApi _api;
  final bool Function() enabled;
  final bool Function() exact;

  /// The conversation so far; only the last two messages are sent.
  final List<VoiceTurn> Function()? context;
  final Duration timeout;

  List<String> _vocab = const [];
  DateTime? _vocabAt;
  Future<void>? _loading;
  final _localMs = <double>[];

  List<String> get vocab => _vocab;

  /// Fetches the user's names and repositories in the background.
  void warm() {
    final at = _vocabAt;
    if (_loading != null ||
        (at != null &&
            DateTime.now().difference(at) < VoiceFixConfig.vocabTtl)) {
      return;
    }
    _loading = _api
        .vocab()
        .then((words) {
          _vocab = words;
          _vocabAt = DateTime.now();
        })
        .whenComplete(() => _loading = null);
  }

  /// The on-device pass; its timing is reported with the next model request.
  LocalFix local(String raw, {Set<int> pauses = const {}, double? confidence}) {
    final watch = Stopwatch()..start();
    final out = normalizeTranscript(
      raw,
      vocab: _vocab,
      pauses: pauses,
      exact: exact(),
      confidence: confidence,
    );
    _localMs.add(watch.elapsedMicroseconds / 1000);
    if (_localMs.length > VoiceFixConfig.maxLocalSamples) _localMs.removeAt(0);
    return out;
  }

  /// The model pass over [local] (skipped for short commands and confident
  /// results). Never throws; never takes much longer than [timeout].
  Future<VoiceFix> refine(
    String raw,
    LocalFix local, {
    String? language,
  }) async {
    final words = local.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    if (words.length < VoiceFixConfig.minLlmWords || local.confident) {
      return result(raw, local.text);
    }
    final samples = [for (final ms in _localMs) (ms * 100).round() / 100];
    _localMs.clear();
    final server = await _api.fix(
      text: local.text,
      context: _recent(),
      language: language,
      exact: exact(),
      vocab: _vocab,
      localMs: samples,
      timeout: timeout,
    );
    if (server == null || !server.applied) return result(raw, local.text);
    return result(raw, server.text, source: 'llm');
  }

  static VoiceFix result(String raw, String text, {String source = 'local'}) {
    final d = diffWords(raw, text);
    return VoiceFix(
      raw: raw,
      text: text,
      changed: d.changed,
      edits: d.edits,
      source: source,
    );
  }

  List<VoiceTurn> _recent() {
    final all = context?.call() ?? const <VoiceTurn>[];
    final start = all.length > VoiceFixConfig.contextTurns
        ? all.length - VoiceFixConfig.contextTurns
        : 0;
    return [
      for (final t in all.sublist(start))
        if (t.content.trim().isNotEmpty)
          (
            role: t.role,
            content: t.content.length > VoiceFixConfig.contextChars
                ? t.content.substring(0, VoiceFixConfig.contextChars)
                : t.content,
          ),
    ];
  }
}
