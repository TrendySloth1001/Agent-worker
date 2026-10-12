import 'package:flutter/material.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/voice.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import 'voice_controller.dart';
import 'voice_engine.dart';

/// The row above the text field while dictating: cancel, a dot-matrix level
/// meter, the clock. Also shows an error with its action.
class VoiceStrip extends StatelessWidget {
  const VoiceStrip({
    super.key,
    required this.voice,
    required this.holding,
    required this.slidingOut,
    required this.onCancel,
    required this.onRetry,
    required this.onSettings,
  });

  final VoiceController voice;

  /// Dictating with the button held down (hold-to-talk).
  final bool holding;

  /// The held finger is past the cancel distance.
  final bool slidingOut;
  final VoidCallback onCancel, onRetry, onSettings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: voice,
      builder: (context, _) => AnimatedSize(
        duration: AppDurations.fast,
        alignment: Alignment.bottomCenter,
        child: switch (voice.phase) {
          VoicePhase.idle => const SizedBox(width: double.infinity),
          VoicePhase.error => _error(context),
          _ => _listening(context),
        },
      ),
    );
  }

  Widget _listening(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final working = voice.phase == VoicePhase.transcribing;
    final label = working
        ? VoiceStrings.transcribing
        : holding
        ? VoiceStrings.slideToCancel
        : VoiceStrings.listening;
    return SizedBox(
      height: VoiceSizes.stripHeight,
      child: Row(
        children: [
          _StripButton(
            icon: AppIcons.close,
            label: VoiceStrings.cancel,
            color: slidingOut ? p.error : p.textSecondary,
            onTap: onCancel,
          ),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            flex: 0,
            child: Text(
              label,
              style: t.caption.copyWith(
                color: slidingOut ? p.error : p.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: DotMeter(
              levels: working
                  ? List.filled(VoiceSizes.meterColumns, 0.0)
                  : voice.levels,
            ),
          ),
          SizedBox(
            width: VoiceSizes.timerWidth,
            child: Text(
              VoiceStrings.clock(voice.elapsed),
              textAlign: TextAlign.end,
              style: t.caption.copyWith(color: p.textPrimary),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
    );
  }

  Widget _error(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final failure = voice.failure ?? VoiceFailure.failed;
    final blocked = failure == VoiceFailure.permissionBlocked;
    final message = switch (failure) {
      VoiceFailure.permissionDenied => VoiceStrings.denied,
      VoiceFailure.permissionBlocked => VoiceStrings.blocked,
      VoiceFailure.unavailable => VoiceStrings.unavailable,
      VoiceFailure.noSpeech => VoiceStrings.noSpeech,
      VoiceFailure.network => VoiceStrings.network,
      VoiceFailure.failed => voice.message ?? VoiceStrings.failed,
    };
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Text(
                message,
                style: t.caption.copyWith(color: p.error),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          if (failure != VoiceFailure.unavailable)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                Haptics.tap();
                blocked ? onSettings() : onRetry();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.sm,
                ),
                child: Text(
                  blocked ? VoiceStrings.openSettings : VoiceStrings.retry,
                  style: t.caption.copyWith(color: p.accent),
                ),
              ),
            ),
          _StripButton(
            icon: AppIcons.close,
            label: VoiceStrings.dismiss,
            color: p.textTertiary,
            onTap: voice.dismiss,
          ),
        ],
      ),
    );
  }
}

class _StripButton extends StatelessWidget {
  const _StripButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final AppIconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Haptics.tap();
        onTap();
      },
      child: SizedBox.square(
        dimension: AppSizes.sendButton,
        child: AppIcon(
          icon,
          size: AppIconSize.md,
          semanticLabel: label,
          color: color,
        ),
      ),
    );
  }
}

/// Columns of dots that light up from the middle with the loudness: the
/// Nothing-style level meter.
class DotMeter extends StatelessWidget {
  const DotMeter({super.key, required this.levels});

  final List<double> levels;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return RepaintBoundary(
      child: CustomPaint(
        size: const Size.fromHeight(
          VoiceSizes.meterRows * (VoiceSizes.meterDot + VoiceSizes.meterGap),
        ),
        painter: _MeterPainter(levels, p.accent, p.border),
      ),
    );
  }
}

class _MeterPainter extends CustomPainter {
  _MeterPainter(this.levels, this.lit, this.dim);

  final List<double> levels;
  final Color lit, dim;

  @override
  void paint(Canvas canvas, Size size) {
    if (levels.isEmpty || size.width <= 0) return;
    final on = Paint()..color = lit;
    final off = Paint()..color = dim;
    final step = size.width / levels.length;
    final rowStep = VoiceSizes.meterDot + VoiceSizes.meterGap;
    final top = (size.height - VoiceSizes.meterRows * rowStep) / 2;
    final radius = VoiceSizes.meterDot / 2;
    for (var c = 0; c < levels.length; c++) {
      final level = levels[c].clamp(VoiceSizes.meterMinLevel, 1.0);
      // Lit rows grow from the middle row outward.
      final reach = (level * VoiceSizes.meterRows / 2).ceil();
      final mid = (VoiceSizes.meterRows - 1) / 2;
      for (var r = 0; r < VoiceSizes.meterRows; r++) {
        final lightUp = (r - mid).abs() < reach;
        canvas.drawCircle(
          Offset(step * (c + 0.5), top + rowStep * r + rowStep / 2),
          radius,
          lightUp ? on : off,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_MeterPainter old) =>
      old.levels != levels || old.lit != lit || old.dim != dim;
}
