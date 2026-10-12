/// SharedPreferences keys.
abstract final class AppPrefs {
  static const themeMode = 'theme_mode';
  static const haptics = 'haptics_on';
  static const defaultWebSearch = 'default_web_search';
  static const defaultKnowledge = 'default_knowledge';
  static const defaultRoundTable = 'default_round_table';
  static const notifyRoundTable = 'notify_round_table';
  static const autocomplete = 'autocomplete_on';
  static const mode = 'chat_mode';
  static const profileName = 'profile_name';
  static const profileRole = 'profile_role';
  static const profileAbout = 'profile_about';
  static const profileTone = 'profile_tone';
  static const profileLength = 'profile_length';
  static const profileLanguage = 'profile_language';
  static const profileInstructions = 'profile_instructions';
  static const profileSignature = 'profile_signature';
  static const browserPackage = 'browser_package';
  static const browserLabel = 'browser_label';

  /// The GitHub web sign-in waiting for its deep link (survives the app
  /// being killed while the user is in the browser).
  static const githubWebPending = 'github_web_pending';
}
