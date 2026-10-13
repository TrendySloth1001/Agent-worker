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
