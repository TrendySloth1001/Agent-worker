import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/connections.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/brand_mark.dart';
import '../../../core/widgets/copy_action.dart';
import '../../../core/widgets/dot_meter.dart';
import '../../chat/widgets/rich/playful_common.dart';

/// GitHub device-flow waiting state: the big code with COPY, OPEN GITHUB and
/// CANCEL, a pulse while waiting and a dot meter counting the code down.
/// Shared by "Connect GitHub" (chat card, Settings) and "Continue with GitHub"
/// (sign-in sheet, Profile link).
class DeviceCodePanel extends StatelessWidget {
  const DeviceCodePanel({
    super.key,
    required this.title,
    required this.code,
    required this.secondsLeft,
    required this.fraction,
    required this.onOpen,
    required this.onCancel,
  });

  final String title, code;
  final int secondsLeft;

  /// Code lifetime left, 1 = fresh.
  final double fraction;
  final VoidCallback onOpen, onCancel;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GithubHeading(title),
        const SizedBox(height: AppSpacing.md),
        Text(ConnectStrings.enterCode, style: t.caption),
        const SizedBox(height: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: ConnectSizes.codePadV,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: p.borderStrong, width: AppBorder.thin),
          ),
          child: Row(
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: SelectableText(
                    code,
                    maxLines: 1,
                    style: t.label.copyWith(
                      fontSize: ConnectSizes.codeFont,
                      letterSpacing: ConnectSizes.codeSpacing,
                      fontWeight: FontWeight.w700,
                      color: p.textPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              CopyAction(text: code),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: PlayfulButton(
                label: ConnectStrings.openGithub,
                icon: ConnectIcons.open,
                primary: true,
                expand: true,
                onTap: onOpen,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            PlayfulButton(label: ConnectStrings.cancel, onTap: onCancel),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            const PulseDot(),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(ConnectStrings.waiting, style: t.caption)),
            Text(
              ConnectStrings.countdown(secondsLeft),
              style: t.caption.copyWith(color: p.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        DotMeter(fraction: fraction),
      ],
    );
  }
}

/// GitHub mark + title on one line.
class GithubHeading extends StatelessWidget {
  const GithubHeading(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        BrandMark.github(
          size: ConnectSizes.markSize,
          color: context.palette.textPrimary,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(title, style: context.text.title)),
      ],
    );
  }
}

/// Accent dot that breathes while waiting for GitHub.
class PulseDot extends StatefulWidget {
  const PulseDot({super.key});

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot>
    with SingleTickerProviderStateMixin {
  late final _ctl = AnimationController(
    vsync: this,
    duration: ConnectDurations.pulse,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _ctl.value = 1;
    } else if (!_ctl.isAnimating) {
      _ctl.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.palette.accent;
    return FadeTransition(
      opacity: Tween(begin: ConnectSizes.pulseMinAlpha, end: 1.0).animate(_ctl),
      child: Container(
        width: ConnectSizes.pulseDot,
        height: ConnectSizes.pulseDot,
        decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
      ),
    );
  }
}
