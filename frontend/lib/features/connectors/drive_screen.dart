import 'package:flutter/material.dart';

import '../../core/constants/app_sizes.dart';
import '../../core/constants/connectors.dart';
import '../../core/haptics.dart';
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
import 'drive_browse_screen.dart';
import 'widgets/connector_kit.dart';

/// Google Drive with drive.file: who is connected, the files sparky can see
/// (picked in Google's picker or saved by sparky), and the account actions.
class DriveScreen extends StatefulWidget {
  const DriveScreen({
    super.key,
    this.connections,
    this.controller,
    this.auth,
    this.now,
  });

  /// Test seams.
  final ConnectionsController? connections;
  final DriveController? controller;
  final ConnectorAuth? auth;
  final DateTime? now;

  @override
  State<DriveScreen> createState() => _DriveScreenState();
}

class _DriveScreenState extends State<DriveScreen> {
  late final ConnectionsController _conn =
      widget.connections ?? ConnectionsController.instance;
  late final DriveController _drive = widget.controller ?? DriveController();
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
    if (widget.controller == null) _drive.dispose();
    super.dispose();
  }

  Connection? get _account => _conn.connection(ConnectorIds.drive);

  /// Loads the files once connected (again for another account).
  void _sync() {
    final a = _account;
    if (a == null) {
      if (_loadedFor != null) {
        _loadedFor = null;
        _drive.clear();
      }
      return;
    }
    if (_loadedFor == a.login && (_drive.loaded || _drive.loading)) return;
    _loadedFor = a.login;
    _drive.load();
  }

  Future<void> _refresh() async {
    await _conn.refresh();
    if (_account != null) await _drive.load();
  }

  Future<void> _disconnect() async {
    Haptics.tap();
    final ok = await confirmConnector(
      context,
      title: ConnectorStrings.disconnectTitle(DriveStrings.title),
      body: ConnectorStrings.disconnectBody(DriveStrings.title),
      go: ConnectorStrings.disconnectAction,
    );
    if (!ok) return;
    try {
      await _conn.disconnectApp(ConnectorIds.drive);
      if (mounted) {
        connectorToast(
          context,
          ConnectorStrings.disconnected(DriveStrings.title),
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
        title: ConnectorStrings.reconnectTitle(DriveStrings.title),
        body: ConnectorStrings.reconnectBody(DriveStrings.title),
        go: ConnectorStrings.reconnectAction,
      );
      if (!ok) return;
    }
    try {
      await _conn.disconnectApp(ConnectorIds.drive);
    } catch (_) {}
    await _auth.connect(ConnectorIds.drive);
  }

  void _browse() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => DriveBrowseScreen(controller: _drive, now: widget.now),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_conn, _drive, _auth]),
      builder: (context, _) {
        final account = _account;
        final configured = _conn.configured(ConnectorIds.drive);
        return M3Page(
          title: DriveStrings.title,
          onRefresh: _refresh,
          slivers: [
            M3Body(
              children: [
                const _BetaNote(),
                const SizedBox(height: AppSpacing.md),
                if (account != null)
                  ..._connected(context, account)
                else if (configured == null && _conn.state == null)
                  const GhSkeletonCells(count: ConnectorSizes.skeletonRows)
                else if (configured == false)
                  const ConnectorNotSetUp()
                else
                  ..._disconnected(),
              ],
            ),
          ],
        );
      },
    );
  }

  List<Widget> _disconnected() => [
    ConnectorPermissionCard(
      provider: ConnectorIds.drive,
      brand: ConnectorBrand.drive,
      title: DriveStrings.permTitle,
      body: DriveStrings.permBody,
      vendor: DriveStrings.vendor,
      auth: _auth,
      onContinue: () => _auth.connect(ConnectorIds.drive),
    ),
    const SizedBox(height: AppSpacing.lg),
    const ConnectorPerks(
      title: DriveStrings.perksTitle,
      rows: DriveStrings.perks,
    ),
  ];

  List<Widget> _connected(BuildContext context, Connection a) {
    final reauth = a.needsReauth || _drive.needsReauth;
    final picking = _auth.busyFor(ConnectorIds.drive, ConnectorFlow.picker);
    final files = _drive.items;
    final recent = (files ?? const <DriveFile>[])
        .take(ConnectorSizes.drivePreviewCount)
        .toList();
    return [
      ConnectorProfileCard(
        avatar: ConnectorAvatar(url: a.avatarUrl, brand: ConnectorBrand.drive),
        name: a.accountName.isNotEmpty ? a.accountName : a.login,
        detail: a.accountEmail.isNotEmpty ? a.accountEmail : a.login,
        needsReauth: reauth,
      ),
      const SizedBox(height: AppSpacing.md),
      if (reauth)
        ConnectorPermissionCard(
          provider: ConnectorIds.drive,
          brand: ConnectorBrand.drive,
          title: ConnectorStrings.expiredTitle,
          body: ConnectorStrings.expiredBody,
          vendor: DriveStrings.vendor,
          auth: _auth,
          onContinue: () => _reconnect(ask: false),
        )
      else ...[
        M3Group(
          children: [
            ConnectorSummaryTile(
              icon: DriveIcons.fallback,
              title: DriveStrings.filesTitle,
              count: files == null
                  ? null
                  : ConnectorStrings.count(files.length),
              onTap: _browse,
            ),
            SettingsTile(
              icon: DriveIcons.pick,
              title: DriveStrings.pick,
              summary: DriveStrings.pickHint,
              trailing: picking
                  ? const SizedBox.square(
                      dimension: AppIconSize.md,
                      child: CircularProgressIndicator(
                        strokeWidth: AppBorder.thick,
                      ),
                    )
                  : null,
              onTap: picking
                  ? null
                  : () {
                      Haptics.tap();
                      _auth.pickDriveFiles();
                    },
            ),
          ],
        ),
        if (_drive.offline || _drive.rateLimited) ...[
          const SizedBox(height: AppSpacing.md),
          ConnectorBanner(
            icon: _drive.offline
                ? ConnectorIcons.offline
                : ConnectorIcons.warning,
            text: _drive.offline
                ? ConnectorStrings.offline
                : ConnectorStrings.rateLimited,
            action: ConnectorStrings.retry,
            onAction: _drive.load,
          ),
        ],
        if (recent.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          M3Group(
            title: DriveStrings.recent,
            children: [
              for (final f in recent) DriveFileTile(file: f, now: widget.now),
            ],
          ),
        ],
      ],
      const SizedBox(height: AppSpacing.lg),
      ConnectorAccountGroup(
        brand: ConnectorBrand.drive,
        openLabel: DriveStrings.openInDrive,
        onOpen: () => openExternal(context, ConnectorUrls.drive),
        onReconnect: _reconnect,
        onDisconnect: _disconnect,
      ),
    ];
  }
}

/// Google's review of sparky's access is still going: a BETA tag and why the
/// "unverified app" screen may show.
class _BetaNote extends StatelessWidget {
  const _BetaNote();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const M3Tag(DriveStrings.beta),
      const SizedBox(height: AppSpacing.sm),
      ConnectorBanner(icon: DriveIcons.betaNote, text: DriveStrings.betaNote),
    ],
  );
}
