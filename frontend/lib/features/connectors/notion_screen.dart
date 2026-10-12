import 'package:flutter/material.dart';

import '../../core/constants/app_sizes.dart';
import '../../core/constants/connectors.dart';
import '../../core/haptics.dart';
import '../../core/widgets/m3_kit_extras.dart';
import '../../data/connect_api.dart';
import '../../data/connections_api.dart';
import '../connections/connections_controller.dart';
import '../github/widgets/gh_rows.dart';
import 'connector_actions.dart';
import 'connector_auth.dart';
import 'connector_brand.dart';
import 'connector_controllers.dart';
import 'notion_browse_screen.dart';
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

  void _browse() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => NotionBrowseScreen(controller: _notion, now: widget.now),
    ),
  );

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
    final icon = a.workspaceIcon;
    final items = _notion.items;
    final recent = (items ?? const <NotionItem>[])
        .take(ConnectorSizes.previewCount)
        .toList();
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
        extra: a.workspaceName,
        needsReauth: reauth,
      ),
      const SizedBox(height: AppSpacing.md),
      if (reauth)
        ConnectorPermissionCard(
          provider: ConnectorIds.notion,
          brand: ConnectorBrand.notion,
          title: ConnectorStrings.expiredTitle,
          body: ConnectorStrings.expiredBody,
          vendor: NotionStrings.vendor,
          auth: _auth,
          onContinue: () => _reconnect(ask: false),
        )
      else ...[
        M3Group(
          children: [
            ConnectorSummaryTile(
              icon: NotionIcons.page,
              title: NotionStrings.pagesSummary,
              count: items == null
                  ? null
                  : ConnectorStrings.count(
                      items.length,
                      more: items.length >= ConnectorSizes.searchPage,
                    ),
              onTap: _browse,
            ),
          ],
        ),
        if (_notion.offline || _notion.rateLimited) ...[
          const SizedBox(height: AppSpacing.md),
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
        ],
        if (recent.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          M3Group(
            title: NotionStrings.recent,
            children: [
              for (final i in recent) NotionItemTile(item: i, now: widget.now),
            ],
          ),
        ],
      ],
      const SizedBox(height: AppSpacing.lg),
      ConnectorAccountGroup(
        brand: ConnectorBrand.notion,
        openLabel: NotionStrings.openInNotion,
        onOpen: () => openExternal(context, ConnectorUrls.notion),
        onReconnect: _reconnect,
        onDisconnect: _disconnect,
      ),
    ];
  }
}

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
