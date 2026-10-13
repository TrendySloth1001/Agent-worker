import 'package:flutter/material.dart';

import '../../core/constants/error_copy.dart';
import '../../core/constants/app_icons.dart';
import '../../core/constants/connectors.dart';
import '../../core/haptics.dart';
import '../../core/widgets/m3_kit_extras.dart';
import '../../data/connect_api.dart';
import '../chat/chat_launch.dart';
import '../chat/widgets/open_url.dart';
import '../connections/connections_controller.dart';
import '../settings/widgets/settings_kit.dart';
import 'connector_brand.dart';
import 'widgets/connector_kit.dart';

/// User actions on connected-app items. Every write (Save to Drive / Notion)
/// starts here, from a tap; the chat model can only read.

bool driveConnected() =>
    ConnectionsController.instance.connection(ConnectorIds.drive) != null;
bool notionConnected() =>
    ConnectionsController.instance.connection(ConnectorIds.notion) != null;

/// ASK SPARKY: a new chat whose turns carry the item (read live by the server).
void askAboutItem(
  BuildContext context, {
  required String provider,
  required String id,
  required String title,
  required String prompt,
}) {
  Haptics.tap();
  ChatLaunch.instance.ask(
    prompt,
    apps: [
      {'provider': provider, 'id': id, 'title': title},
    ],
  );
  Navigator.of(context).popUntil((r) => r.isFirst);
}

Future<void> openExternal(BuildContext context, String url) async {
  if (url.isEmpty) return;
  Haptics.tap();
  await visitUrl(context, url);
}

String _errorText(Object e) => e is ConnectException
    ? (e.rateLimited ? ConnectorStrings.rateLimited : friendlyException(e))
    : ConnectorStrings.saveFailed;

/// ADD TO KNOWLEDGE BASE.
Future<void> addItemToKnowledge(
  BuildContext context, {
  required String provider,
  required String id,
}) async {
  Haptics.tap();
  try {
    final api = ConnectApi.instance;
    if (provider == ConnectorIds.notion) {
      await api.notionToKnowledge(id);
    } else {
      await api.driveToKnowledge(id);
    }
    if (context.mounted) connectorToast(context, ConnectorStrings.addedToKb);
  } catch (e) {
    Haptics.error();
    if (context.mounted) connectorToast(context, _errorText(e));
  }
}

/// SAVE TO DRIVE: a sparky doc ([docId]) or Markdown ([title] + [markdown]).
Future<void> saveToDrive(
  BuildContext context, {
  String? docId,
  String? title,
  String? markdown,
}) async {
  Haptics.tap();
  connectorToast(context, ConnectorStrings.saving);
  try {
    await ConnectApi.instance.saveToDrive(
      docId: docId,
      title: title,
      markdown: markdown,
    );
    Haptics.received();
    if (context.mounted) connectorToast(context, DriveStrings.saved);
  } catch (e) {
    Haptics.error();
    if (context.mounted) connectorToast(context, _errorText(e));
  }
}

/// SAVE TO NOTION: asks under which shared page, then creates the page.
Future<void> saveToNotion(
  BuildContext context, {
  String? docId,
  String? title,
  String? markdown,
}) async {
  Haptics.tap();
  final parent = await pickNotionParent(context);
  if (parent == null || !context.mounted) return;
  connectorToast(context, ConnectorStrings.saving);
  try {
    await ConnectApi.instance.saveToNotion(
      parentId: parent.id,
      docId: docId,
      title: title,
      markdown: markdown,
    );
    Haptics.received();
    if (context.mounted) connectorToast(context, NotionStrings.saved);
  } catch (e) {
    Haptics.error();
    if (context.mounted) connectorToast(context, _errorText(e));
  }
}

/// The shared Notion pages a new page can go under.
Future<NotionItem?> pickNotionParent(BuildContext context) {
  return showM3Sheet<NotionItem>(
    context,
    builder: (sheet) => FutureBuilder<List<NotionItem>>(
      future: ConnectApi.instance.notionSearch(kind: 'page'),
      builder: (context, snap) {
        final scheme = Theme.of(context).colorScheme;
        final Widget body;
        if (snap.connectionState != ConnectionState.done) {
          body = const Padding(
            padding: EdgeInsets.all(ConnectorSizes.rowIcon),
            child: Center(child: CircularProgressIndicator()),
          );
        } else if (snap.hasError || (snap.data?.isEmpty ?? true)) {
          body = Padding(
            padding: const EdgeInsets.all(ConnectorSizes.rowIcon),
            child: Text(
              snap.hasError ? _errorText(snap.error!) : NotionStrings.noParents,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium!.copyWith(color: scheme.onSurfaceVariant),
            ),
          );
        } else {
          body = Flexible(
            child: SingleChildScrollView(
              child: M3Group(
                children: [
                  for (final p in snap.data!)
                    SettingsTile(
                      icon: NotionIcons.page,
                      leading: ConnectorRowIcon(
                        icon: NotionIcons.page,
                        emoji: p.iconIsImage ? null : p.icon,
                      ),
                      title: p.title.isEmpty ? NotionStrings.untitled : p.title,
                      onTap: () => Navigator.pop(sheet, p),
                    ),
                ],
              ),
            ),
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [const M3SheetTitle(NotionStrings.pickParent), body],
        );
      },
    ),
  );
}

/// Save to Drive / Notion share-sheet rows for the connected apps.
List<(T, AppIconData, String)> connectorSaveOptions<T>({
  required T drive,
  required T notion,
  bool includeNotion = true,
}) => [
  if (driveConnected())
    (drive, ConnectorBrand.drive.logo, DriveStrings.saveToDrive),
  if (includeNotion && notionConnected())
    (notion, ConnectorBrand.notion.logo, NotionStrings.saveToNotion),
];
