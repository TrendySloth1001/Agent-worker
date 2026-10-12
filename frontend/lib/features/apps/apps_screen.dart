import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/constants/apps.dart';
import '../../core/constants/connectors.dart';
import '../../core/constants/settings_copy.dart';
import '../../core/haptics.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/m3_kit_extras.dart';
import '../../data/knowledge_api.dart';
import '../connections/connections_controller.dart';
import '../settings/widgets/settings_kit.dart';
import 'apps_registry.dart';

/// Hub of everything Sparky can connect to or read from: linked accounts,
/// built-in sources and the apps that are coming.
class AppsScreen extends StatefulWidget {
  const AppsScreen({super.key, this.connections, this.sourceCount});

  /// Test seams; default to the app's connection state and knowledge API.
  final ConnectionsController? connections;
  final Future<int> Function()? sourceCount;

  @override
  State<AppsScreen> createState() => _AppsScreenState();
}

class _AppsScreenState extends State<AppsScreen> {
  late final ConnectionsController _connections =
      widget.connections ?? ConnectionsController.instance;
  int? _sources;
  bool _sourcesFailed = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _connections.ensureLoaded();
    _loadSources();
  }

  Future<void> _loadSources() async {
    try {
      final custom = widget.sourceCount;
      final base = custom == null ? AppScope.of(context).baseUrl : '';
      final n = custom != null
          ? await custom()
          : (await KnowledgeApi(base).list()).length;
      if (!mounted) return;
      setState(() {
        _sources = n;
        _sourcesFailed = false;
      });
    } catch (_) {
      if (mounted) setState(() => _sourcesFailed = true);
    }
  }

  Future<void> _refresh() =>
      Future.wait([_connections.refresh(), _loadSources()]);

  /// Live status line for the apps that have one.
  String _blurb(AppConnector a) {
    switch (a.id) {
      case AppIds.github:
        final g = _connections.github;
        if (g != null) return AppsStrings.account(g.login);
        return switch (_connections.githubPhase) {
          GithubPhase.loading => AppsStrings.loading,
          _ => AppsStrings.notConnected,
        };
      case AppIds.googleDrive || AppIds.notion:
        final id = _providerOf(a.id)!;
        final c = _connections.connection(id);
        if (c != null) {
          final who = c.accountEmail.isNotEmpty ? c.accountEmail : c.login;
          final ws = c.workspaceName;
          return id == ConnectorIds.notion && ws.isNotEmpty ? ws : who;
        }
        if (_connections.state == null) {
          return _connections.loadFailed ? a.blurb : AppsStrings.loading;
        }
        if (_connections.configured(id) != true) {
          return ConnectorStrings.notSetUp;
        }
        return a.blurb;
      case AppIds.knowledge:
        final n = _sources;
        if (n == null) return _sourcesFailed ? a.blurb : AppsStrings.loading;
        return n == 0 ? AppsStrings.noSources : AppsStrings.sources(n);
      default:
        return a.blurb;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _connections,
      builder: (context, _) {
        final accounts = AppsRegistry.inSection(AppSection.account);
        bool linked(AppConnector a) => _isConnected(a);
        final connectedApps = [
          for (final a in accounts)
            if (linked(a)) a,
        ];
        final available = [
          for (final a in accounts)
            if (!linked(a)) a,
        ];
        return M3Page(
          title: AppsStrings.title,
          onRefresh: _refresh,
          slivers: [
            M3Body(
              children: [
                if (connectedApps.isNotEmpty)
                  M3Group(
                    title: AppsStrings.sectionConnected,
                    children: [for (final a in connectedApps) _tile(a)],
                  ),
                if (available.isNotEmpty)
                  M3Group(
                    title: AppsStrings.sectionAvailable,
                    children: [for (final a in available) _tile(a)],
                  ),
                M3Group(
                  title: AppsStrings.sectionBuiltIn,
                  children: [
                    for (final a in AppsRegistry.inSection(AppSection.builtIn))
                      _tile(a),
                  ],
                ),
                M3Group(
                  title: AppsStrings.sectionSoon,
                  footer: AppsStrings.soonFooter,
                  children: [
                    for (final a in AppsRegistry.inSection(AppSection.soon))
                      _tile(a),
                  ],
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  static String? _providerOf(String appId) => switch (appId) {
    AppIds.googleDrive => ConnectorIds.drive,
    AppIds.notion => ConnectorIds.notion,
    _ => null,
  };

  bool _isConnected(AppConnector a) {
    if (a.id == AppIds.github) return _connections.github != null;
    final p = _providerOf(a.id);
    return p != null && _connections.connection(p) != null;
  }

  /// The trailing tag of a linkable app.
  Widget? _accountTag(AppConnector a) {
    if (a.section != AppSection.account) return null;
    final p = _providerOf(a.id);
    final c = p == null ? null : _connections.connection(p);
    if (c != null && c.needsReauth) {
      return const M3Tag(ConnectorStrings.reconnectTag);
    }
    if (_isConnected(a)) {
      return const M3Tag(AppsStrings.connected, accent: true);
    }
    if (p != null &&
        _connections.state != null &&
        _connections.configured(p) != true) {
      return const M3Tag(ConnectorStrings.notSetUpTag);
    }
    return const M3Tag(AppsStrings.connect);
  }

  /// A coming-soon app cannot be connected yet: say so.
  void _soon(AppConnector a) {
    Haptics.tap();
    final m = ScaffoldMessenger.maybeOf(context);
    if (m == null) return;
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(content: Text(AppsStrings.soonToast(a.name))));
  }

  Widget _tile(AppConnector a) {
    return Opacity(
      opacity: a.isSoon ? AppsSizes.soonAlpha : 1,
      child: SettingsTile(
        icon: a.icon ?? a.brand!.logo,
        leading: a.brand != null ? AppMark(a.brand!) : null,
        title: a.name,
        summary: _blurb(a),
        trailing: a.isSoon ? const M3Tag(AppsStrings.soon) : _accountTag(a),
        onTap: a.open == null
            ? (a.isSoon ? () => _soon(a) : null)
            : () {
                Haptics.tap();
                a.open!(context);
              },
      ),
    );
  }
}

/// A brand logo in the tonal circle every row leads with.
class AppMark extends StatelessWidget {
  const AppMark(this.brand, {super.key});

  final AppBrand brand;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: SettingsSizes.iconCircle,
      height: SettingsSizes.iconCircle,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: scheme.surfaceContainerHighest,
      ),
      child: Center(
        child: AppIcon(
          brand.logo,
          size: AppsSizes.brandGlyph,
          color: scheme.onSurface,
        ),
      ),
    );
  }
}
