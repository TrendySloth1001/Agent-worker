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
import 'drive_file_screen.dart';
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
    if (widget.controller == null) _drive.dispose();
    _search.dispose();
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

  void _open(DriveFile f) {
    Haptics.tap();
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => DriveFileScreen(file: f)));
  }

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
      else
        M3Group(
          children: [
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
      if (!reauth && (_drive.offline || _drive.rateLimited)) ...[
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
      const SizedBox(height: AppSpacing.lg),
      ..._files(context),
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

  List<Widget> _files(BuildContext context) {
    final files = _drive.items;
    final scheme = Theme.of(context).colorScheme;
    if (files == null) {
      if (_drive.error != null && !_drive.offline && !_drive.needsReauth) {
        return [
          M3Empty(
            icon: DriveIcons.fallback,
            title: ConnectorStrings.loadFailed,
            hint: _drive.error!.message,
            action: FilledButton.tonal(
              onPressed: _drive.load,
              child: const Text(ConnectorStrings.retry),
            ),
          ),
        ];
      }
      if (_drive.needsReauth) return const [];
      return const [GhSkeletonCells(count: ConnectorSizes.skeletonRows)];
    }
    final showSearch = files.isNotEmpty || _drive.query.isNotEmpty;
    return [
      if (showSearch) ...[
        GhPillSearch(
          hint: DriveStrings.filter,
          controller: _search,
          onChanged: _drive.setQuery,
        ),
        const SizedBox(height: AppSpacing.md),
      ],
      if (files.isEmpty)
        M3Empty(
          icon: DriveIcons.fallback,
          title: _drive.query.isEmpty
              ? DriveStrings.noFiles
              : DriveStrings.noMatches,
          hint: _drive.query.isEmpty ? DriveStrings.noFilesHint : null,
        )
      else
        M3Group(
          title: DriveStrings.filesTitle,
          children: [
            for (final f in files)
              SettingsTile(
                icon: driveIcon(f),
                leading: ConnectorRowIcon(icon: driveIcon(f)),
                title: f.name,
                summary: _summary(f),
                trailing: AppIcon(
                  AppIcons.chevronRight,
                  size: AppIconSize.sm,
                  color: scheme.onSurfaceVariant,
                ),
                onTap: () => _open(f),
              ),
          ],
        ),
    ];
  }

  String _summary(DriveFile f) {
    final kind = driveKindLabel(f);
    final m = f.modified;
    if (m == null) return kind;
    return '$kind · ${timeAgo(m, widget.now ?? DateTime.now())}';
  }
}

/// Icon of a Drive file by its type.
AppIconData driveIcon(DriveFile f) => switch (f.mimeType) {
  'application/vnd.google-apps.document' => DriveIcons.doc,
  'application/vnd.google-apps.spreadsheet' => DriveIcons.sheet,
  'application/vnd.google-apps.presentation' => DriveIcons.slides,
  'application/pdf' => DriveIcons.pdf,
  final m when m.startsWith('image/') => DriveIcons.image,
  final m when m.startsWith('text/') => DriveIcons.text,
  _ => DriveIcons.other,
};

String driveKindLabel(DriveFile f) => switch (f.mimeType) {
  'application/vnd.google-apps.document' => DriveStrings.kindDoc,
  'application/vnd.google-apps.spreadsheet' => DriveStrings.kindSheet,
  'application/vnd.google-apps.presentation' => DriveStrings.kindSlides,
  'application/pdf' => DriveStrings.kindPdf,
  final m when m.startsWith('text/') => DriveStrings.kindText,
  _ => DriveStrings.kindOther,
};
