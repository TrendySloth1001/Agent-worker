import 'package:hugeicons/hugeicons.dart';

import 'app_icons.dart';
import 'app_sizes.dart';
import 'brand_logos.dart';

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
  static String versionShort(String version, String build) =>
      '$version ($build)';

  /// What people who are not the owner see under the logo.

  // Hero strip (mono caps).
  static String heroVersion(String version) => 'V$version';
  static const heroLatest = 'UP TO DATE';
  static const heroUpdate = 'UPDATE READY';

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
      icon: AboutIcons.peeps,
      label: 'ILLUSTRATIONS',
      value: 'Open Peeps by Pablo Stanley (CC0)',
      url: 'https://www.openpeeps.com/',
    ),
    (
      icon: AboutIcons.illustrations,
      label: 'ILLUSTRATIONS',
      value: 'Open Doodles by Pablo Stanley (CC0)',
      url: 'https://www.opendoodles.com/',
    ),
    (
      icon: AboutIcons.icons,
      label: 'ICONS',
      value: 'Hugeicons',
      url: 'https://hugeicons.com/',
    ),
    (
      icon: AboutIcons.iconify,
      label: 'ICONS',
      value: 'Iconify icon sets',
      url: 'https://iconify.design/',
    ),
    (
      icon: AboutIcons.logos,
      label: 'BRAND LOGOS',
      value:
          'SVG Logos & Simple Icons (CC0), theSVG, VSCode Icons (MIT), '
          'selfh.st/icons (CC BY 4.0). Logos are trademarks of their owners.',
      url: 'https://github.com/gilbarbara/logos',
    ),
    (
      icon: AboutIcons.modelLogos,
      label: 'MODEL LOGOS',
      value:
          'LobeHub Icons (MIT). Logos are trademarks of their owners and '
          'only identify who made each model.',
      url: 'https://github.com/lobehub/lobe-icons',
    ),
    (
      icon: AboutIcons.fonts,
      label: 'FONTS',
      value: 'Space Grotesk & Space Mono (SIL Open Font License)',
      url: 'https://openfontlicense.org/',
    ),
    (
      icon: AboutIcons.geoip,
      label: 'LOCATION',
      value: 'IP geolocation by DB-IP (CC BY 4.0)',
      url: 'https://db-ip.com/',
    ),
    (
      icon: AboutIcons.flutter,
      label: 'BUILT WITH',
      value: 'Flutter',
      url: 'https://flutter.dev/',
    ),
  ];

  // Developer section (owner only).
  static const developer = 'Developer';
  static const developerHelp = 'Server address, status and build';
  static const buildTitle = 'Build';
  static String buildLine(String version, String build, String platform) =>
      '$version ($build) · $platform';
  static const telemetry = 'Telemetry & analytics';
  static const telemetryHelp = 'Model calls, tokens and latency';

  // Legal pages, served by the sparky server.
  static const privacyPolicy = 'Privacy policy';
  static const terms = 'Terms of service';
  static const openFailed = 'Could not open the page.';

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
  static const licenseDoodles = 'Open Doodles (illustrations)';
  static const licenseDoodlesText =
      'Open Doodles by Pablo Stanley, https://www.opendoodles.com/. '
      'Released under CC0 1.0 Universal (public domain dedication).';
  static const licenseLobeIcons = 'LobeHub Icons (model logos)';
  static const licenseLobeIconsText =
      'LobeHub Icons, https://github.com/lobehub/lobe-icons. '
      'Logos are trademarks of their respective owners.\n\n'
      'MIT License\n\nCopyright (c) 2023 LobeHub\n\n'
      'Permission is hereby granted, free of charge, to any person obtaining '
      'a copy of this software and associated documentation files (the '
      '"Software"), to deal in the Software without restriction, including '
      'without limitation the rights to use, copy, modify, merge, publish, '
      'distribute, sublicense, and/or sell copies of the Software, and to '
      'permit persons to whom the Software is furnished to do so, subject to '
      'the following conditions:\n\n'
      'The above copyright notice and this permission notice shall be '
      'included in all copies or substantial portions of the Software.\n\n'
      'THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, '
      'EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF '
      'MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND '
      'NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE '
      'LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION '
      'OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION '
      'WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.';
  static const licenseIcons = 'Hugeicons, Iconify (icons)';
  static const licenseIconsText =
      'Hugeicons, https://hugeicons.com/. Iconify icon sets, '
      'https://iconify.design/.';
  static const licenseLogos = 'Brand logos';
  static const licenseLogosText =
      'SVG Logos and Simple Icons (CC0), theSVG, VSCode Icons (MIT) and '
      'selfh.st/icons (CC BY 4.0, https://selfh.st/icons/). Logos are '
      'trademarks of their respective owners.';
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
  static const icons = HugeIcons.strokeRoundedStarSquare;
  static const fonts = HugeIcons.strokeRoundedTextFont;
  static const geoip = HugeIcons.strokeRoundedLocation05;
  static const flutter = BrandLogos.flutter;
  static const logos = HugeIcons.strokeRoundedCheckmarkBadge01;
  static const peeps = HugeIcons.strokeRoundedUserMultiple;
  static const iconify = HugeIcons.strokeRoundedShapes;
  static const modelLogos = HugeIcons.strokeRoundedCube;
  static const open = AppIcons.openExternal;
  static const copy = AppIcons.copy;

  static const licenses = HugeIcons.strokeRoundedLegalDocument01;
  static const privacyPolicy = HugeIcons.strokeRoundedShieldUser;
  static const terms = HugeIcons.strokeRoundedAgreement01;
  static const build = HugeIcons.strokeRoundedWrench01;
  static const telemetry = HugeIcons.strokeRoundedActivity01;
  static const feedback = HugeIcons.strokeRoundedMail01;
  static const heart = HugeIcons.strokeRoundedFavourite;
  static const chevron = AppIcons.chevronRight;
}

abstract final class AboutSizes {
  static const illustration = 140.0;

  /// The dotted art area of the hero; the grid fades out over [heroFade].
  static const heroArt = 176.0;
  static const heroFade = [0.25, 1.0];
  static const statusDot = 6.0;
  static const wordmark = AppFontSize.displayLarge;

  /// Wordmark on the licenses page header.
  static const licenseWordmark = AppFontSize.display;
}
