import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_prefs.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/constants/settings_copy.dart';
import '../../core/haptics.dart';
import '../../core/notify/notify_kind.dart';
import '../../core/notify/notify_prefs.dart';

/// Persisted user preferences.
class SettingsController extends ChangeNotifier {
  SettingsController._(this._prefs) {
    themeMode = _readTheme();
    hapticsOn = _prefs?.getBool(AppPrefs.haptics) ?? true;
    defaultWebSearch = _prefs?.getBool(AppPrefs.defaultWebSearch) ?? true;
    smartSuggestions = _prefs?.getBool(AppPrefs.smartSuggestions) ?? true;
    defaultKnowledge = _prefs?.getBool(AppPrefs.defaultKnowledge) ?? false;
    defaultRoundTable = _prefs?.getBool(AppPrefs.defaultRoundTable) ?? false;
    notify = NotifyPrefs(_prefs)..addListener(notifyListeners);
    autocompleteOn = _prefs?.getBool(AppPrefs.autocomplete) ?? true;
    voiceAutoSend = _prefs?.getBool(AppPrefs.voiceAutoSend) ?? false;
    voiceHighAccuracy = _prefs?.getBool(AppPrefs.voiceHighAccuracy) ?? false;
    assistActions = _prefs?.getBool(AppPrefs.assistActions) ?? true;
    assistLive = _prefs?.getBool(AppPrefs.assistLive) ?? true;
    assistSaveHistory = _prefs?.getBool(AppPrefs.assistSaveHistory) ?? true;
    mode = _readMode();
    name = _prefs?.getString(AppPrefs.profileName) ?? '';
    role = _prefs?.getString(AppPrefs.profileRole) ?? '';
    about = _prefs?.getString(AppPrefs.profileAbout) ?? '';
    language = _prefs?.getString(AppPrefs.profileLanguage) ?? '';
    customInstructions = _prefs?.getString(AppPrefs.profileInstructions) ?? '';
    signature = _prefs?.getString(AppPrefs.profileSignature) ?? '';
    final savedTone = _prefs?.getString(AppPrefs.profileTone);
    tone = tones.contains(savedTone) ? savedTone! : '';
    final savedLength = _prefs?.getString(AppPrefs.profileLength);
    length = lengths.contains(savedLength) ? savedLength! : 'detailed';
    final savedScale = _prefs?.getString(AppPrefs.textScale);
    textScale = SettingsSizes.textScales.containsKey(savedScale)
        ? savedScale!
        : 'normal';
    modelChoice = _prefs?.getString(AppPrefs.modelChoice) ?? 'auto';
    modelChoiceName = _prefs?.getString(AppPrefs.modelChoiceName) ?? '';
    browserPackage = _prefs?.getString(AppPrefs.browserPackage) ?? '';
    browserLabel = _prefs?.getString(AppPrefs.browserLabel) ?? '';
    Haptics.enabled = hapticsOn;
  }

  /// Valid values are the ids the backend accepts.
  static const modes = ['default', 'debug', 'review', 'design', 'explain'];

  /// Tone and length ids the backend accepts.
  static const tones = [
    'friendly',
    'professional',
    'casual',
    'direct',
    'enthusiastic',
  ];
  static const lengths = ['concise', 'balanced', 'detailed'];

  /// Falls back to defaults if storage is unavailable.
  static Future<SettingsController> load() async {
    try {
      return SettingsController._(await SharedPreferences.getInstance());
    } catch (_) {
      return SettingsController._(null);
    }
  }

  final SharedPreferences? _prefs;

  late ThemeMode themeMode;
  late bool hapticsOn;
  late bool autocompleteOn;

  /// Voice input: send when dictation ends / always transcribe on the server.
  late bool voiceAutoSend, voiceHighAccuracy;

  /// Assistant: answers may propose phone actions (alarm, event, call...)
  /// shown as cards that run only on Confirm.
  late bool assistActions;

  /// Assistant: the talk button starts Live (spoken answers, keeps listening).
  late bool assistLive;

  /// Assistant overlay chats are saved to the history on their own.
  late bool assistSaveHistory;

  /// New chats start with WEB on Auto (true) or Off (false).
  late bool defaultWebSearch;

  /// Offer the knowledge base and Docs when a message looks like it needs them.
  late bool smartSuggestions;
  late bool defaultKnowledge;
  late bool defaultRoundTable;

  /// Notification choices: master switch, one per kind, quiet hours.
  late final NotifyPrefs notify;

  /// System notification when a round table finishes in the background
  /// (same key as before the notification center).
  bool get notifyRoundTable => notify.isOn(NotifyKind.roundTable);
  late String mode;

  // Personalization. Empty string means not set; [tone] '' means no tone.
  late String name, role, about, language, customInstructions, signature;
  late String tone;
  late String length;

  /// One of [SettingsSizes.textScales]' keys.
  late String textScale;

  /// 'auto', 'fast', 'smart' or a raw model id.
  late String modelChoice;

  /// Friendly name of a specific model pick; empty for the presets.
  String modelChoiceName = '';

  /// Remembered browser for external links. Empty means the system default.
  late String browserPackage, browserLabel;

  ThemeMode _readTheme() {
    final name = _prefs?.getString(AppPrefs.themeMode);
    return ThemeMode.values.where((m) => m.name == name).firstOrNull ??
        ThemeMode.system;
  }

  String _readMode() {
    final saved = _prefs?.getString(AppPrefs.mode);
    return modes.contains(saved) ? saved! : modes.first;
  }

  void setThemeMode(ThemeMode value) {
    themeMode = value;
    _prefs?.setString(AppPrefs.themeMode, value.name);
    notifyListeners();
  }

  void setHaptics(bool value) {
    hapticsOn = value;
    Haptics.enabled = value;
    _prefs?.setBool(AppPrefs.haptics, value);
    notifyListeners();
  }

  void setAutocomplete(bool value) {
    autocompleteOn = value;
    _prefs?.setBool(AppPrefs.autocomplete, value);
    notifyListeners();
  }

  void setVoiceAutoSend(bool value) {
    voiceAutoSend = value;
    _prefs?.setBool(AppPrefs.voiceAutoSend, value);
    notifyListeners();
  }

  void setVoiceHighAccuracy(bool value) {
    voiceHighAccuracy = value;
    _prefs?.setBool(AppPrefs.voiceHighAccuracy, value);
    notifyListeners();
  }

  void setAssistActions(bool value) {
    assistActions = value;
    _prefs?.setBool(AppPrefs.assistActions, value);
    notifyListeners();
  }

  void setAssistSaveHistory(bool value) {
    assistSaveHistory = value;
    _prefs?.setBool(AppPrefs.assistSaveHistory, value);
    notifyListeners();
  }

  void setAssistLive(bool value) {
    assistLive = value;
    _prefs?.setBool(AppPrefs.assistLive, value);
    notifyListeners();
  }

  void setDefaultWebSearch(bool value) {
    defaultWebSearch = value;
    _prefs?.setBool(AppPrefs.defaultWebSearch, value);
    notifyListeners();
  }

  void setSmartSuggestions(bool value) {
    smartSuggestions = value;
    _prefs?.setBool(AppPrefs.smartSuggestions, value);
    notifyListeners();
  }

  void setDefaultKnowledge(bool value) {
    defaultKnowledge = value;
    _prefs?.setBool(AppPrefs.defaultKnowledge, value);
    notifyListeners();
  }

  void setDefaultRoundTable(bool value) {
    defaultRoundTable = value;
    _prefs?.setBool(AppPrefs.defaultRoundTable, value);
    notifyListeners();
  }

  void setNotifyRoundTable(bool value) {
    notify.setKind(NotifyKind.roundTable, value);
  }

  void setMode(String value) {
    if (!modes.contains(value)) return;
    mode = value;
    _prefs?.setString(AppPrefs.mode, value);
    notifyListeners();
  }

  /// Sets a text profile field, trimmed and clamped to [max].
  void _setText(String key, String value, int max, void Function(String) set) {
    final v = value.trim();
    final clamped = v.length > max ? v.substring(0, max) : v;
    set(clamped);
    _prefs?.setString(key, clamped);
    notifyListeners();
  }

  void setName(String v) => _setText(
    AppPrefs.profileName,
    v,
    AppSizes.profileNameMax,
    (x) => name = x,
  );

  void setRole(String v) => _setText(
    AppPrefs.profileRole,
    v,
    AppSizes.profileRoleMax,
    (x) => role = x,
  );

  void setAbout(String v) => _setText(
    AppPrefs.profileAbout,
    v,
    AppSizes.profileAboutMax,
    (x) => about = x,
  );

  void setLanguage(String v) => _setText(
    AppPrefs.profileLanguage,
    v,
    AppSizes.profileLanguageMax,
    (x) => language = x,
  );

  void setCustomInstructions(String v) => _setText(
    AppPrefs.profileInstructions,
    v,
    AppSizes.profileInstructionsMax,
    (x) => customInstructions = x,
  );

  void setSignature(String v) => _setText(
    AppPrefs.profileSignature,
    v,
    AppSizes.profileSignatureMax,
    (x) => signature = x,
  );

  /// Pass '' to clear the tone.
  void setTone(String value) {
    if (value.isNotEmpty && !tones.contains(value)) return;
    tone = value;
    _prefs?.setString(AppPrefs.profileTone, value);
    notifyListeners();
  }

  void setLength(String value) {
    if (!lengths.contains(value)) return;
    length = value;
    _prefs?.setString(AppPrefs.profileLength, value);
    notifyListeners();
  }

  /// Pass '' to go back to the system default.
  void setBrowser(String package, [String label = '']) {
    browserPackage = package;
    browserLabel = package.isEmpty ? '' : label;
    _prefs?.setString(AppPrefs.browserPackage, browserPackage);
    _prefs?.setString(AppPrefs.browserLabel, browserLabel);
    notifyListeners();
  }

  double get textScaleFactor => SettingsSizes.textScales[textScale] ?? 1.0;

  void setTextScale(String id) {
    if (!SettingsSizes.textScales.containsKey(id)) return;
    textScale = id;
    _prefs?.setString(AppPrefs.textScale, id);
    notifyListeners();
  }

  void setModelChoice(String id, {String name = ''}) {
    modelChoice = id.isEmpty ? 'auto' : id;
    modelChoiceName = name;
    _prefs?.setString(AppPrefs.modelChoice, modelChoice);
    _prefs?.setString(AppPrefs.modelChoiceName, name);
    notifyListeners();
  }

  /// The model id to request, or null to let the server pick (Auto).
  String? get modelId => switch (modelChoice) {
    'auto' => null,
    'fast' => SettingsSizes.fastModelId,
    'smart' => SettingsSizes.smartModelId,
    final raw => raw,
  };

  /// Applies a reply-style preset (tone and length together).
  void applyReplyStyle(String tone, String length) {
    this.tone = tone;
    this.length = length;
    _prefs?.setString(AppPrefs.profileTone, tone);
    _prefs?.setString(AppPrefs.profileLength, length);
    notifyListeners();
  }

  /// Puts every preference back to its default. Name, role, about, language,
  /// instructions and signature are the user's own words and stay.
  void resetToDefaults() {
    themeMode = ThemeMode.system;
    hapticsOn = true;
    Haptics.enabled = true;
    defaultWebSearch = true;
    smartSuggestions = true;
    defaultKnowledge = false;
    defaultRoundTable = false;
    notify.reset();
    mode = modes.first;
    tone = '';
    length = 'detailed';
    textScale = 'normal';
    modelChoice = 'auto';
    modelChoiceName = '';
    autocompleteOn = true;
    voiceAutoSend = false;
    voiceHighAccuracy = false;
    assistActions = true;
    assistLive = true;
    assistSaveHistory = true;
    for (final key in [
      AppPrefs.themeMode,
      AppPrefs.haptics,
      AppPrefs.defaultWebSearch,
      AppPrefs.defaultKnowledge,
      AppPrefs.defaultRoundTable,
      AppPrefs.smartSuggestions,
      AppPrefs.mode,
      AppPrefs.profileTone,
      AppPrefs.profileLength,
      AppPrefs.textScale,
      AppPrefs.modelChoice,
      AppPrefs.modelChoiceName,
      AppPrefs.autocomplete,
      AppPrefs.voiceAutoSend,
      AppPrefs.voiceHighAccuracy,
      AppPrefs.assistActions,
      AppPrefs.assistLive,
      AppPrefs.assistSaveHistory,
    ]) {
      _prefs?.remove(key);
    }
    notifyListeners();
  }

  /// The `profile` object for POST /chat: only non-empty fields.
  Map<String, String> profileJson() => {
    if (name.isNotEmpty) 'name': name,
    if (role.isNotEmpty) 'role': role,
    if (about.isNotEmpty) 'about': about,
    if (tone.isNotEmpty) 'tone': tone,
    'length': length,
    if (language.isNotEmpty) 'language': language,
    if (customInstructions.isNotEmpty) 'instructions': customInstructions,
    if (signature.isNotEmpty) 'signature': signature,
  };
}
