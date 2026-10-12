import 'package:hugeicons/hugeicons.dart';

import 'app_icons.dart';
import 'app_sizes.dart';

/// About sparky (Settings → ABOUT → ABOUT SPARKY, Profile footer): what the
/// app does, privacy, backend, credits, licenses and feedback.

/// One "WHAT IT DOES" / "PRIVACY" row.
typedef AboutItem = ({AppIconData icon, String title, String detail});

/// One credit; [url] opens in the browser when set.
typedef AboutCredit = ({
  AppIconData icon,
  String label,
  String value,
  String? url,
});

abstract final class AboutStrings {
  static const entry = 'ABOUT SPARKY';
  static const title = 'ABOUT';
  static const appName = 'sparky';
  static const tagline = 'Your engineering sidekick.';

  // Version line, e.g. VERSION 1.0.0 (1) · ANDROID.
  static const fallbackVersion = '1.0.0';
  static const fallbackBuild = '1';
  static const fallbackPlatform = 'Android';
  static String versionLine(String version, String build, String platform) =>
      'Version $version ($build) · $platform';
  static String versionShort(String version, String build) =>
      '$version ($build)';

  // Sections.
  static const whatItDoes = 'WHAT IT DOES';
  static const privacy = 'PRIVACY';
  static const backend = 'BACKEND';
  static const credits = 'CREDITS';

  static const features = <AboutItem>[
    (
      icon: AboutIcons.models,
      title: 'Multi-model chat',
      detail:
          'Automatic model routing across free cloud models: Groq, '
          'Ollama Cloud, NVIDIA and OpenRouter.',
    ),
    (
      icon: AboutIcons.web,
      title: 'Web search',
      detail: 'Answers grounded in the web, with sentence-level citations.',
    ),
    (
      icon: AboutIcons.knowledge,
      title: 'Knowledge base',
      detail: 'Save notes and documents; sparky searches them when you ask.',
    ),
    (
      icon: AboutIcons.roundTable,
      title: 'Round Table',
      detail: 'Several models debate a question and agree on one answer.',
    ),
    (
      icon: AboutIcons.doc,
      title: 'DOC mode',
      detail: 'Long-form documents, written section by section.',
    ),
    (
      icon: AboutIcons.github,
      title: 'GitHub',
      detail: 'Repos, commits, the git graph and pull request reviews.',
    ),
    (
      icon: AboutIcons.widgets,
      title: 'Rich widgets',
      detail: 'Charts, calculators, quizzes, HTML pages, diagrams and math.',
    ),
    (
      icon: AboutIcons.attach,
      title: 'Attachments',
      detail: 'Images, documents, video and audio.',
    ),
    (
      icon: AboutIcons.fork,
      title: 'Your chats, your way',
      detail: 'Fork, merge, share and export any conversation.',
    ),
  ];

  /// The server host goes into the first bullet at runtime.
  static List<AboutItem> privacyItems(String host) => [
    (
      icon: AboutIcons.server,
      title: 'Stored on your sparky server',
      detail:
          'Chats and files live on $host and are only visible to your '
          'account.',
    ),
    (
      icon: AboutIcons.lock,
      title: 'Private file storage',
      detail: 'Files sit in private storage and open through expiring links.',
    ),
    (
      icon: AboutIcons.key,
      title: 'Encrypted GitHub tokens',
      detail: 'GitHub tokens are encrypted at rest.',
    ),
    (
      icon: AboutIcons.delete,
      title: 'Delete anything',
      detail: 'Remove any file in Storage, or your whole account in Profile.',
    ),
    (
      icon: AboutIcons.send,
      title: 'Model providers',
      detail:
          'Your messages are sent to third-party model providers to '
          'generate answers.',
    ),
  ];

  // Backend card.
  static const url = 'URL';
  static const status = 'STATUS';
  static const tapToCopy = 'TAP TO COPY';
  static const urlCopied = 'Backend URL copied.';

  static const creditList = <AboutCredit>[
    (
      icon: AboutIcons.illustrations,
      label: 'ILLUSTRATIONS',
      value: 'Open Peeps by Pablo Stanley (CC0)',
      url: 'https://www.openpeeps.com/',
    ),
    (
      icon: AboutIcons.illustrations,
      label: 'MASCOT',
      value: 'Sparky, drawn in code for this app (no third-party art)',
      url: null,
    ),
    (
      icon: AboutIcons.icons,
      label: 'ICONS',
      value: 'Hugeicons',
      url: 'https://hugeicons.com/',
    ),
    (
      icon: AboutIcons.icons,
      label: 'ICONS',
      value: 'Iconify icon sets',
      url: 'https://iconify.design/',
    ),
    (
      icon: AboutIcons.fonts,
      label: 'FONTS',
      value: 'Space Grotesk & Space Mono (SIL Open Font License)',
      url: 'https://openfontlicense.org/',
    ),
    (
      icon: AboutIcons.flutter,
      label: 'BUILT WITH',
      value: 'Flutter',
      url: 'https://flutter.dev/',
    ),
  ];

  // Actions.
  static const licenses = 'OPEN-SOURCE LICENSES';
  static const feedback = 'SEND FEEDBACK';
  static const feedbackEmail = 'nkumawat8956@gmail.com';
  static String feedbackSubject(String version) =>
      'sparky feedback (v$version)';
  static const noMailApp = 'No mail app found. Email address copied.';
  static const legalese = '© 2026 sparky';

  // Footer: MADE WITH [heart] — © 2026 sparky.
  static const madeWith = 'MADE WITH';
  static const footerRest = '— © 2026 sparky';
  static const love = 'love';

  // Extra entries shown on the licenses page.
  static const licensePeeps = 'Open Peeps (illustrations)';
  static const licensePeepsText =
      'Open Peeps by Pablo Stanley, https://www.openpeeps.com/. '
      'Released under CC0 1.0 Universal (public domain dedication).';
  static const licenseFonts = 'Space Grotesk, Space Mono (fonts)';
  static const licenseFontsText =
      'Space Grotesk and Space Mono are licensed under the SIL Open Font '
      'License, Version 1.1. https://openfontlicense.org/';
}

abstract final class AboutIcons {
  static const entry = AppIcons.about;
  static const version = AppIcons.themeSystem;
  static const whatItDoes = HugeIcons.strokeRoundedSparkles;
  static const privacy = HugeIcons.strokeRoundedShieldKey;
  static const backend = AppIcons.server;
  static const credits = HugeIcons.strokeRoundedAward01;

  static const models = AppIcons.models;
  static const web = AppIcons.web;
  static const knowledge = AppIcons.knowledge;
  static const roundTable = AppIcons.roundTable;
  static const doc = AppIcons.doc;
  static const github = AppIcons.github;
  static const widgets = HugeIcons.strokeRoundedChartLineData01;
  static const attach = AppIcons.attach;
  static const fork = AppIcons.fork;

  static const server = HugeIcons.strokeRoundedCloudServer;
  static const lock = HugeIcons.strokeRoundedSquareLock02;
  static const key = AppIcons.key;
  static const delete = AppIcons.delete;
  static const send = HugeIcons.strokeRoundedSent;

  static const illustrations = HugeIcons.strokeRoundedPaintBrush01;
  static const icons = HugeIcons.strokeRoundedDashboardSquare01;
  static const fonts = HugeIcons.strokeRoundedTextFont;
  static const flutter = AppIcons.code;
  static const open = AppIcons.openExternal;
  static const copy = AppIcons.copy;

  static const licenses = HugeIcons.strokeRoundedLegalDocument01;
  static const feedback = HugeIcons.strokeRoundedMail01;
  static const heart = HugeIcons.strokeRoundedFavourite;
  static const chevron = AppIcons.chevronRight;
}

abstract final class AboutSizes {
  static const illustration = 140.0;
  static const wordmark = AppFontSize.displayLarge;

  /// Wordmark on the licenses page header.
  static const licenseWordmark = AppFontSize.display;
}
