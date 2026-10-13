import 'package:hugeicons/hugeicons.dart';

import 'app_icons.dart';
import 'app_sizes.dart';
import 'assist.dart';
import 'brand_logos.dart';
import 'memory.dart';

/// The first-run tour shown once per account after sign-up / first sign-in,
/// and again from About → Take the tour.

/// One feature row on a tour page.
typedef TourPoint = ({AppIconData icon, String title, String detail});

abstract final class OnboardingStrings {
  /// About → the button that replays the tour.
  static const takeTour = 'Take the tour';

  // Top bar and buttons.
  static const skip = 'Skip';
  static const back = 'Back';
  static const next = 'Next';
  static const start = 'Start chatting';
  static String step(int page, int total) =>
      '${(page + 1).toString().padLeft(2, '0')} / '
      '${total.toString().padLeft(2, '0')}';
  static String pageLabel(int page, int total) => 'Page ${page + 1} of $total';

  // 1. Welcome.
  static const welcomeKicker = 'WELCOME';
  static String hello(String firstName) =>
      firstName.isEmpty ? 'Hi, meet sparky.' : 'Hi $firstName, meet sparky.';
  static const welcomeBody =
      'Your personal AI. Ask anything, write, plan, learn and get things '
      'done.';
  static const welcomeNote = 'A quick look around takes under a minute.';
  static const welcomeTags = ['ASK', 'WRITE', 'PLAN', 'LEARN'];

  // 2. Ask anything.
  static const askKicker = 'ASK ANYTHING';
  static const askTitle = 'Ask anything.';
  static const askBody =
      'Big questions or small ones, in your own words. Type it, say it or '
      'snap a photo.';
  static const askPoints = <TourPoint>[
    (
      icon: OnboardingIcons.web,
      title: 'Answers you can check',
      detail:
          'Picks the right AI for each question and searches the web, with '
          'sources you can tap.',
    ),
    (
      icon: OnboardingIcons.write,
      title: 'Write and plan',
      detail: 'Emails, essays, trips and to-do lists, drafted in seconds.',
    ),
    (
      icon: OnboardingIcons.voice,
      title: 'Talk instead of type',
      detail: 'Tap the mic and just say it.',
    ),
    (
      icon: OnboardingIcons.attach,
      title: 'Photos and files',
      detail: 'Add a photo, PDF or video and ask about it, or get a summary.',
    ),
  ];

  // 3. Learn and remember.
  static const knowKicker = 'LEARN AND REMEMBER';
  static const knowTitle = 'Go deeper.';
  static const knowBody =
      'Keep your notes close, dig into a topic and let sparky remember what '
      'matters to you.';
  static const knowPoints = <TourPoint>[
    (
      icon: OnboardingIcons.knowledge,
      title: 'Your notes and files',
      detail: 'Save them once. Turn on KB and sparky checks them first.',
    ),
    (
      icon: OnboardingIcons.doc,
      title: 'Long documents',
      detail: 'Reports, study guides and plans. Turn on DOC to write one.',
    ),
    (
      icon: OnboardingIcons.roundTable,
      title: 'A second opinion',
      detail: 'Turn on TABLE and several AIs talk it over, then agree.',
    ),
    (
      icon: OnboardingIcons.memory,
      title: 'Memory',
      detail:
          'Remembers what matters about you. You see it, edit it or switch '
          'it off.',
    ),
  ];

  // 4. Apps (optional extras).
  static const appsKicker = 'OPTIONAL EXTRAS';
  static const appsTitle = 'Connect your apps.';
  static const appsBody =
      'If you like, link apps you already use and ask about them in plain '
      'words.';
  static const appsPoints = <TourPoint>[
    (
      icon: BrandLogos.googleDrive,
      title: 'Google Drive',
      detail: 'Beta. Only the files you pick. Nothing else is opened.',
    ),
    (
      icon: BrandLogos.notion,
      title: 'Notion',
      detail: 'Only the pages you share with sparky.',
    ),
    (
      icon: BrandLogos.github,
      title: 'GitHub',
      detail: 'For coders: projects, changes and code reviews.',
    ),
  ];
  static const appsNote =
      'Skip it for now if you like. Connect any time from Apps.';

  // 5. Assistant.
  static const assistKicker = 'EVERYWHERE';
  static const assistTitle = 'sparky, over any app.';
  static const assistBody =
      'Hold the power button and sparky opens on top of whatever you are '
      'doing.';
  static const assistPoints = <TourPoint>[
    (
      icon: OnboardingIcons.power,
      title: 'Hold the power button',
      detail: 'Or swipe up from a bottom corner. Ask, then carry on.',
    ),
    (
      icon: OnboardingIcons.screen,
      title: AssistStrings.shareScreen,
      detail: 'Ask about what is on screen. Nothing is read before that tap.',
    ),
  ];
  static const assistCta = AssistStrings.setDefault;
  static const assistDone = 'sparky is your assistant';
  static const assistLater = 'Optional. You can do it later in Settings.';

  // 6. Make it yours.
  static const yoursKicker = 'MAKE IT YOURS';
  static const yoursTitle = 'Make it yours.';
  static const yoursBody = 'Two quick picks. Change them any time in Settings.';
  static const nameLabel = 'What should I call you?';
  static const nameHint = 'Your name';
  static const styleLabel = 'How should I reply?';
}

abstract final class OnboardingIcons {
  static const write = AppIcons.edit;
  static const voice = AppIcons.mic;
  static const web = AppIcons.web;
  static const roundTable = AppIcons.roundTable;
  static const attach = AppIcons.attach;
  static const knowledge = AppIcons.knowledge;
  static const doc = AppIcons.doc;
  static const memory = MemoryIcons.section;
  static const power = AssistIcons.power;
  static const screen = AssistIcons.screen;
  static const assistant = AssistIcons.assistant;
  static const check = AppIcons.check;
  static const name = AppIcons.profileName;
  static const next = HugeIcons.strokeRoundedArrowRight01;
  static const tour = HugeIcons.strokeRoundedRoute01;
}

abstract final class OnboardingSizes {
  static const pages = 6;

  /// Content column cap on wide screens.
  static const maxWidth = 480.0;

  /// Illustration height; smaller on short screens (height in 1x-text units).
  static const art = 176.0;
  static const artCompact = 120.0;
  static const artCompactBelow = 800.0;

  /// The welcome page's art: the page has room for a bigger hello.
  static const heroArt = 248.0;
  static const heroArtCompact = 168.0;

  static const headline = AppFontSize.headline;

  // Page indicator: Nothing-style glyph dots, the current one a red pill.
  static const dot = 6.0;
  static const dotActive = 22.0;
  static const dotGap = 6.0;

  /// Gap between feature rows.
  static const pointGap = AppSpacing.md;

  /// Start of the staggered content entrance, per row.
  static const stagger = 0.12;

  /// How far content rises as it enters, in logical pixels.
  static const rise = 12.0;
}

abstract final class OnboardingDurations {
  static const page = Duration(milliseconds: 380);
  static const dot = Duration(milliseconds: 260);
  static const entrance = Duration(milliseconds: 520);

  /// The "has chats" check for servers without the onboarded flag.
  static const decide = Duration(seconds: 6);
}

/// SharedPreferences key: the tour was done for this account on this phone.
abstract final class OnboardingPrefs {
  static String done(String userId) => 'onboarded_$userId';
}
