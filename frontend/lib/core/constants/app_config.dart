abstract final class AppConfig {
  /// Hosted backend (Coolify). Override with --dart-define API_BASE_URL.
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://sparky.cloudnsofts.com',
  );

  /// Sent as a bearer token only when non-empty (matches the server API_TOKEN).
  /// Both values come from env.json: `flutter run --dart-define-from-file=env.json`.
  static const apiToken = String.fromEnvironment('API_TOKEN');

  /// Site logos for source chips.
  static String faviconUrl(String domain) =>
      'https://www.google.com/s2/favicons?domain=$domain&sz=64';

  /// Iconify icons through the backend, which swaps a name that does not
  /// exist for the closest real icon and reports it in `X-Icon-Id`.
  static String iconUrl(String set, String name) =>
      '$apiBaseUrl/icons/$set/$name.svg';

  /// Iconify sets drawn in their own colors (brand logos); the rest take
  /// the text color.
  static const colorIconSets = {
    'logos',
    'devicon',
    'skill-icons',
    'vscode-icons',
    'flat-color-icons',
    'fluent-emoji-flat',
    'twemoji',
    'noto',
  };

  /// Wikimedia asks image clients to identify themselves.
  static const imageHeaders = {
    'User-Agent': 'AgentWorkerApp/1.0 (engineering chat app)',
  };
}
