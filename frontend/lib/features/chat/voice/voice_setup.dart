import 'dart:ui' show PlatformDispatcher;

import '../../settings/settings_controller.dart';
import 'on_device_engine.dart';
import 'server_engine.dart';
import 'voice_controller.dart';
import 'voice_locale.dart';

/// The app's dictation: Android's recognizer first, the server as fallback,
/// reading the language and accuracy settings each time it starts.
VoiceController createVoiceController(SettingsController settings) {
  return VoiceController(
    onDevice: OnDeviceVoiceEngine(),
    server: ServerVoiceEngine(),
    locale: () => voiceLocaleFor(
      language: settings.language,
      device: PlatformDispatcher.instance.locale.toLanguageTag(),
    ),
    highAccuracy: () => settings.voiceHighAccuracy,
  );
}
