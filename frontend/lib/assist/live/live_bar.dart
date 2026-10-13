import 'package:flutter/material.dart';

import '../../core/constants/app_sizes.dart';
import '../../core/constants/assist.dart';
import '../../core/constants/live_voice.dart';
import '../../core/theme/app_palette.dart';
import '../../core/widgets/app_icon.dart';
import 'live_voice.dart';

/// The pill's row in Live mode: what sparky is doing (listening, thinking,
/// speaking), what it heard, a level meter, and End. Tapping the bar while
/// sparky thinks or talks interrupts it.
class LiveBar extends StatelessWidget {
  const LiveBar({super.key, required this.live, this.level});

  final LiveVoice live;

  /// The mic level (0..1) while listening.
  final double Function()? level;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ListenableBuilder(
      listenable: live,
      builder: (context, _) {
        final phase = live.phase;
        final label = switch (phase) {
          LivePhase.listening => LiveStrings.listening,
          LivePhase.thinking => LiveStrings.thinking,
          LivePhase.speaking => LiveStrings.speaking,
          LivePhase.off => LiveStrings.live,
        };
        final line = switch (phase) {
          LivePhase.listening =>
            live.heard.isEmpty ? LiveStrings.speakNow : live.heard,
          LivePhase.thinking => live.heard,
          LivePhase.speaking => LiveStrings.tapToTalk,
          LivePhase.off => '',
        };
        final interruptible =
            phase == LivePhase.thinking || phase == LivePhase.speaking;
        return Semantics(
          button: interruptible,
          label: '$label. $line',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: interruptible ? live.interrupt : null,
            child: SizedBox(
              height: AssistSizes.pillButton,
              child: Row(
                children: [
                  const SizedBox(width: AppSpacing.md),
                  _Pulse(phase: phase, level: level),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: context.text.caption.copyWith(
                            color: phase == LivePhase.off
                                ? p.textTertiary
                                : p.accent,
                          ),
                        ),
                        if (line.isNotEmpty)
                          Text(
                            line,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.bodySmall.copyWith(
                              color: p.textPrimary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: LiveStrings.end,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: live.end,
                      child: Container(
                        width: AssistSizes.pillButton,
                        height: AssistSizes.pillButton,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: p.textPrimary,
                        ),
                        child: AppIcon(
                          LiveIcons.end,
                          size: AppIconSize.lg,
                          color: p.textInverse,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Three dots: they follow the mic while listening, light up in turn while
/// speaking, and dim while thinking. Still with reduced motion.
class _Pulse extends StatefulWidget {
  const _Pulse({required this.phase, this.level});

  final LivePhase phase;
  final double Function()? level;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final _ticker = AnimationController(
    vsync: this,
    duration: LiveSizes.pulsePeriod,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _ticker.stop();
    } else if (!_ticker.isAnimating) {
      _ticker.repeat();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AnimatedBuilder(
      animation: _ticker,
      builder: (context, _) {
        final t = _ticker.value;
        final level = (widget.level?.call() ?? 0).clamp(0.0, 1.0);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < LiveSizes.dots; i++) ...[
              if (i > 0) const SizedBox(width: LiveSizes.dotGap),
              Container(
                width: LiveSizes.dot,
                height: LiveSizes.dot,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: p.accent.withValues(
                    alpha: switch (widget.phase) {
                      LivePhase.listening =>
                        LiveSizes.dimAlpha +
                            (1 - LiveSizes.dimAlpha) *
                                (level * (i + 1) / LiveSizes.dots),
                      LivePhase.speaking =>
                        ((t * LiveSizes.dots).floor() % LiveSizes.dots) == i
                            ? 1.0
                            : LiveSizes.dimAlpha,
                      _ => LiveSizes.dimAlpha,
                    },
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
