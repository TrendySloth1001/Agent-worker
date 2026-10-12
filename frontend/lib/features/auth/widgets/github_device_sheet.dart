import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/connections.dart';
import '../../../core/constants/sso_constants.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../data/sso_api.dart';
import '../../chat/widgets/open_url.dart';
import '../../chat/widgets/rich/playful_common.dart';
import '../../connections/widgets/device_code_panel.dart';
import '../sso/github_device_flow.dart';

/// "Continue with GitHub" / Profile → LINK: the device code in a bottom sheet.
/// Completes with the finished poll (carrying the session when signing in),
/// or null when closed.
Future<SsoPoll?> showGithubDeviceSheet(
  BuildContext context, {
  required String title,
  required Future<DeviceStart> Function() start,
  required Future<SsoPoll> Function(String flowId) poll,
}) {
  Haptics.tap();
  return showModalBottomSheet<SsoPoll>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _GithubDeviceSheet(
      title: title,
      flow: GithubDeviceFlow(start: start, poll: poll),
    ),
  );
}

class _GithubDeviceSheet extends StatefulWidget {
  const _GithubDeviceSheet({required this.title, required this.flow});

  final String title;
  final GithubDeviceFlow flow;

  @override
  State<_GithubDeviceSheet> createState() => _GithubDeviceSheetState();
}

class _GithubDeviceSheetState extends State<_GithubDeviceSheet> {
  GithubDeviceFlow get _flow => widget.flow;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    _flow.addListener(_onFlow);
    _flow.begin();
  }

  @override
  void dispose() {
    _flow.removeListener(_onFlow);
    _flow.dispose();
    super.dispose();
  }

  void _onFlow() {
    if (_closed || !mounted) return;
    switch (_flow.phase) {
      case DeviceFlowPhase.done:
        Haptics.received();
        _close(_flow.result);
      case DeviceFlowPhase.expired ||
          DeviceFlowPhase.denied ||
          DeviceFlowPhase.failed:
        Haptics.error();
      default:
        break;
    }
  }

  void _close([SsoPoll? result]) {
    if (_closed) return;
    _closed = true;
    Navigator.of(context).pop(result);
  }

  Future<void> _open() async {
    final f = _flow.flow;
    if (f == null) return;
    await Clipboard.setData(ClipboardData(text: f.userCode));
    if (!mounted) return;
    final m = ScaffoldMessenger.maybeOf(context);
    m?.hideCurrentSnackBar();
    m?.showSnackBar(SnackBar(content: Text(ConnectStrings.codeCopied)));
    await visitUrl(context, f.openUrl);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListenableBuilder(
              listenable: _flow,
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
    switch (_flow.phase) {
      case DeviceFlowPhase.starting || DeviceFlowPhase.done:
        return _Busy(
          title: widget.title,
          label: _flow.phase == DeviceFlowPhase.done
              ? SsoStrings.signingIn
              : SsoStrings.starting,
        );
      case DeviceFlowPhase.waiting:
        return DeviceCodePanel(
          title: widget.title,
          code: _flow.flow?.userCode ?? '',
          secondsLeft: _flow.secondsLeft,
          fraction: _flow.timeLeftFraction,
          onOpen: _open,
          onCancel: () {
            Haptics.tap();
            _close();
          },
        );
      case DeviceFlowPhase.expired:
        return _Problem(
          title: widget.title,
          message: SsoStrings.expired,
          onRetry: _flow.begin,
          onClose: _close,
        );
      case DeviceFlowPhase.denied:
        return _Problem(
          title: widget.title,
          message: SsoStrings.denied,
          onRetry: _flow.begin,
          onClose: _close,
        );
      case DeviceFlowPhase.failed:
        return _Problem(
          title: widget.title,
          message: _flow.error ?? SsoStrings.failed,
          onRetry: _flow.begin,
          onClose: _close,
        );
    }
  }
}

class _Busy extends StatelessWidget {
  const _Busy({required this.title, required this.label});

  final String title, label;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GithubHeading(title),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            SizedBox.square(
              dimension: AppIconSize.sm,
              child: CircularProgressIndicator(
                strokeWidth: AppBorder.thick,
                color: p.textPrimary,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(label, style: context.text.caption),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem({
    required this.title,
    required this.message,
    required this.onRetry,
    required this.onClose,
  });

  final String title, message;
  final VoidCallback onRetry, onClose;

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
      ],
    );
  }
}
