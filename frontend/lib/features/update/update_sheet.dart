import 'package:flutter/material.dart';

import '../../core/constants/app_sizes.dart';
import '../../core/constants/settings_copy.dart';
import '../../core/constants/update.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/update/update_controller.dart';
import '../../core/update/update_models.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/dot_grid_background.dart';
import '../../core/widgets/m3_kit_extras.dart';
import '../chat/widgets/attachment_views.dart';
import '../settings/widgets/settings_kit.dart';
import 'update_parts.dart';

/// "A new sparky is ready": the bottom sheet for feature and major updates.
/// Feature updates are compact; major ones get a richer header and the full
/// list of highlights.
class UpdateSheet extends StatelessWidget {
  const UpdateSheet({super.key, required this.controller});

  final UpdateController controller;

  /// Opens the sheet. [markShown] records it for the "Later" cadence; the
  /// About row opens it without counting as a prompt.
  static Future<void> show(
    BuildContext context, {
    UpdateController? controller,
    bool markShown = false,
  }) {
    final c = controller ?? UpdateController.instance;
    if (c.latest == null) return Future.value();
    if (markShown) c.markSheetShown();
    return showM3Sheet<void>(
      context,
      builder: (_) => UpdateSheet(controller: c),
    );
  }

  /// Shows the sheet if it is due (once per session). Returns whether it did.
  static Future<bool> maybeShow(
    BuildContext context, {
    UpdateController? controller,
  }) async {
    final c = controller ?? UpdateController.instance;
    if (!c.sheetDue) return false;
    await show(context, controller: c, markShown: true);
    return true;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final release = controller.latest;
      if (release == null) return const SizedBox.shrink();
      return _Body(controller: controller, release: release);
    },
  );
}

class _Body extends StatelessWidget {
  const _Body({required this.controller, required this.release});

  final UpdateController controller;
  final UpdateRelease release;

  bool get _major => release.kind == UpdateKind.major;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final title = release.title.isEmpty
        ? UpdateStrings.fallbackTitle
        : release.title;
    final busy =
        controller.phase != UpdatePhase.idle &&
        controller.phase != UpdatePhase.ready &&
        controller.phase != UpdatePhase.failed;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenPadding,
          0,
          AppSpacing.screenPadding,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _major ? _majorHeader(context, title) : _header(context, title),
            const SizedBox(height: AppSpacing.lg),
            if (_major && release.notes.isNotEmpty)
              SettingsGroup(
                entries: [
                  for (final n in release.notes) GroupEntry(_Highlight(n)),
                ],
              )
            else if (release.notes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: SettingsSizes.headerInset,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final n in release.notes.take(UpdateSizes.noteLines))
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: _Bullet(n),
                      ),
                  ],
                ),
              ),
            SizedBox(height: busy ? AppSpacing.md : AppSpacing.lg),
            UpdateStatusBlock(controller: controller),
            if (controller.phase == UpdatePhase.failed)
              const SizedBox(height: AppSpacing.lg),
            UpdateButtons(
              controller: controller,
              secondaryLabel: UpdateStrings.later,
              onSecondary: () => Navigator.of(context).maybePop(),
            ),
            if (controller.phase == UpdatePhase.downloading ||
                controller.phase == UpdatePhase.installing) ...[
              const SizedBox(height: AppSpacing.md),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: Text(
                    UpdateStrings.hide,
                    style: context.text.label.copyWith(color: p.textSecondary),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, String title) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: SettingsSizes.headerInset,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            UpdateStrings.kickerFeature,
            style: AppTextStyles.label.copyWith(color: p.accent),
          ),
          const SizedBox(height: AppSpacing.sm),
          Semantics(
            header: true,
            child: Text(title, style: context.text.headline),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            _versionLine(),
            style: context.text.caption.copyWith(color: p.textTertiary),
          ),
        ],
      ),
    );
  }

  /// Major: a dotted hero with the icon, kicker, title and version.
  Widget _majorHeader(BuildContext context, String title) {
    final p = context.palette;
    return M3Card(
      padding: EdgeInsets.zero,
      child: Stack(
        children: [
          const Positioned.fill(child: DotGridBackground()),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                children: [
                  Container(
                    width: UpdateSizes.heroCircle,
                    height: UpdateSizes.heroCircle,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: p.accent.withValues(alpha: M3Sizes.tagAlpha),
                    ),
                    child: Center(
                      child: AppIcon(
                        UpdateIcons.rocket,
                        size: UpdateSizes.heroIcon,
                        color: p.accent,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    UpdateStrings.kickerMajor,
                    style: AppTextStyles.label.copyWith(color: p.accent),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Semantics(
                    header: true,
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: context.text.headline,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _versionLine(),
                    style: context.text.caption.copyWith(color: p.textTertiary),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _versionLine() => UpdateStrings.versionLine(
    release.version,
    release.size > 0 ? formatBytes(release.size) : '',
  );
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: Container(
            width: AppSizes.dot,
            height: AppSizes.dot,
            decoration: BoxDecoration(shape: BoxShape.circle, color: p.accent),
          ),
        ),
        const SizedBox(width: UpdateSizes.bulletGap),
        Expanded(
          child: Text(
            text,
            style: context.text.body.copyWith(color: p.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _Highlight extends StatelessWidget {
  const _Highlight(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xxs),
            child: AppIcon(
              UpdateIcons.check,
              size: UpdateSizes.bulletIcon,
              color: p.accent,
            ),
          ),
          const SizedBox(width: UpdateSizes.bulletGap),
          Expanded(child: Text(text, style: context.text.body)),
        ],
      ),
    );
  }
}
