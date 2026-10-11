import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/connections.dart';
import '../../../core/constants/sso_constants.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import '../../chat/widgets/rich/playful_common.dart';
import '../../connections/widgets/device_code_panel.dart';
import '../../connections/widgets/github_web_panel.dart';
import '../sso/github_web_auth.dart';

enum GithubWebSheetResult { done, useCode, closed }

/// "Continue with GitHub" / Profile → LINK over the one-tap web flow: starts
/// it, opens GitHub, and waits in a small sheet until the deep link comes
/// back (the result itself is applied by [GithubWebAuth]).
Future<GithubWebSheetResult> showGithubWebSheet(
  BuildContext context, {
  required String title,
  required String mode,
}) async {
  Haptics.tap();
  final p = context.palette;
  final r = await showModalBottomSheet<GithubWebSheetResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: p.surface,
    shape: RoundedRectangleBorder(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppRadius.lg),
      ),
      side: BorderSide(color: p.border),
    ),
    builder: (context) => _GithubWebSheet(title: title, mode: mode),
  );
  return r ?? GithubWebSheetResult.closed;
}

class _GithubWebSheet extends StatefulWidget {
  const _GithubWebSheet({required this.title, required this.mode});

  final String title, mode;

  @override
  State<_GithubWebSheet> createState() => _GithubWebSheetState();
}

class _GithubWebSheetState extends State<_GithubWebSheet> {
  final _web = GithubWebAuth.instance;
  StreamSubscription<GithubWebOutcome>? _sub;
  GithubWebSheetResult? _result;

  @override
  void initState() {
    super.initState();
    _sub = _web.outcomes.listen((o) {
      if (o.mode == widget.mode && o.ok) _close(GithubWebSheetResult.done);
    });
    _web.start(widget.mode);
  }

  @override
  void dispose() {
    _sub?.cancel();
    // Closed without finishing: forget the flow (a late link is ignored).
    if (_result != GithubWebSheetResult.done && _web.activeFor(widget.mode)) {
      _web.cancel();
    }
    super.dispose();
  }

  void _close(GithubWebSheetResult r) {
    if (_result != null || !mounted) return;
    _result = r;
    Navigator.of(context).pop(r);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SafeArea(
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
            ListenableBuilder(
              listenable: _web,
              builder: (context, _) => AnimatedSize(
                duration: AppDurations.normal,
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.all(ConnectSizes.pad),
                  child: _body(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    void useCode() => _close(GithubWebSheetResult.useCode);
    if (_web.phase == GithubWebPhase.failed) {
      return _Problem(
        title: widget.title,
        message: _web.error ?? GithubWebStrings.failed,
        onRetry: () => _web.start(widget.mode),
        onUseCode: useCode,
        onClose: () => _close(GithubWebSheetResult.closed),
      );
    }
    return GithubWebPanel(
      title: widget.title,
      openedInApp: _web.openedInApp,
      busyLabel: switch (_web.phase) {
        GithubWebPhase.waiting => null,
        GithubWebPhase.redeeming => GithubWebStrings.finishing,
        _ => GithubWebStrings.opening,
      },
      onOpenAgain: _web.reopen,
      onCancel: () => _close(GithubWebSheetResult.closed),
      onUseCode: useCode,
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem({
    required this.title,
    required this.message,
    required this.onRetry,
    required this.onUseCode,
    required this.onClose,
  });

  final String title, message;
  final VoidCallback onRetry, onUseCode, onClose;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GithubHeading(title),
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
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: PlayfulButton(
                label: SsoStrings.retry,
                icon: ConnectIcons.retry,
                primary: true,
                expand: true,
                onTap: () {
                  Haptics.tap();
                  onRetry();
                },
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            PlayfulButton(
              label: SsoStrings.close,
              onTap: () {
                Haptics.tap();
                onClose();
              },
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Center(child: UseCodeLink(onTap: onUseCode)),
      ],
    );
  }
}
