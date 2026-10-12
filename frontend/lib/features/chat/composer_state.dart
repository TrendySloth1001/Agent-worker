import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/docs.dart';
import '../../core/constants/smart_toggles.dart';

/// The composer's toggles for one conversation: WEB mode, KB, DOC and its
/// length, and the suggestions already offered (so they are not repeated).
class ComposerState {
  const ComposerState({
    required this.web,
    required this.knowledge,
    this.doc = false,
    this.docLength = DocConfig.defaultLength,
    this.suppressed = const {},
  });

  final WebMode web;
  final bool knowledge;
  final bool doc;
  final String docLength;
  final Set<SuggestKind> suppressed;

  Map<String, dynamic> toJson() => {
    'web': web.wire,
    'kb': knowledge,
    'doc': doc,
    'docLength': docLength,
    'suppressed': [for (final k in suppressed) k.name],
  };

  factory ComposerState.fromJson(Map<String, dynamic> j) => ComposerState(
    web: WebMode.fromWire(j['web']),
    knowledge: j['kb'] == true,
    doc: j['doc'] == true,
    docLength: DocStrings.lengths.any((l) => l.$1 == j['docLength'])
        ? j['docLength'] as String
        : DocConfig.defaultLength,
    suppressed: {
      for (final k in j['suppressed'] as List? ?? const [])
        ?SuggestKind.fromWire(k),
    },
  );

  @override
  bool operator ==(Object other) =>
      other is ComposerState &&
      jsonEncode(toJson()) == jsonEncode(other.toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

/// Remembers [ComposerState] per saved conversation on this device (one
/// prefs entry, oldest chats dropped past [SmartConfig.maxRemembered]).
class ComposerStore {
  ComposerStore([Future<SharedPreferences>? prefs])
    : _prefs = prefs ?? SharedPreferences.getInstance();

  final Future<SharedPreferences> _prefs;

  Future<Map<String, dynamic>> _all() async {
    try {
      final raw = (await _prefs).getString(SmartConfig.composerPrefsKey);
      final decoded = raw == null ? null : jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : {};
    } catch (_) {
      return {};
    }
  }

  Future<ComposerState?> read(String conversationId) async {
    final entry = (await _all())[conversationId];
    return entry is Map<String, dynamic> ? ComposerState.fromJson(entry) : null;
  }

  Future<void> write(String conversationId, ComposerState state) async {
    try {
      final all = await _all();
      all
        ..remove(conversationId)
        ..[conversationId] = state.toJson();
      while (all.length > SmartConfig.maxRemembered) {
        all.remove(all.keys.first);
      }
      await (await _prefs).setString(
        SmartConfig.composerPrefsKey,
        jsonEncode(all),
      );
    } catch (_) {
      // Toggles simply fall back to the defaults next time.
    }
  }
}
