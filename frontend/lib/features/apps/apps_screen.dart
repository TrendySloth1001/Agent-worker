import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/constants/apps.dart';
import '../../core/constants/settings_copy.dart';
import '../../core/haptics.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/m3_kit_extras.dart';
import '../../data/knowledge_api.dart';
import '../chat/widgets/markdown/inline_icon.dart';
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
        final connected = _connections.github != null;
        return M3Page(
          title: AppsStrings.title,
          onRefresh: _refresh,
          slivers: [
            M3Body(
              children: [
                M3Group(
                  title: connected
                      ? AppsStrings.sectionConnected
                      : AppsStrings.sectionAvailable,
                  children: [for (final a in accounts) _tile(a)],
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

  Widget _tile(AppConnector a) {
    final isGithub = a.id == AppIds.github;
    final connected = isGithub && _connections.github != null;
    return Opacity(
      opacity: a.isSoon ? AppsSizes.soonAlpha : 1,
      child: SettingsTile(
        icon: a.icon ?? a.brand!.fallback,
        leading: a.brand != null ? AppMark(a.brand!) : null,
        title: a.name,
        summary: _blurb(a),
        trailing: a.isSoon
            ? const M3Tag(AppsStrings.soon)
            : isGithub
            ? M3Tag(
                connected ? AppsStrings.connected : AppsStrings.connect,
                accent: connected,
              )
            : null,
        onTap: a.open == null
            ? null
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
        child: InlineIcon(
          set: brand.set,
          name: brand.name,
          size: AppsSizes.brandGlyph,
          color: scheme.onSurface,
          fallback: AppIcon(
            brand.fallback,
            size: AppsSizes.brandGlyph,
            color: scheme.onSurface,
          ),
        ),
      ),
    );
  }
}
