import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_prefs.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/haptics.dart';

/// Persisted user preferences.
class SettingsController extends ChangeNotifier {
  SettingsController._(this._prefs) {
    themeMode = _readTheme();
    hapticsOn = _prefs?.getBool(AppPrefs.haptics) ?? true;
    defaultWebSearch = _prefs?.getBool(AppPrefs.defaultWebSearch) ?? false;
    defaultKnowledge = _prefs?.getBool(AppPrefs.defaultKnowledge) ?? false;
    defaultRoundTable = _prefs?.getBool(AppPrefs.defaultRoundTable) ?? false;
    notifyRoundTable = _prefs?.getBool(AppPrefs.notifyRoundTable) ?? true;
    autocompleteOn = _prefs?.getBool(AppPrefs.autocomplete) ?? true;
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
  late bool defaultWebSearch;
  late bool defaultKnowledge;
  late bool defaultRoundTable;

  /// System notification when a round table finishes in the background.
  late bool notifyRoundTable;
  late String mode;

  // Personalization. Empty string means not set; [tone] '' means no tone.
  late String name, role, about, language, customInstructions, signature;
  late String tone;
  late String length;

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

  void setDefaultWebSearch(bool value) {
    defaultWebSearch = value;
    _prefs?.setBool(AppPrefs.defaultWebSearch, value);
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
    notifyRoundTable = value;
    _prefs?.setBool(AppPrefs.notifyRoundTable, value);
    notifyListeners();
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
