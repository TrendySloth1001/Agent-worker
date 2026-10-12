import 'package:hugeicons/hugeicons.dart';

/// One release in "What's new" (About → What's new). Newest first; add an
/// entry with every version bump in pubspec.yaml.
typedef Release = ({String version, String date, List<String> changes});

abstract final class ChangelogStrings {
  static const entry = "What's new";
  static const title = "What's new";
  static const latest = 'LATEST';
  static String heading(String version, String date) => '$version · $date';
}

abstract final class ChangelogIcons {
  static const entry = HugeIcons.strokeRoundedSparkles;
  static const bullet = HugeIcons.strokeRoundedCheckmarkCircle02;
}

abstract final class Changelog {
  static const releases = <Release>[
    (
      version: '1.4.1',
      date: '13 Oct 2026',
      changes: [
        'A short tour for new accounts. Replay it from About → Take the tour.',
        'The assistant has a new animated dot backdrop in red.',
        'The assistant can now search the web, use your knowledge base, run Round Table and write docs, just like chat.',
        'Attach photos, videos and documents from the assistant.',
        'Cleaner chat header: three matching round buttons.',
        'Terms of Service and Privacy Policy, linked from sign-in.',
      ],
    ),
    (
      version: '1.3.1',
      date: '13 Oct 2026',
      changes: [
        'Real logos everywhere: Google Drive, Notion, GitHub, model providers and file types.',
        'Coming-soon apps (Photos, Gmail, Calendar, Slack) are listed in Apps.',
      ],
    ),
    (
      version: '1.3.0',
      date: '13 Oct 2026',
      changes: [
        'sparky as your phone assistant: hold the power button to ask from any app.',
        'Share your screen with sparky in one tap.',
        'Select several chats to archive, pin or delete, or delete all chats in Settings.',
        'Redesigned sign-in and create-account screens.',
      ],
    ),
    (
      version: '1.2.0',
      date: '13 Oct 2026',
      changes: [
        'Connect Google Drive and Notion. sparky only sees the files and pages you share.',
        'Smarter memory: remembers your name, nickname, city and preferences, and updates them in place.',
        'GitHub sign-in only asks for your name and email.',
      ],
    ),
    (
      version: '1.1.2',
      date: '12 Oct 2026',
      changes: [
        'A new greeting and illustration each time you open a new chat.',
        'GitHub permission card in plain language.',
        'Fixed a blank screen after signing in with GitHub.',
      ],
    ),
    (
      version: '1.1.1',
      date: '12 Oct 2026',
      changes: [
        'Pull requests, issues, commits and activity open inside the app, with Ask Sparky everywhere.',
        'Review, comment, merge and manage labels from the app when you have access.',
      ],
    ),
    (
      version: '1.1.0',
      date: '12 Oct 2026',
      changes: [
        'Apps hub and a full GitHub screen.',
        'New settings, telemetry, knowledge base and sidebar design.',
        'Voice input, smart toggles for web, knowledge base and docs.',
      ],
    ),
  ];
}
