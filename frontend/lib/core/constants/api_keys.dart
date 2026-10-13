import 'package:hugeicons/hugeicons.dart';

import 'app_icons.dart';
import 'app_sizes.dart';
import 'brand_logos.dart';
import 'telemetry.dart';

/// Settings → Your API keys: bring-your-own provider keys, the key sheet,
/// the first-open intro and the "Your usage" view. Provider names, links and
/// placeholders come from the server (GET /me/keys); only copy lives here.

abstract final class ApiKeysPaths {
  static const keys = '/me/keys';
  static String key(String provider) => '/me/keys/$provider';
  static String test(String provider) => '/me/keys/$provider/test';
  static const usage = '/me/usage/keys';
}

abstract final class ApiKeysStrings {
  // Settings entry.
  static const settingsLabel = 'Your API keys';
  static const settingsHelp = 'Use your own accounts with AI providers.';
  static const settingsKeywords =
      'api keys bring your own key provider groq openrouter nvidia ollama '
      'token secret';

  // Page.
  static const title = 'Your API keys';
  static const lead =
      'Add a key from a provider you already use and sparky sends your '
      'chats through it. Your key is only ever used for you.';
  static const howItWorks = 'How it works';
  static const providersHeader = 'Providers';
  static const emptyRow = 'No key yet';
  static const loadFailed = 'Couldn\'t load your keys. Pull down to retry.';

  // Row.
  static String endsWith(String hint) => 'Ends in $hint';
  static const add = 'Add key';
  static const replace = 'Replace';
  static const remove = 'Remove';
  static const test = 'Test';
  static const testing = 'Testing…';
  static const getKey = 'Get a key';

  // Status chips.
  static const statusValid = 'WORKS';
  static const statusInvalid = 'NOT ACCEPTED';
  static const statusQuota = 'OUT OF CREDIT';
  static const statusUntested = 'NOT TESTED';

  // Live test results.
  static const resultValid = 'Works';
  static const resultInvalid = 'Key not accepted';
  static const resultQuota = 'Out of credit';
  static const resultNetwork = 'Couldn\'t reach provider';

  // Sheet.
  static const sheetTitleAdd = 'Add a key';
  static String sheetTitleFor(String provider) => '$provider key';
  static const sheetSubtitle =
      'Paste the key from your provider. It is encrypted and never shown '
      'again.';
  static const fieldLabel = 'API key';
  static const paste = 'Paste';
  static const show = 'Show key';
  static const hide = 'Hide key';
  static const save = 'Save and test';
  static const saving = 'Checking…';
  static const badFormat = 'That doesn\'t look like a key from this provider.';
  static const saveFailed = 'Couldn\'t save that key. Try again.';
  static const savedWorks = 'Saved. Your key works.';

  // Remove.
  static const removeTitle = 'Remove this key?';
  static String removeBody(String provider) =>
      'sparky stops using your $provider key and goes back to its own. You '
      'can add it again any time.';
  static const removed = 'Key removed';
  static const removeFailed = 'Couldn\'t remove the key. Try again.';

  // Usage entry.
  static const usageTitle = 'Your usage';
  static const usageHelp = 'Requests and tokens on your own keys.';
}

/// The first-open intro (three swipeable pages).
abstract final class ApiKeysIntroStrings {
  static const pages = 3;

  static const skip = 'Skip';
  static const next = 'Next';
  static const back = 'Back';
  static const done = 'Add a key';

  static const useKicker = 'YOUR OWN KEYS';
  static const useTitle = 'Use your own keys.';
  static const useBody =
      'Already have an account with an AI provider? Bring your key and '
      'sparky sends your chats through it.';

  static const privateKicker = 'PRIVATE BY DESIGN';
  static const privateTitle = 'Only you can use it.';
  static const privateBody =
      'Your key is encrypted on our server and never shared with anyone else.';
  static const privatePoints = [
    (
      icon: ApiKeysIcons.lock,
      title: 'Encrypted',
      detail: 'Stored scrambled. We can\'t read it back.',
    ),
    (
      icon: ApiKeysIcons.key,
      title: 'Last 4 only',
      detail: 'Only the last 4 characters are ever shown.',
    ),
    (
      icon: ApiKeysIcons.remove,
      title: 'Remove any time',
      detail: 'One tap and it is gone.',
    ),
  ];

  static const usageKicker = 'YOUR USAGE';
  static const usageTitle = 'See what you use.';
  static const usageBody =
      'Once a key works you get your own usage view: requests, tokens and '
      'the models you used.';
  static const usagePoints = [
    (
      icon: ApiKeysIcons.test,
      title: 'Test in one tap',
      detail: 'Check a key works before you rely on it.',
    ),
    (
      icon: ApiKeysIcons.usage,
      title: 'Just your numbers',
      detail: 'Only calls made with your keys. Nothing from anyone else.',
    ),
  ];
}

/// The first-open intro to "Your usage" (three swipeable pages).
abstract final class UsageIntroStrings {
  static const pages = 3;

  static const skip = ApiKeysIntroStrings.skip;
  static const next = ApiKeysIntroStrings.next;
  static const back = ApiKeysIntroStrings.back;
  static const done = 'See my usage';

  /// The small link on the usage view that reopens the intro.
  static const howItWorks = 'How it works';

  static const analyticsKicker = 'YOUR ANALYTICS';
  static const analyticsTitle = 'Your own analytics.';
  static const analyticsBody =
      'See how many requests you sent, how many tokens they used and which '
      'models answered, day by day, for every chat that ran on your keys.';

  static const onlyYoursKicker = 'ONLY YOURS';
  static const onlyYoursTitle = 'Only yours.';
  static const onlyYoursBody =
      'This is your data and nobody else\'s. It stays private to you.';
  static const onlyYoursPoints = [
    (
      icon: ApiKeysIcons.key,
      title: 'Just your keys',
      detail: 'Only chats that ran on keys you added.',
    ),
    (
      icon: ApiKeysIcons.lock,
      title: 'Never other people\'s',
      detail: 'You never see anyone else\'s numbers, and they never see yours.',
    ),
    (
      icon: ApiKeysIcons.usage,
      title: 'Never the server\'s',
      detail: 'sparky\'s own usage is not mixed in.',
    ),
  ];

  static const workKicker = 'MAKE IT WORK FOR YOU';
  static const workTitle = 'Make it work for you.';
  static const workBody = 'A few quick ways to put your numbers to use.';
  static const workPoints = [
    (
      icon: ApiKeysIcons.day,
      title: 'Spot heavy days',
      detail: 'See which days you used the most.',
    ),
    (
      icon: ApiKeysIcons.models,
      title: 'Compare models',
      detail: 'See which models answered and how fast.',
    ),
    (
      icon: ApiKeysIcons.warning,
      title: 'Catch a key running low',
      detail: 'Notice failures early, before a key runs out.',
    ),
  ];
}

/// "Your usage" view.
abstract final class KeyUsageStrings {
  static const title = 'Your usage';
  static const lead = 'Calls made with your own keys.';
  static const days7 = '7 DAYS';
  static const days30 = '30 DAYS';
  static const requests = 'REQUESTS';
  static const tokens = 'TOKENS';
  static const latency = 'AVG TIME';
  static const failed = 'FAILED';
  static const byDay = 'Requests per day';
  static const byModel = 'By model';
  static const byProvider = 'By provider';
  static const empty = 'No calls on your keys yet.';
  static const emptyHint = 'Chat with sparky and your usage shows up here.';
  static const loadFailed = 'Couldn\'t load your usage. Pull down to retry.';
  static const tooltipRequests = 'requests';
  static String modelLine(int requests, int tokens, String tokensText) =>
      '$requests req · $tokensText tok';
}

abstract final class ApiKeysSizes {
  static const logo = AppIconSize.lg;
  static const chipRadius = AppRadius.pill;
  static const sheetFieldLines = 1;
  static const providerChipGap = AppSpacing.sm;
  static const resultLines = 2;
  static const usageBarsHeight = 140.0;
  static const usageBarWidth = 8.0;
  static const usageTopModels = 6;
  static const introLogoBox = 56.0;
  static const minKeyLength = 16;
  static const saveMinWidth = 140.0;
}

abstract final class ApiKeysIcons {
  static const key = AppIcons.key;
  static const lock = HugeIcons.strokeRoundedLockPassword;
  static const remove = AppIcons.delete;
  static const test = AppIcons.check;
  static const usage = HugeIcons.strokeRoundedAnalytics01;
  static const info = HugeIcons.strokeRoundedInformationCircle;
  static const day = HugeIcons.strokeRoundedCalendar03;
  static const models = TelemetryIcons.models;
  static const warning = AppIcons.alert;
  static const paste = HugeIcons.strokeRoundedClipboard;
  static const show = HugeIcons.strokeRoundedView;
  static const hide = HugeIcons.strokeRoundedViewOff;
  static const link = HugeIcons.strokeRoundedLink04;

  /// The provider's real logo (groq, nvidia, ollama, openrouter).
  static AppIconData provider(String id) => AppIcons.provider(id);
  static const providerFallback = BrandLogos.openrouter;
}

/// SharedPreferences key: the intro was seen by this account on this phone.
abstract final class ApiKeysPrefs {
  static String introSeen(String userId) => 'api_keys_intro_$userId';

  /// The usage intro was seen by this account on this phone.
  static String usageIntroSeen(String userId) => 'key_usage_intro_$userId';
}
