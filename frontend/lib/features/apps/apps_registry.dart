import 'package:flutter/material.dart';

import '../../core/constants/app_icons.dart';
import '../../core/constants/apps.dart';
import '../../core/constants/memory.dart';
import '../knowledge/knowledge_screen.dart';
import '../memory/memory_screen.dart';
import '../github/github_screen.dart';

/// Where an app sits on the hub.
enum AppSection {
  /// An external account that can be linked (GitHub).
  account,

  /// A feature of Sparky that lives here too (knowledge base, memory).
  builtIn,

  /// Announced, not usable yet.
  soon,
}

/// An Iconify brand mark with a Hugeicons fallback while it loads.
class AppBrand {
  const AppBrand(this.name, this.fallback, {this.set = AppsIcons.brandSet});

  final String set;
  final String name;
  final AppIconData fallback;
}

/// One entry of the Apps hub. Adding a connector later is one entry in
/// [AppsRegistry.all]: give it an id, a name, a mark and a section; set
/// [open] once it is usable.
class AppConnector {
  const AppConnector({
    required this.id,
    required this.name,
    required this.blurb,
    required this.section,
    this.brand,
    this.icon,
    this.open,
  }) : assert(brand != null || icon != null);

  final String id;
  final String name;

  /// One line under the name when there is no live status.
  final String blurb;
  final AppSection section;

  /// Brand logo (external services).
  final AppBrand? brand;

  /// Plain icon (Sparky's own features).
  final AppIconData? icon;

  /// Opens the app's screen; null while it is [AppSection.soon].
  final void Function(BuildContext context)? open;

  bool get isSoon => section == AppSection.soon;
}

void _push(BuildContext context, Widget screen) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));

/// Every connector the hub lists, in display order per section.
abstract final class AppsRegistry {
  static final all = <AppConnector>[
    AppConnector(
      id: AppIds.github,
      name: AppsStrings.github,
      blurb: AppsStrings.githubBlurb,
      section: AppSection.account,
      brand: const AppBrand(AppsIcons.github, AppsIcons.githubFallback),
      open: (c) => _push(c, const GithubScreen()),
    ),
    AppConnector(
      id: AppIds.knowledge,
      name: AppsStrings.knowledge,
      blurb: AppsStrings.knowledgeBlurb,
      section: AppSection.builtIn,
      icon: AppIcons.knowledge,
      open: (c) => _push(c, const KnowledgeScreen()),
    ),
    AppConnector(
      id: AppIds.memory,
      name: AppsStrings.memory,
      blurb: AppsStrings.memoryBlurb,
      section: AppSection.builtIn,
      icon: MemoryIcons.section,
      open: (c) => _push(c, const MemoryScreen()),
    ),
    const AppConnector(
      id: AppIds.googleDrive,
      name: AppsStrings.googleDrive,
      blurb: AppsStrings.googleDriveBlurb,
      section: AppSection.soon,
      brand: AppBrand(AppsIcons.googleDrive, AppsIcons.googleDriveFallback),
    ),
    const AppConnector(
      id: AppIds.googlePhotos,
      name: AppsStrings.googlePhotos,
      blurb: AppsStrings.googlePhotosBlurb,
      section: AppSection.soon,
      brand: AppBrand(AppsIcons.googlePhotos, AppsIcons.photosFallback),
    ),
    const AppConnector(
      id: AppIds.notion,
      name: AppsStrings.notion,
      blurb: AppsStrings.notionBlurb,
      section: AppSection.soon,
      brand: AppBrand(AppsIcons.notion, AppsIcons.notionFallback),
    ),
    const AppConnector(
      id: AppIds.gmail,
      name: AppsStrings.gmail,
      blurb: AppsStrings.gmailBlurb,
      section: AppSection.soon,
      brand: AppBrand(AppsIcons.gmail, AppsIcons.mailFallback),
    ),
    const AppConnector(
      id: AppIds.calendar,
      name: AppsStrings.calendar,
      blurb: AppsStrings.calendarBlurb,
      section: AppSection.soon,
      brand: AppBrand(AppsIcons.calendar, AppsIcons.calendarFallback),
    ),
    const AppConnector(
      id: AppIds.slack,
      name: AppsStrings.slack,
      blurb: AppsStrings.slackBlurb,
      section: AppSection.soon,
      brand: AppBrand(AppsIcons.slack, AppsIcons.slackFallback),
    ),
  ];

  static List<AppConnector> inSection(AppSection s) => [
    for (final a in all)
      if (a.section == s) a,
  ];

  static AppConnector? byId(String id) =>
      all.where((a) => a.id == id).firstOrNull;
}
