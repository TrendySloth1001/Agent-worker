import 'package:flutter/material.dart';

import '../../core/constants/app_icons.dart';
import '../../core/constants/apps.dart';
import '../../core/constants/memory.dart';
import '../knowledge/knowledge_screen.dart';
import '../memory/memory_screen.dart';
import '../connectors/drive_screen.dart';
import '../connectors/notion_screen.dart';
import '../github/github_screen.dart';

/// Where an app sits on the hub.
enum AppSection {
  /// An external account that can be linked (GitHub, Google Drive, Notion).
  account,

  /// A feature of Sparky that lives here too (knowledge base, memory).
  builtIn,

  /// Announced, not usable yet.
  soon,
}

/// A connected app's official logo (bundled, see `BrandLogos`).
class AppBrand {
  const AppBrand(this.logo);

  final AppIconData logo;
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
    this.badge,
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

  /// Small tag beside the name (BETA while the provider reviews our access).
  final String? badge;

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
      brand: const AppBrand(AppsIcons.github),
      open: (c) => _push(c, const GithubScreen()),
    ),
    AppConnector(
      id: AppIds.googleDrive,
      name: AppsStrings.googleDrive,
      blurb: AppsStrings.googleDriveBlurb,
      section: AppSection.account,
      brand: const AppBrand(AppsIcons.googleDrive),
      badge: AppsStrings.beta,
      open: (c) => _push(c, const DriveScreen()),
    ),
    AppConnector(
      id: AppIds.notion,
      name: AppsStrings.notion,
      blurb: AppsStrings.notionBlurb,
      section: AppSection.account,
      brand: const AppBrand(AppsIcons.notion),
      open: (c) => _push(c, const NotionScreen()),
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
      id: AppIds.googlePhotos,
      name: AppsStrings.googlePhotos,
      blurb: AppsStrings.googlePhotosBlurb,
      section: AppSection.soon,
      brand: AppBrand(AppsIcons.googlePhotos),
    ),
    const AppConnector(
      id: AppIds.gmail,
      name: AppsStrings.gmail,
      blurb: AppsStrings.gmailBlurb,
      section: AppSection.soon,
      brand: AppBrand(AppsIcons.gmail),
    ),
    const AppConnector(
      id: AppIds.calendar,
      name: AppsStrings.calendar,
      blurb: AppsStrings.calendarBlurb,
      section: AppSection.soon,
      brand: AppBrand(AppsIcons.calendar),
    ),
    const AppConnector(
      id: AppIds.slack,
      name: AppsStrings.slack,
      blurb: AppsStrings.slackBlurb,
      section: AppSection.soon,
      brand: AppBrand(AppsIcons.slack),
    ),
  ];

  static List<AppConnector> inSection(AppSection s) => [
    for (final a in all)
      if (a.section == s) a,
  ];

  static AppConnector? byId(String id) =>
      all.where((a) => a.id == id).firstOrNull;
}
