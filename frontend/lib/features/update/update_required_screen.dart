import 'package:flutter/material.dart';

import '../../core/constants/app_sizes.dart';
import '../../core/constants/update.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/update/update_controller.dart';
import '../../core/update/update_models.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/dot_grid_background.dart';
import '../../core/widgets/m3_kit_extras.dart';
import '../chat/widgets/attachment_views.dart';
import 'update_parts.dart';

/// Full-screen "update to continue": a critical update, or a build older than
/// the server still supports. No way past it except updating.
class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({super.key, required this.controller});

  final UpdateController controller;

  @override
  Widget build(BuildContext context) => M3Themed(
    child: Builder(
      builder: (context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) => _build(context),
      ),
    ),
  );

  Widget _build(BuildContext context) {
    final p = context.palette;
    final release = controller.latest;
    final critical = release?.kind == UpdateKind.critical;
    final size = release != null && release.size > 0
        ? formatBytes(release.size)
        : '';
    return Scaffold(
      backgroundColor: p.background,
      body: Stack(
        children: [
          const Positioned.fill(child: DotGridBackground()),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: UpdateSizes.maxWidth,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: UpdateSizes.heroCircle,
                          height: UpdateSizes.heroCircle,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: p.accent.withValues(alpha: M3Sizes.tagAlpha),
                          ),
                          child: Center(
                            child: AppIcon(
                              critical
                                  ? UpdateIcons.shield
                                  : UpdateIcons.update,
                              size: UpdateSizes.heroIcon,
                              color: p.accent,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      Semantics(
                        header: true,
                        child: Text(
                          UpdateStrings.requiredTitle,
                          textAlign: TextAlign.center,
                          style: context.text.headline,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        critical
                            ? UpdateStrings.requiredCritical
                            : UpdateStrings.requiredBody,
                        textAlign: TextAlign.center,
                        style: context.text.body.copyWith(
                          color: p.textSecondary,
                        ),
                      ),
                      if (release != null) ...[
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          UpdateStrings.versionLine(release.version, size),
                          textAlign: TextAlign.center,
                          style: AppTextStyles.caption.copyWith(
                            color: p.textTertiary,
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.xxl),
                      UpdateStatusBlock(controller: controller),
                      if (controller.phase == UpdatePhase.failed)
                        const SizedBox(height: AppSpacing.lg),
                      UpdateButtons(controller: controller),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Puts [UpdateRequiredScreen] above the whole app (navigator, sheets
/// included) while an update is required, and swallows the back button.
class UpdateGate extends StatefulWidget {
  const UpdateGate({super.key, required this.controller, required this.child});

  final UpdateController controller;
  final Widget child;

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<bool> didPopRoute() async => widget.controller.blocking;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, child) => Stack(
      children: [
        Positioned.fill(child: child!),
        if (widget.controller.blocking)
          Positioned.fill(
            child: UpdateRequiredScreen(controller: widget.controller),
          ),
      ],
    ),
    child: widget.child,
  );
}
