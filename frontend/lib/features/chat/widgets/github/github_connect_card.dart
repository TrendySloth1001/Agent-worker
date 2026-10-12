import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/connections.dart';
import '../../../../core/constants/illustrations.dart';
import '../../../../core/constants/widget_github.dart';
import '../../../../core/haptics.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/illustration.dart';
import '../../../connections/connections_controller.dart';
import '../../../connections/widgets/device_code_panel.dart';
import '../../../connections/widgets/github_web_panel.dart';
import '../../../auth/sso/github_web_auth.dart';
import '../../../../core/constants/sso_constants.dart';
import '../open_url.dart';
import '../rich/playful_common.dart';
import '../rich/rich_frame.dart';
import 'github_common.dart';

/// ```github-connect block: links the user's own GitHub account with the
/// OAuth device flow (code on screen, approve on github.com).
class GithubConnectCard extends StatelessWidget {
  const GithubConnectCard({super.key, required this.source});

  /// Unused ("github"); kept for the registry signature.
  final String source;

  @override
  Widget build(BuildContext context) {
    return RichCard(
      title: ConnectStrings.cardTitle,
      leading: const Octicon(GithubOcticons.mark),
      child: GithubConnectPanel(paper: context.palette.codeBackground),
    );
  }
}

/// Opens the connect flow in a bottom sheet (Settings → Connections).
Future<void> showGithubConnectSheet(BuildContext context) {
  Haptics.tap();
  final p = context.palette;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: p.surface,
    shape: RoundedRectangleBorder(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppRadius.lg),
      ),
      side: BorderSide(color: p.border),
    ),
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppSpacing.sm),
            Center(
              child: Container(
                width: ConnectSizes.sheetHandleWidth,
                height: ConnectSizes.sheetHandleHeight,
                decoration: BoxDecoration(
                  color: p.borderStrong,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),
            GithubConnectPanel(paper: p.surface),
          ],
        ),
      ),
    ),
  );
}

/// The whole connect experience for one state of [ConnectionsController].
class GithubConnectPanel extends StatefulWidget {
  const GithubConnectPanel({super.key, this.paper});

  /// Surface behind the panel (for the illustration's fills).
  final Color? paper;

  @override
  State<GithubConnectPanel> createState() => _GithubConnectPanelState();
}

class _GithubConnectPanelState extends State<GithubConnectPanel> {
  final _c = ConnectionsController.instance;

  @override
  void initState() {
    super.initState();
    _c.ensureLoaded();
  }

  void _toast(String text) {
    final m = ScaffoldMessenger.maybeOf(context);
    if (m == null) return;
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _connect() async {
    await _c.connectGithub();
  }

  Future<void> _openGithub() async {
    final f = _c.flow;
    if (f == null) return;
    await Clipboard.setData(ClipboardData(text: f.userCode));
    if (!mounted) return;
    _toast(ConnectStrings.codeCopied);
    await visitUrl(context, f.openUrl);
  }

  Future<void> _disconnect() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(ConnectStrings.disconnectTitle),
        content: const Text(ConnectStrings.disconnectBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(ConnectStrings.disconnectKeep),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(ConnectStrings.disconnect),
          ),
        ],
      ),
    );
    if (ok != true) return;
    Haptics.tap();
    try {
      await _c.disconnectGithub();
      if (mounted) _toast(ConnectStrings.disconnected);
    } catch (_) {
      if (mounted) _toast(ConnectStrings.failed);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) => AnimatedSize(
        duration: AppDurations.normal,
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.all(ConnectSizes.pad),
          child: _body(context),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    switch (_c.githubPhase) {
      case GithubPhase.loading:
        return const GhSkeleton();
      case GithubPhase.loadFailed:
        return _Problem(
          message: ConnectStrings.loadFailed,
          onRetry: _c.refresh,
        );
      case GithubPhase.notConfigured:
        return _c.isOwner
            ? _Setup(onRetry: _c.refresh)
            : const _Problem(message: ConnectStrings.notAvailable);
      case GithubPhase.idle || GithubPhase.starting:
        return _Intro(
          paper: widget.paper,
          starting: _c.githubPhase == GithubPhase.starting,
          onConnect: _connect,
        );
      case GithubPhase.browser:
        final web = _c.web;
        return GithubWebPanel(
          title: ConnectStrings.title,
          openedInApp: web.openedInApp,
          busyLabel: switch (web.phase) {
            GithubWebPhase.starting => GithubWebStrings.opening,
            GithubWebPhase.redeeming => GithubWebStrings.finishing,
            _ => null,
          },
          onOpenAgain: web.reopen,
          onCancel: _c.cancelFlow,
          onUseCode: _c.useCode,
        );
      case GithubPhase.waiting:
        return DeviceCodePanel(
          title: ConnectStrings.title,
          code: _c.flow?.userCode ?? '',
          secondsLeft: _c.secondsLeft,
          fraction: _c.timeLeftFraction,
          onOpen: _openGithub,
          onCancel: _c.cancelFlow,
        );
      case GithubPhase.connected:
        return _Connected(controller: _c, onDisconnect: _disconnect);
      case GithubPhase.expired:
        return _Problem(message: ConnectStrings.expired, onRetry: _connect);
      case GithubPhase.denied:
        return _Problem(message: ConnectStrings.denied, onRetry: _connect);
      case GithubPhase.failed:
        return _Problem(
          message: _c.flowError ?? ConnectStrings.failed,
          onRetry: _connect,
        );
    }
  }
}

class _Intro extends StatelessWidget {
  const _Intro({
    required this.paper,
    required this.starting,
    required this.onConnect,
  });

  final Color? paper;
  final bool starting;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Illustration(
            kind: IllustrationKind.github,
            height: IllustrationSizes.github,
            paper: paper,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const GithubHeading(ConnectStrings.title),
        const SizedBox(height: AppSpacing.xs),
        Text(ConnectStrings.pitch, style: context.text.bodySmall),
        const SizedBox(height: AppSpacing.lg),
        PlayfulButton(
          label: starting ? ConnectStrings.starting : ConnectStrings.connect,
          icon: ConnectIcons.connect,
          primary: true,
          expand: true,
          enabled: !starting,
          onTap: onConnect,
        ),
      ],
    );
  }
}

class _Connected extends StatelessWidget {
  const _Connected({required this.controller, required this.onDisconnect});

  final ConnectionsController controller;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final g = controller.github!;
    final canSend = playfulCanSend(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            GhAvatar(g.avatarUrl, size: ConnectSizes.avatar),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ConnectStrings.connectedTitle, style: t.title),
                  const SizedBox(height: AppSpacing.xxs),
                  Row(
                    children: [
                      AppIcon(
                        ConnectIcons.check,
                        size: AppIconSize.xs,
                        color: p.textPrimary,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Flexible(
                        child: Text(
                          ConnectStrings.authOk,
                          style: t.caption.copyWith(color: p.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            PopupMenuButton<int>(
              tooltip: ConnectStrings.more,
              color: p.surfaceRaised,
              icon: AppIcon(
                ConnectIcons.more,
                size: AppIconSize.sm,
                color: p.textSecondary,
              ),
              onOpened: Haptics.tap,
              onSelected: (_) => onDisconnect(),
              itemBuilder: (context) => [
                PopupMenuItem<int>(
                  value: 0,
                  child: Row(
                    children: [
                      AppIcon(
                        ConnectIcons.disconnect,
                        size: AppIconSize.sm,
                        color: p.accent,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        ConnectStrings.disconnect,
                        style: t.caption.copyWith(color: p.accent),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            GhChip(
              ConnectStrings.account(g.login),
              icon: GithubOcticons.mark,
              onTap: () =>
                  visitUrl(context, ConnectStrings.profileUrl(g.login)),
            ),
          ],
        ),
        if (g.scopes.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${ConnectStrings.scopes}  ${g.scopes.join(' · ')}',
            style: t.caption,
          ),
        ],
        if (canSend) ...[
          const SizedBox(height: AppSpacing.lg),
          PlayfulButton(
            label: ConnectStrings.showRepos,
            icon: ConnectIcons.repos,
            primary: true,
            expand: true,
            onTap: () => playfulSend(context, ConnectStrings.showReposMessage),
          ),
        ],
      ],
    );
  }
}

/// Short message with an optional retry.
class _Problem extends StatelessWidget {
  const _Problem({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const GithubHeading(ConnectStrings.title),
        const SizedBox(height: AppSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppIcon(
              ConnectIcons.warning,
              size: AppIconSize.sm,
              color: p.accent,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                message,
                style: context.text.bodySmall.copyWith(color: p.textSecondary),
              ),
            ),
          ],
        ),
        if (onRetry != null) ...[
          const SizedBox(height: AppSpacing.md),
          PlayfulButton(
            label: ConnectStrings.retry,
            icon: ConnectIcons.retry,
            expand: true,
            onTap: onRetry!,
          ),
        ],
      ],
    );
  }
}

/// Owner-only: how to create the GitHub OAuth app.
class _Setup extends StatelessWidget {
  const _Setup({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const GithubHeading(ConnectStrings.setupTitle),
        const SizedBox(height: AppSpacing.sm),
        Text(ConnectStrings.setupIntro, style: t.bodySmall),
        const SizedBox(height: AppSpacing.md),
        for (var i = 0; i < ConnectStrings.setupSteps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: ConnectSizes.stepIndex,
                  child: Text('${i + 1}', style: t.caption),
                ),
                Expanded(
                  child: Text(
                    ConnectStrings.setupSteps[i],
                    style: t.bodySmall.copyWith(color: p.textPrimary),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: PlayfulButton(
                label: ConnectStrings.openSetup,
                icon: ConnectIcons.open,
                primary: true,
                expand: true,
                onTap: () => visitUrl(context, ConnectStrings.setupUrl),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            PlayfulButton(
              label: ConnectStrings.retry,
              icon: ConnectIcons.retry,
              onTap: onRetry,
            ),
          ],
        ),
      ],
    );
  }
}
