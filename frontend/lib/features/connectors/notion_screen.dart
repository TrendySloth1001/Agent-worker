import 'package:flutter/material.dart';

import '../../core/constants/app_icons.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/constants/connectors.dart';
import '../../core/haptics.dart';
import '../../core/time_ago.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/m3_kit_extras.dart';
import '../../data/connect_api.dart';
import '../../data/connections_api.dart';
import '../connections/connections_controller.dart';
import '../github/widgets/gh_rows.dart';
import '../settings/widgets/settings_kit.dart';
import 'connector_actions.dart';
import 'connector_auth.dart';
import 'connector_brand.dart';
import 'connector_controllers.dart';
import 'widgets/connector_kit.dart';
import 'widgets/connector_reader.dart';

/// Notion: the connected workspace, a search over the pages shared with
/// sparky, and the account actions. Not connected, it explains that the
/// user picks the pages on Notion's own screen.
class NotionScreen extends StatefulWidget {
  const NotionScreen({
    super.key,
    this.connections,
    this.controller,
    this.auth,
    this.now,
  });

  final ConnectionsController? connections;
  final NotionController? controller;
  final ConnectorAuth? auth;
  final DateTime? now;

  @override
  State<NotionScreen> createState() => _NotionScreenState();
}

class _NotionScreenState extends State<NotionScreen> {
  late final ConnectionsController _conn =
      widget.connections ?? ConnectionsController.instance;
  late final NotionController _notion = widget.controller ?? NotionController();
  late final ConnectorAuth _auth = widget.auth ?? ConnectorAuth.instance;
  final _search = TextEditingController();
  String? _loadedFor;

  @override
  void initState() {
    super.initState();
    _conn.addListener(_sync);
    _conn.ensureLoaded();
    _sync();
  }

  @override
  void dispose() {
    _conn.removeListener(_sync);
    if (widget.controller == null) _notion.dispose();
    _search.dispose();
    super.dispose();
  }

  Connection? get _account => _conn.connection(ConnectorIds.notion);

  void _sync() {
    final a = _account;
    if (a == null) {
      if (_loadedFor != null) {
        _loadedFor = null;
        _notion.clear();
      }
      return;
    }
    final key = '${a.login}/${a.workspaceName}';
    if (_loadedFor == key && (_notion.loaded || _notion.loading)) return;
    _loadedFor = key;
    _notion.load();
  }

  Future<void> _refresh() async {
    await _conn.refresh();
    if (_account != null) await _notion.load();
  }

  Future<void> _disconnect() async {
    Haptics.tap();
    final ok = await confirmConnector(
      context,
      title: ConnectorStrings.disconnectTitle(NotionStrings.title),
      body: ConnectorStrings.disconnectBody(NotionStrings.title),
      go: ConnectorStrings.disconnectAction,
    );
    if (!ok) return;
    try {
      await _conn.disconnectApp(ConnectorIds.notion);
      if (mounted) {
        connectorToast(
          context,
          ConnectorStrings.disconnected(NotionStrings.title),
        );
      }
    } catch (_) {
      if (mounted) connectorToast(context, ConnectorStrings.failed);
    }
  }

  Future<void> _reconnect({bool ask = true}) async {
    Haptics.tap();
    if (ask) {
      final ok = await confirmConnector(
        context,
        title: ConnectorStrings.reconnectTitle(NotionStrings.title),
        body: ConnectorStrings.reconnectBody(NotionStrings.title),
        go: ConnectorStrings.reconnectAction,
      );
      if (!ok) return;
    }
    try {
      await _conn.disconnectApp(ConnectorIds.notion);
    } catch (_) {}
    await _auth.connect(ConnectorIds.notion);
  }

  void _open(NotionItem i) {
    Haptics.tap();
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => NotionPageScreen(item: i)));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_conn, _notion, _auth]),
      builder: (context, _) {
        final account = _account;
        final configured = _conn.configured(ConnectorIds.notion);
        return M3Page(
          title: NotionStrings.title,
          onRefresh: _refresh,
          slivers: [
            M3Body(
              children: [
                if (account != null)
                  ..._connected(context, account)
                else if (configured == null && _conn.state == null)
                  const GhSkeletonCells(count: ConnectorSizes.skeletonRows)
                else if (configured == false)
                  const ConnectorNotSetUp()
                else ...[
                  ConnectorPermissionCard(
                    provider: ConnectorIds.notion,
                    brand: ConnectorBrand.notion,
                    title: NotionStrings.permTitle,
                    body: NotionStrings.permBody,
                    vendor: NotionStrings.vendor,
                    auth: _auth,
                    onContinue: () => _auth.connect(ConnectorIds.notion),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const ConnectorPerks(
                    title: NotionStrings.perksTitle,
                    rows: NotionStrings.perks,
                  ),
                ],
              ],
            ),
          ],
        );
      },
    );
  }

  List<Widget> _connected(BuildContext context, Connection a) {
    final reauth = a.needsReauth || _notion.needsReauth;
    final workspace = a.workspaceName;
    final icon = a.workspaceIcon;
    return [
      ConnectorProfileCard(
        avatar: ConnectorAvatar(
          url: a.avatarUrl.isNotEmpty
              ? a.avatarUrl
              : (icon.startsWith('https://') ? icon : ''),
          emoji: icon,
          brand: ConnectorBrand.notion,
        ),
        name: a.accountName.isNotEmpty ? a.accountName : a.login,
        detail: a.accountEmail.isNotEmpty ? a.accountEmail : a.login,
        extra: workspace,
        needsReauth: reauth,
      ),
      const SizedBox(height: AppSpacing.md),
      if (reauth) ...[
        ConnectorPermissionCard(
          provider: ConnectorIds.notion,
          brand: ConnectorBrand.notion,
          title: ConnectorStrings.expiredTitle,
          body: ConnectorStrings.expiredBody,
          vendor: NotionStrings.vendor,
          auth: _auth,
          onContinue: () => _reconnect(ask: false),
        ),
        const SizedBox(height: AppSpacing.lg),
      ] else ...[
        GhPillSearch(
          hint: NotionStrings.search,
          controller: _search,
          onChanged: _notion.setQuery,
        ),
        const SizedBox(height: AppSpacing.md),
        if (_notion.offline || _notion.rateLimited) ...[
          ConnectorBanner(
            icon: _notion.offline
                ? ConnectorIcons.offline
                : ConnectorIcons.warning,
            text: _notion.offline
                ? ConnectorStrings.offline
                : ConnectorStrings.rateLimited,
            action: ConnectorStrings.retry,
            onAction: _notion.load,
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        ..._pages(context),
        const SizedBox(height: AppSpacing.lg),
      ],
      ConnectorAccountGroup(
        brand: ConnectorBrand.notion,
        openLabel: NotionStrings.openInNotion,
        onOpen: () => openExternal(context, ConnectorUrls.notion),
        onReconnect: _reconnect,
        onDisconnect: _disconnect,
      ),
    ];
  }

  List<Widget> _pages(BuildContext context) {
    final items = _notion.items;
    final scheme = Theme.of(context).colorScheme;
    if (items == null) {
      if (_notion.error != null && !_notion.offline) {
        return [
          M3Empty(
            icon: NotionIcons.fallback,
            title: ConnectorStrings.loadFailed,
            hint: _notion.error!.message,
            action: FilledButton.tonal(
              onPressed: _notion.load,
              child: const Text(ConnectorStrings.retry),
            ),
          ),
        ];
      }
      return const [GhSkeletonCells(count: ConnectorSizes.skeletonRows)];
    }
    if (items.isEmpty) {
      final q = _notion.query;
      return [
        M3Empty(
          icon: q.isEmpty ? NotionIcons.fallback : AppIcons.search,
          title: q.isEmpty ? NotionStrings.noPages : NotionStrings.noMatches,
          hint: q.isEmpty
              ? NotionStrings.noPagesHint
              : NotionStrings.noMatchesHint(q),
        ),
      ];
    }
    return [
      M3Group(
        title: _notion.query.isEmpty
            ? NotionStrings.pagesTitle
            : NotionStrings.results,
        children: [
          for (final i in items)
            SettingsTile(
              icon: i.isDatabase ? NotionIcons.database : NotionIcons.page,
              leading: notionRowIcon(i),
              title: i.title.isEmpty ? NotionStrings.untitled : i.title,
              summary: i.lastEdited == null
                  ? null
                  : timeAgo(i.lastEdited!, widget.now ?? DateTime.now()),
              trailing: i.isDatabase
                  ? const M3Tag(NotionStrings.database)
                  : AppIcon(
                      AppIcons.chevronRight,
                      size: AppIconSize.sm,
                      color: scheme.onSurfaceVariant,
                    ),
              onTap: () => _open(i),
            ),
        ],
      ),
    ];
  }
}

Widget notionRowIcon(NotionItem i) => ConnectorRowIcon(
  icon: i.isDatabase ? NotionIcons.database : NotionIcons.page,
  emoji: i.iconIsImage ? null : i.icon,
  imageUrl: i.iconIsImage ? i.icon : null,
);

/// A Notion page (or database rows) read as Markdown.
class NotionPageScreen extends StatelessWidget {
  const NotionPageScreen({super.key, required this.item, this.load});

  final NotionItem item;

  /// Test seam; defaults to the live API.
  final Future<NotionPage> Function()? load;

  @override
  Widget build(BuildContext context) => ConnectorReader(
    provider: ConnectorIds.notion,
    id: item.id,
    initialTitle: item.title,
    openLabel: NotionStrings.openInNotion,
    prompt: NotionStrings.prompt,
    load: () async {
      final p = await (load ?? () => ConnectApi.instance.notionRead(item.id))();
      return ReaderContent(
        title: p.title.isEmpty ? item.title : p.title,
        markdown: p.markdown,
        url: p.url.isEmpty ? item.url : p.url,
        truncated: p.truncated,
      );
    },
  );
}
