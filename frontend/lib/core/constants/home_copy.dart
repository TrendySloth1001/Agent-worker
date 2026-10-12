import 'package:hugeicons/hugeicons.dart';

import 'app_icons.dart';

/// New-chat home: greeting, starter cards, capability chips, recent chats.

/// What kind of starter a card is; sets its icon and tiny label.
enum StarterKind {
  learn(HomeStrings.learn, HugeIcons.strokeRoundedMortarboard01),
  build(HomeStrings.build, HugeIcons.strokeRoundedCodeSquare),
  compare(HomeStrings.compare, HugeIcons.strokeRoundedGitCompare),
  write(HomeStrings.write, HugeIcons.strokeRoundedPencilEdit02),
  plan(HomeStrings.plan, HugeIcons.strokeRoundedCalendar01);

  const StarterKind(this.label, this.icon);
  final String label;
  final AppIconData icon;
}

/// A feature the chips teach and prime in the composer.
enum HomeCapability {
  doc(HomeStrings.capDoc, HomeStrings.hintDoc),
  roundTable(HomeStrings.capTable, HomeStrings.hintTable),
  web(HomeStrings.capWeb, HomeStrings.hintWeb),
  knowledge(HomeStrings.capKnowledge, HomeStrings.hintKnowledge),
  github(HomeStrings.capGithub, HomeStrings.hintGithub);

  const HomeCapability(this.label, this.hint);
  final String label;

  /// Composer placeholder while this is primed.
  final String hint;

  AppIconData get icon => switch (this) {
    doc => AppIcons.doc,
    roundTable => AppIcons.roundTable,
    web => AppIcons.web,
    knowledge => AppIcons.knowledge,
    github => AppIcons.github,
  };
}

/// One starter card. [prompt] is what tapping sends.
class Starter {
  const Starter(this.kind, this.title, this.prompt, [this.hint]);
  final StarterKind kind;
  final String title;
  final String prompt;

  /// One line under the title; personalised starters have none.
  final String? hint;
}

abstract final class HomeStrings {
  static const learn = 'LEARN';
  static const build = 'BUILD';
  static const compare = 'COMPARE';
  static const write = 'WRITE';
  static const plan = 'PLAN';

  static const capDoc = 'Write a doc';
  static const capTable = 'Round table';
  static const capWeb = 'Search the web';
  static const capKnowledge = 'Knowledge base';
  static const capGithub = 'GitHub';

  static const hintDoc = 'Describe the document to write…';
  static const hintTable = 'Ask something worth debating…';
  static const hintWeb = 'Ask about anything current…';
  static const hintKnowledge = 'Ask your documents…';
  static const hintGithub = 'Ask about a repo, PR or issue…';
  static const githubDraft = 'On GitHub, ';

  static const morning = 'Good morning';
  static const afternoon = 'Good afternoon';
  static const evening = 'Good evening';
  static const night = 'Still up';

  static const sublines = [
    'What should we work on?',
    'What is on your mind?',
    'Where shall we start?',
    'Ready when you are.',
  ];

  static const tryAsking = 'TRY ASKING';
  static const shuffle = 'Show different suggestions';
  static const continueTitle = 'CONTINUE';
  static const untitled = 'Untitled chat';
  static const messageOne = '1 message';
  static String messages(int n) => n == 1 ? messageOne : '$n messages';
  static String capSemantics(String label, bool on) =>
      '$label, ${on ? 'on' : 'off'}';
  static String openChat(String title) => 'Open chat: $title';
  static String starterSemantics(String kind, String title, String? hint) =>
      hint == null ? '$kind. $title' : '$kind. $title. $hint';
  static const longPressHint = 'Edit before sending';
  static String greeting(String hello, String? name) =>
      name == null || name.isEmpty ? hello : '$hello, $name';
}

abstract final class HomeSizes {
  static const mascot = 56.0;
  static const mascotCompact = 40.0;
  static const greetingSize = 28.0;
  static const greetingRoomy = 32.0;
  static const mascotRoomy = 72.0;
  static const roomyExtra = 84.0;
  static const greetingCompact = 22.0;
  static const sublineSize = 16.0;

  static const cardHeight = 112.0;
  static const cardCompactWidth = 188.0;
  static const cardCompactHeight = 108.0;
  static const cardIcon = 32.0;
  static const cardPadding = 12.0;
  static const cardGap = 8.0;

  static const chipHeight = 40.0;
  static const hit = 48.0;

  static const recentRow = 60.0;
  static const recentIcon = 36.0;
  static const bigRadius = 20.0;
  static const smallRadius = 6.0;

  /// Estimated heights used to decide which sections fit.
  static const headerFull = 84.0;
  static const headerCompact = 48.0;
  static const labelRow = 32.0;
  static const gridBlock = labelRow + 2 * cardHeight + cardGap;
  static const rowBlock = labelRow + cardCompactHeight;
  static const chipsBlock = hit;
  static const recentBlock = 28.0 + recentRow;
  static const sectionGap = 16.0;

  /// Entrance motion.
  static const rise = 10.0;
  static const staggerMs = 70;
  static const entrance = Duration(milliseconds: 650);
  static const poolShown = 4;
  static const recentFetch = 3;
}

abstract final class HomeIcons {
  static const shuffle = HugeIcons.strokeRoundedShuffle;
  static const recent = AppIcons.chat;
  static const next = AppIcons.chevronRight;
}

/// Built-in starters, used until (and filled in after) the personalised ones.
const fallbackStarters = [
  Starter(
    StarterKind.learn,
    'Explain a concept',
    'Explain how large language models work, step by step',
    'Any topic, any depth',
  ),
  Starter(
    StarterKind.build,
    'Debug an error',
    'Help me debug an error I keep running into',
    'Find the cause, not a patch',
  ),
  Starter(
    StarterKind.compare,
    'Compare options',
    'Compare PostgreSQL and MongoDB for a chat app',
    'Pros, cons and a verdict',
  ),
  Starter(
    StarterKind.write,
    'Draft an email',
    'Help me write a clear, friendly follow-up email',
    'Polished and on tone',
  ),
  Starter(
    StarterKind.plan,
    'Plan my day',
    'Help me plan a focused day around three priorities',
    'Priorities and time blocks',
  ),
  Starter(
    StarterKind.build,
    'Review my code',
    'Review my code for bugs and clarity',
    'Bugs, smells and quick wins',
  ),
  Starter(
    StarterKind.learn,
    'Teach me something',
    'Teach me something surprising I can use this week',
    'A quick, useful lesson',
  ),
  Starter(
    StarterKind.write,
    'Summarise a topic',
    'Give me a crisp one-page summary of how HTTPS works',
    'Short, structured, sourced',
  ),
];
