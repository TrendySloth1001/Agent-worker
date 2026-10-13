import 'dart:ui' show PlatformDispatcher;

import '../../../data/chat_message.dart';
import '../../../data/transcript_fix_api.dart';
import '../../settings/settings_controller.dart';
import 'on_device_engine.dart';
import 'server_engine.dart';
import 'transcript_fixer.dart';
import 'voice_controller.dart';
import 'voice_locale.dart';

/// Chat messages as fix context (the fixer sends only the last two).
List<VoiceTurn> voiceTurns(List<ChatMessage> messages) => [
  for (final m in messages)
    if (m.role != Role.context && !m.isError && m.content.trim().isNotEmpty)
      (role: m.role == Role.user ? 'user' : 'assistant', content: m.content),
];

/// The app's dictation: Android's recognizer first, the server as fallback,
/// reading the language and accuracy settings each time it starts. Each
/// finished segment is corrected ("Auto-fix what I say") with [context] —
/// the conversation, of which only the last two messages are sent.
VoiceController createVoiceController(
  SettingsController settings, {
  List<VoiceTurn> Function()? context,
}) {
  return VoiceController(
    onDevice: OnDeviceVoiceEngine(),
    server: ServerVoiceEngine(),
    locale: () => voiceLocaleFor(
      language: settings.language,
      device: PlatformDispatcher.instance.locale.toLanguageTag(),
    ),
    highAccuracy: () => settings.voiceHighAccuracy,
    fixer: TranscriptFixer(
      enabled: () => settings.voiceAutoFix,
      exact: () => settings.voiceExactWords,
      context: context,
    ),
  );
}
