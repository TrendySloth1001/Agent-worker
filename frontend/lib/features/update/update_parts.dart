import 'package:flutter/material.dart';

import '../../core/constants/app_sizes.dart';
import '../../core/constants/update.dart';
import '../../core/haptics.dart';
import '../../core/theme/app_palette.dart';
import '../../core/update/update_controller.dart';
import '../../core/widgets/app_icon.dart';

/// Small accent dot: "there is an update".
class UpdateDot extends StatelessWidget {
  const UpdateDot({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: UpdateSizes.dot,
    height: UpdateSizes.dot,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: context.palette.accent,
    ),
  );
}

String updateFailureText(UpdateFailure? f) => switch (f) {
  UpdateFailure.verify => UpdateStrings.failVerify,
  UpdateFailure.signature => UpdateStrings.failSignature,
  UpdateFailure.install => UpdateStrings.failInstall,
  _ => UpdateStrings.failNetwork,
};

ButtonStyle _pill(BuildContext context) => ButtonStyle(
  minimumSize: const WidgetStatePropertyAll(
    Size.fromHeight(AppSizes.buttonHeight),
  ),
  shape: const WidgetStatePropertyAll(StadiumBorder()),
  textStyle: WidgetStatePropertyAll(
    context.text.body.copyWith(
      fontVariations: const [FontVariation.weight(600)],
    ),
  ),
);

/// What is going on besides the buttons: download progress, the permission
/// explainer, "installing", or the reason something failed. Empty when idle.
class UpdateStatusBlock extends StatelessWidget {
  const UpdateStatusBlock({super.key, required this.controller});

  final UpdateController controller;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    switch (controller.phase) {
      case UpdatePhase.downloading:
        final pct = (controller.progress * 100).round();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              UpdateStrings.downloading(pct),
              style: context.text.label.copyWith(color: p.textSecondary),
            ),
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: LinearProgressIndicator(
                value: controller.progress,
                minHeight: UpdateSizes.progressHeight,
                color: p.accent,
                backgroundColor: p.border,
              ),
            ),
          ],
        );
      case UpdatePhase.installing:
        return Row(
          children: [
            SizedBox(
              width: UpdateSizes.spinner,
              height: UpdateSizes.spinner,
              child: CircularProgressIndicator(
                strokeWidth: UpdateSizes.spinnerStroke,
                color: p.accent,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                UpdateStrings.installing,
                style: context.text.bodySmall.copyWith(color: p.textSecondary),
              ),
            ),
          ],
        );
      case UpdatePhase.needsPermission:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(UpdateStrings.permissionTitle, style: context.text.title),
            const SizedBox(height: AppSpacing.sm),
            Text(
              UpdateStrings.permissionBody,
              style: context.text.bodySmall.copyWith(color: p.textSecondary),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: _pill(context),
                    onPressed: () {
                      Haptics.tap();
                      controller.cancelPermission();
                    },
                    child: const Text(UpdateStrings.notNow),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: FilledButton(
                    style: _pill(context),
                    onPressed: () {
                      Haptics.tap();
                      controller.openPermissionSettings();
                    },
                    child: const Text(UpdateStrings.permissionOpen),
                  ),
                ),
              ],
            ),
          ],
        );
      case UpdatePhase.failed:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppIcon(UpdateIcons.alert, size: AppIconSize.md, color: p.error),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                updateFailureText(controller.failure),
                style: context.text.bodySmall.copyWith(color: p.error),
              ),
            ),
          ],
        );
      case UpdatePhase.idle || UpdatePhase.ready:
        return const SizedBox.shrink();
    }
  }
}

/// The main buttons while nothing is running: [secondary] ("Later") and
/// Update / Try again. Hidden while a download, install or the permission
/// step is on screen (the [UpdateStatusBlock] has its own).
class UpdateButtons extends StatelessWidget {
  const UpdateButtons({
    super.key,
    required this.controller,
    this.secondaryLabel,
    this.onSecondary,
  });

  final UpdateController controller;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final phase = controller.phase;
    if (phase == UpdatePhase.downloading ||
        phase == UpdatePhase.installing ||
        phase == UpdatePhase.needsPermission) {
      return const SizedBox.shrink();
    }
    final retry = phase == UpdatePhase.failed;
    return Row(
      children: [
        if (secondaryLabel != null) ...[
          Expanded(
            child: OutlinedButton(
              style: _pill(context),
              onPressed: () {
                Haptics.tap();
                onSecondary?.call();
              },
              child: Text(secondaryLabel!),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
        ],
        Expanded(
          child: FilledButton(
            style: _pill(context),
            onPressed: () {
              Haptics.tap();
              controller.begin();
            },
            child: Text(retry ? UpdateStrings.tryAgain : UpdateStrings.update),
          ),
        ),
      ],
    );
  }
}
