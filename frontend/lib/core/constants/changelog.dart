import 'package:hugeicons/hugeicons.dart';

import 'app_icons.dart';
import 'brand_logos.dart';

/// What kind of change a "What's new" item is. `new` is a Dart keyword, so
/// the "New" kind is [added].
enum ChangeKind { added, improved, fixed }

/// One highlight of a release: a short, human [title] and one [detail] line.
/// [icon] is a Hugeicons glyph, or a [BrandLogos] entry when the change is
/// about a brand (Google Drive, Notion, GitHub…).
typedef Change = ({
  ChangeKind kind,
  String title,
  String detail,
  AppIconData icon,
});

/// One release in "What's new" (About → What's new). Newest first; add an
/// entry with every version bump in pubspec.yaml.
typedef Release = ({
  String version,
  String date,
  String headline,
  List<Change> items,
});

abstract final class ChangelogStrings {
  static const entry = "What's new";
  static const title = "What's new";
  static const latest = 'LATEST';
  static const earlier = 'EARLIER';
  static const seeAll = 'See all';
  static const gotIt = 'Got it';
  static const expand = 'Show changes';
  static const collapse = 'Hide changes';

  static String kind(ChangeKind k) => switch (k) {
    ChangeKind.added => 'NEW',
    ChangeKind.improved => 'IMPROVED',
    ChangeKind.fixed => 'FIXED',
  };

  /// "LATEST · 13 OCT 2026".
  static String heroKicker(String date) => '$latest · ${date.toUpperCase()}';

  /// "v1.4.1".
  static String version(String v) => 'v$v';
  static String count(int n) => n == 1 ? '1 change' : '$n changes';

  /// The one-time sheet after an update.
  static String sheetKicker(String version) =>
      "WHAT'S NEW IN ${version.toUpperCase()}";
  static String sheetMore(int n) => n == 1 ? '+ 1 more' : '+ $n more';
}

abstract final class ChangelogIcons {
  static const entry = HugeIcons.strokeRoundedSparkles;
  static const chevron = HugeIcons.strokeRoundedArrowDown01;
}

abstract final class ChangelogSizes {
  /// Max width of the content on tablets and foldables.
  static const maxWidth = 560.0;

  // Hero card of the latest release.
  static const heroArt = 112.0;

  /// Below this inner card width (in 1x-text units) the hero art is hidden
  /// so the version number keeps its room.
  static const heroArtMinWidth = 260.0;
  static const heroVersion = 64.0;
  static const heroVersionTracking = -2.0;
  static const heroRadius = 28.0;

  // Feature cards.
  static const featureIconBox = 44.0;
  static const featureIcon = 22.0;
  static const kindDot = 8.0;

  // Timeline of earlier releases.
  static const railWidth = 28.0;
  static const railDot = 12.0;
  static const railDotOpen = 14.0;
  static const railLine = 1.5;

  /// From the top of a release row to the center of its dot (lines up with
  /// the version number).
  static const railDotTop = 22.0;
  static const timelineVersion = 22.0;
  static const timelineIconBox = 32.0;
  static const timelineIcon = 18.0;
  static const chevronTurns = 0.5;

  // One-time sheet: how many highlights it shows before "+ N more".
  static const sheetItems = 3;

  static const expandDuration = Duration(milliseconds: 280);
}

/// Shared-preferences key of the version whose "What's new" sheet was seen.
abstract final class ChangelogPrefs {
  static const lastSeenVersion = 'whats_new_seen_version';
}

abstract final class Changelog {
  static Release get latest => releases.first;

  /// The release for [version] (e.g. "1.4.1"), if listed.
  static Release? find(String version) {
    for (final r in releases) {
      if (r.version == version) return r;
    }
    return null;
  }

  static const releases = <Release>[
    (
      version: '1.13.1',
      date: '15 Oct 2026',
      headline: 'Knows where you are, roughly',
      items: [
        (
          kind: ChangeKind.added,
          title: 'Local answers',
          detail:
              'Weather, prices, places and news fit your city or state, '
              'with no location permission. Set your city in Privacy.',
          icon: HugeIcons.strokeRoundedMapsLocation01,
        ),
      ],
    ),
    (
      version: '1.13.0',
      date: '15 Oct 2026',
      headline: 'Tap to do it',
      items: [
        (
          kind: ChangeKind.added,
          title: 'Playlists',
          detail:
              'Song suggestions arrive as a playlist: covers, 30-second '
              'previews, open in your music app, or play them all.',
          icon: HugeIcons.strokeRoundedPlayList,
        ),
        (
          kind: ChangeKind.added,
          title: 'Action cards',
          detail:
              'Directions, calendar events, alarms, timers, calls, rides, '
              'food and travel searches, ready in one tap.',
          icon: HugeIcons.strokeRoundedTouch01,
        ),
        (
          kind: ChangeKind.added,
          title: 'UPI, prefilled',
          detail:
              'Ask to pay someone and sparky opens your UPI app with the '
              'details filled in. You confirm and pay there.',
          icon: HugeIcons.strokeRoundedPayment01,
        ),
      ],
    ),
    (
      version: '1.12.3',
      date: '15 Oct 2026',
      headline: 'A little tick',
      items: [
        (
          kind: ChangeKind.added,
          title: 'Sound on open',
          detail:
              'A soft tick when the assistant opens. Quiet on silent and Do '
              'Not Disturb; turn it off in Assistant settings.',
          icon: HugeIcons.strokeRoundedVolumeHigh,
        ),
      ],
    ),
    (
      version: '1.12.2',
      date: '15 Oct 2026',
      headline: 'Drive, opened up',
      items: [
        (
          kind: ChangeKind.added,
          title: 'Drive previews',
          detail:
              'Drive files open right in sparky, with the original and '
              "sparky's view side by side.",
          icon: HugeIcons.strokeRoundedGoogleDrive,
        ),
        (
          kind: ChangeKind.added,
          title: 'Pick folders',
          detail:
              'Select folders and many files at once. If Google keeps a '
              'folder closed, sparky opens it so you can pick inside.',
          icon: HugeIcons.strokeRoundedFolderAdd,
        ),
      ],
    ),
    (
      version: '1.12.1',
      date: '15 Oct 2026',
      headline: 'Two ways to look',
      items: [
        (
          kind: ChangeKind.added,
          title: 'Original or sparky view',
          detail:
              'Switch any preview between the file itself and what sparky '
              'read from it: a summary, key points and the text.',
          icon: HugeIcons.strokeRoundedView,
        ),
        (
          kind: ChangeKind.fixed,
          title: 'Previews that open',
          detail: 'Images, PDFs and documents open reliably again.',
          icon: HugeIcons.strokeRoundedImage01,
        ),
      ],
    ),
    (
      version: '1.12.0',
      date: '15 Oct 2026',
      headline: 'See it before you ask',
      items: [
        (
          kind: ChangeKind.added,
          title: 'File previews',
          detail:
              'Tap any file to open it right in sparky: images, PDFs, code, '
              'tables, notes and videos.',
          icon: HugeIcons.strokeRoundedFileView,
        ),
        (
          kind: ChangeKind.added,
          title: 'Ask about a file',
          detail:
              'From any preview, one tap starts a chat with that file '
              'attached.',
          icon: HugeIcons.strokeRoundedAiChat01,
        ),
        (
          kind: ChangeKind.improved,
          title: 'Smoother Drive picking',
          detail:
              'The Google Drive picker fills the screen, with files, '
              'folders and shared items in their own tabs.',
          icon: HugeIcons.strokeRoundedFolder01,
        ),
      ],
    ),
    (
      version: '1.11.1',
      date: '15 Oct 2026',
      headline: 'Facts first',
      items: [
        (
          kind: ChangeKind.improved,
          title: 'Checks before it claims',
          detail:
              'Factual questions now search the web first, and sparky says '
              'so when it does not know instead of guessing.',
          icon: HugeIcons.strokeRoundedCheckmarkBadge01,
        ),
        (
          kind: ChangeKind.improved,
          title: 'Updates that resume',
          detail:
              'A dropped connection no longer restarts an update download '
              'from zero.',
          icon: HugeIcons.strokeRoundedDownload04,
        ),
        (
          kind: ChangeKind.added,
          title: 'Crash reports',
          detail:
              'If sparky crashes, it can tell us so we can fix it. Never '
              'your chats. Turn it off in Privacy.',
          icon: HugeIcons.strokeRoundedBug01,
        ),
      ],
    ),
    (
      version: '1.10.0',
      date: '15 Oct 2026',
      headline: 'Straight answers',
      items: [
        (
          kind: ChangeKind.improved,
          title: 'Answers get to the point',
          detail:
              'Replies lead with the answer, fit their length to your '
              'question and skip the filler.',
          icon: HugeIcons.strokeRoundedTarget01,
        ),
        (
          kind: ChangeKind.fixed,
          title: 'Videos, for real',
          detail:
              'sparky answers from the actual frames and audio, cites '
              'moments like [0:42] and says when it can\'t tell.',
          icon: HugeIcons.strokeRoundedVideo01,
        ),
        (
          kind: ChangeKind.fixed,
          title: 'Real model names',
          detail: 'Every answer shows which model wrote it, not just "AI".',
          icon: HugeIcons.strokeRoundedAiChat02,
        ),
        (
          kind: ChangeKind.improved,
          title: 'One icon per option',
          detail: 'Settings no longer reuse the same icon for different things.',
          icon: HugeIcons.strokeRoundedDashboardSquare02,
        ),
      ],
    ),
    (
      version: '1.9.3',
      date: '14 Oct 2026',
      headline: 'Smoother, everywhere',
      items: [
        (
          kind: ChangeKind.improved,
          title: 'Friendlier sheets',
          detail:
              'Every confirm and choice now slides up from the bottom, with '
              'a little illustration to go with it.',
          icon: HugeIcons.strokeRoundedSquareArrowUp02,
        ),
        (
          kind: ChangeKind.improved,
          title: 'A glowing profile',
          detail:
              'Your photo gets a soft dot aura that lights up when you '
              'touch it. Tap the photo to change it.',
          icon: HugeIcons.strokeRoundedUserCircle,
        ),
        (
          kind: ChangeKind.fixed,
          title: 'Keyboard behaves',
          detail: 'Tap anywhere outside a text box to put the keyboard away.',
          icon: HugeIcons.strokeRoundedKeyboard,
        ),
        (
          kind: ChangeKind.fixed,
          title: 'One buzz, not two',
          detail: 'Opening the sidebar from the menu vibrates just once.',
          icon: HugeIcons.strokeRoundedSmartPhone01,
        ),
        (
          kind: ChangeKind.added,
          title: 'Know your numbers',
          detail:
              'The API keys intro now shows the telemetry and usage '
              'analytics your own keys unlock.',
          icon: HugeIcons.strokeRoundedAnalytics01,
        ),
        (
          kind: ChangeKind.fixed,
          title: 'Fresh update status',
          detail:
              'About checks again when you open it, and its glow stays '
              'inside the art.',
          icon: HugeIcons.strokeRoundedRefresh,
        ),
      ],
    ),
    (
      version: '1.9.0',
      date: '14 Oct 2026',
      headline: 'Yours, and locked',
      items: [
        (
          kind: ChangeKind.added,
          title: 'Bring your own keys',
          detail:
              'Add a key from Groq, OpenRouter, NVIDIA or Ollama and your '
              'chats run on it. Test it in one tap.',
          icon: HugeIcons.strokeRoundedKey01,
        ),
        (
          kind: ChangeKind.added,
          title: 'Your own usage',
          detail:
              'See requests, tokens and models for the chats run on your '
              'keys. Only you can see it.',
          icon: HugeIcons.strokeRoundedAnalytics01,
        ),
        (
          kind: ChangeKind.improved,
          title: 'Encrypted for you',
          detail:
              'Your chats, memories, notes and files are encrypted on our '
              'servers with a key of their own.',
          icon: HugeIcons.strokeRoundedSecurityLock,
        ),
        (
          kind: ChangeKind.improved,
          title: 'Livelier dots',
          detail:
              'Backgrounds and your profile ring now move like the '
              'assistant, then rest to save battery.',
          icon: HugeIcons.strokeRoundedGridView,
        ),
        (
          kind: ChangeKind.fixed,
          title: 'Sharper circle search',
          detail:
              'Answers stick to what you circled, and a blank capture says '
              'so instead of guessing.',
          icon: HugeIcons.strokeRoundedSearchArea,
        ),
      ],
    ),
    (
      version: '1.8.0',
      date: '14 Oct 2026',
      headline: 'See sparky think',
      items: [
        (
          kind: ChangeKind.added,
          title: 'Live progress',
          detail:
              'While you wait, sparky shows what it is doing: picking a '
              'model, searching the web, reading your files.',
          icon: HugeIcons.strokeRoundedLoading03,
        ),
        (
          kind: ChangeKind.added,
          title: 'Meet the models',
          detail:
              'Tap the model name under any answer to see who made it and '
              'what it is good at.',
          icon: HugeIcons.strokeRoundedInformationCircle,
        ),
        (
          kind: ChangeKind.improved,
          title: 'Living backgrounds',
          detail:
              'The dot grid on sign-in, onboarding and the home screen '
              'ripples when you touch it, then rests to save battery.',
          icon: HugeIcons.strokeRoundedGridView,
        ),
        (
          kind: ChangeKind.improved,
          title: 'Cleaner About page',
          detail: 'Your version and update status, at a glance.',
          icon: HugeIcons.strokeRoundedInformationSquare,
        ),
      ],
    ),
    (
      version: '1.7.0',
      date: '13 Oct 2026',
      headline: 'Updates, built in',
      items: [
        (
          kind: ChangeKind.added,
          title: 'In-app updates',
          detail:
              'New versions download inside sparky and install in a tap. '
              'No more hunting for APKs.',
          icon: HugeIcons.strokeRoundedDownload04,
        ),
        (
          kind: ChangeKind.added,
          title: 'Gentle reminders',
          detail:
              'sparky asks once per version, at a quiet moment. Later means '
              'later: it waits days, not minutes.',
          icon: HugeIcons.strokeRoundedNotification01,
        ),
        (
          kind: ChangeKind.improved,
          title: 'Saves your data',
          detail:
              'Small fixes download on Wi-Fi only. You can change that in '
              'About.',
          icon: HugeIcons.strokeRoundedWifi01,
        ),
      ],
    ),
    (
      version: '1.6.1',
      date: '13 Oct 2026',
      headline: 'Say it, sparky fixes it',
      items: [
        (
          kind: ChangeKind.added,
          title: 'Smart dictation',
          detail:
              'What you say is tidied up as you speak: punctuation, numbers, '
              'names and misheard words. Hinglish stays Hinglish.',
          icon: HugeIcons.strokeRoundedMic01,
        ),
        (
          kind: ChangeKind.added,
          title: 'Undo any fix',
          detail: 'Tap "Undo fix" to get back exactly what you said.',
          icon: HugeIcons.strokeRoundedTextCheck,
        ),
        (
          kind: ChangeKind.improved,
          title: 'Simpler settings',
          detail:
              'Technical details are tucked away; only what you need shows.',
          icon: HugeIcons.strokeRoundedSettings02,
        ),
        (
          kind: ChangeKind.fixed,
          title: 'Answers keep going',
          detail:
              'If the connection drops, sparky reconnects and carries on '
              'instead of stopping.',
          icon: HugeIcons.strokeRoundedRefresh,
        ),
      ],
    ),
    (
      version: '1.5.3',
      date: '13 Oct 2026',
      headline: 'Open it anywhere',
      items: [
        (
          kind: ChangeKind.added,
          title: 'Open in your apps',
          detail:
              'Say "play it" or "open in music app" and sparky finds the song '
              'and opens it in the app you have.',
          icon: HugeIcons.strokeRoundedMusicNote01,
        ),
        (
          kind: ChangeKind.added,
          title: 'Assistant chats saved',
          detail: 'Chats from the assistant now show up in your history.',
          icon: HugeIcons.strokeRoundedLink01,
        ),
      ],
    ),
    (
      version: '1.5.0',
      date: '13 Oct 2026',
      headline: 'Circle to search',
      items: [
        (
          kind: ChangeKind.added,
          title: 'Circle to search',
          detail:
              'Hold the power button, circle anything on screen, and sparky '
              'tells you what it is.',
          icon: HugeIcons.strokeRoundedSearch01,
        ),
        (
          kind: ChangeKind.added,
          title: 'Phone actions',
          detail:
              'Alarms, reminders, events, directions and messages, always '
              'after you confirm.',
          icon: HugeIcons.strokeRoundedTarget02,
        ),
        (
          kind: ChangeKind.improved,
          title: 'Better web search',
          detail: 'Faster, more reliable answers with sources.',
          icon: HugeIcons.strokeRoundedWifi01,
        ),
      ],
    ),
    (
      version: '1.4.1',
      date: '13 Oct 2026',
      headline: 'The assistant gets smarter',
      items: [
        (
          kind: ChangeKind.added,
          title: 'Everything chat can do',
          detail:
              'The assistant now searches the web, uses your knowledge base, '
              'runs Round Table and writes docs.',
          icon: HugeIcons.strokeRoundedAiMagic,
        ),
        (
          kind: ChangeKind.added,
          title: 'Attach files',
          detail: 'Add photos, videos and documents right from the assistant.',
          icon: AppIcons.attach,
        ),
        (
          kind: ChangeKind.added,
          title: 'A quick tour',
          detail:
              'New accounts get a short welcome tour. Replay it any time '
              'from About → Take the tour.',
          icon: HugeIcons.strokeRoundedRoute01,
        ),
        (
          kind: ChangeKind.added,
          title: 'Terms and privacy',
          detail:
              'Read the Terms of Service and Privacy Policy from the '
              'sign-in screen.',
          icon: HugeIcons.strokeRoundedSecurityCheck,
        ),
        (
          kind: ChangeKind.improved,
          title: 'A living backdrop',
          detail: 'The assistant glows with a new animated red dot pattern.',
          icon: HugeIcons.strokeRoundedGrid,
        ),
        (
          kind: ChangeKind.improved,
          title: 'Cleaner chat header',
          detail: 'Three matching round buttons at the top of every chat.',
          icon: HugeIcons.strokeRoundedLayoutTop,
        ),
      ],
    ),
    (
      version: '1.3.1',
      date: '13 Oct 2026',
      headline: 'Real logos, everywhere',
      items: [
        (
          kind: ChangeKind.improved,
          title: 'Real brand logos',
          detail:
              'Google Drive, Notion, GitHub, model providers and file types '
              'show their real logos.',
          icon: BrandLogos.googleDrive,
        ),
        (
          kind: ChangeKind.added,
          title: 'More apps on the way',
          detail: 'Photos, Gmail, Calendar and Slack are listed in Apps.',
          icon: BrandLogos.gmail,
        ),
      ],
    ),
    (
      version: '1.3.0',
      date: '13 Oct 2026',
      headline: 'sparky, from any app',
      items: [
        (
          kind: ChangeKind.added,
          title: 'Your phone assistant',
          detail: 'Hold the power button to ask sparky from any app.',
          icon: HugeIcons.strokeRoundedSmartPhone01,
        ),
        (
          kind: ChangeKind.added,
          title: 'Share your screen',
          detail: 'Show sparky what you are looking at in one tap.',
          icon: HugeIcons.strokeRoundedComputerPhoneSync,
        ),
        (
          kind: ChangeKind.added,
          title: 'Tidy up chats',
          detail:
              'Select several chats to archive, pin or delete, or clear them '
              'all in Settings.',
          icon: HugeIcons.strokeRoundedCheckList,
        ),
        (
          kind: ChangeKind.improved,
          title: 'Fresh sign-in',
          detail: 'Redesigned sign-in and create-account screens.',
          icon: HugeIcons.strokeRoundedLogin01,
        ),
      ],
    ),
    (
      version: '1.2.0',
      date: '13 Oct 2026',
      headline: 'Bring your files',
      items: [
        (
          kind: ChangeKind.added,
          title: 'Google Drive',
          detail: 'Connect Drive. sparky only sees the files you share.',
          icon: BrandLogos.googleDrive,
        ),
        (
          kind: ChangeKind.added,
          title: 'Notion',
          detail: 'Connect Notion. sparky only sees the pages you share.',
          icon: BrandLogos.notion,
        ),
        (
          kind: ChangeKind.improved,
          title: 'Smarter memory',
          detail:
              'Remembers your name, nickname, city and preferences, and '
              'keeps them up to date.',
          icon: HugeIcons.strokeRoundedBrain02,
        ),
        (
          kind: ChangeKind.improved,
          title: 'Lighter GitHub sign-in',
          detail: 'Only asks for your name and email.',
          icon: BrandLogos.github,
        ),
      ],
    ),
    (
      version: '1.1.2',
      date: '12 Oct 2026',
      headline: 'A warmer welcome',
      items: [
        (
          kind: ChangeKind.added,
          title: 'Fresh greetings',
          detail: 'A new greeting and drawing every time you start a chat.',
          icon: HugeIcons.strokeRoundedSmile,
        ),
        (
          kind: ChangeKind.improved,
          title: 'Clear GitHub permissions',
          detail: 'The permission card now speaks plain language.',
          icon: BrandLogos.github,
        ),
        (
          kind: ChangeKind.fixed,
          title: 'No more blank screen',
          detail: 'Signing in with GitHub opens the app as it should.',
          icon: BrandLogos.github,
        ),
      ],
    ),
    (
      version: '1.1.1',
      date: '12 Oct 2026',
      headline: 'GitHub, right in the app',
      items: [
        (
          kind: ChangeKind.added,
          title: 'GitHub inside sparky',
          detail:
              'Pull requests, issues, commits and activity open in the app, '
              'with Ask Sparky everywhere.',
          icon: BrandLogos.github,
        ),
        (
          kind: ChangeKind.added,
          title: 'Review and merge',
          detail:
              'Review, comment, merge and manage labels when you have access.',
          icon: HugeIcons.strokeRoundedGitMerge,
        ),
      ],
    ),
    (
      version: '1.1.0',
      date: '12 Oct 2026',
      headline: 'A whole new look',
      items: [
        (
          kind: ChangeKind.added,
          title: 'Apps hub',
          detail: 'One home for your apps, with a full GitHub screen.',
          icon: HugeIcons.strokeRoundedDashboardSquare01,
        ),
        (
          kind: ChangeKind.added,
          title: 'Talk to sparky',
          detail: 'Ask out loud with voice input.',
          icon: HugeIcons.strokeRoundedMic01,
        ),
        (
          kind: ChangeKind.added,
          title: 'Smart toggles',
          detail: 'Quick switches for web, knowledge base and docs.',
          icon: HugeIcons.strokeRoundedToggleOn,
        ),
        (
          kind: ChangeKind.improved,
          title: 'A fresh design',
          detail: 'New settings, telemetry, knowledge base and sidebar.',
          icon: HugeIcons.strokeRoundedPaintBrush01,
        ),
      ],
    ),
  ];
}
