import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import 'section_header.dart';

/// Fixed-height placeholder so the list does not jump when data arrives.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({
    super.key,
    this.height = AppSizes.providerSkeletonHeight,
  });

  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget bar(double factor) => FractionallySizedBox(
      widthFactor: factor,
      child: Container(
        height: AppSizes.skeletonBar,
        decoration: BoxDecoration(
          color: p.surfaceHigh,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
    );
    return SizedBox(
      height: height,
      child: FlatCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            bar(AppSizes.skeletonBarFactor),
            const SizedBox(height: AppSpacing.lg),
            bar(1),
            const SizedBox(height: AppSpacing.md),
            bar(1),
            const SizedBox(height: AppSpacing.md),
            bar(AppSizes.skeletonBarFactor),
          ],
        ),
      ),
    );
  }
}

/// Offline message with a retry button. [stale] shows a slim banner instead.
class UsageError extends StatelessWidget {
  const UsageError({
    super.key,
    required this.onRetry,
    this.stale = false,
    this.loading = false,
  });

  final VoidCallback onRetry;
  final bool stale;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final retry = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: loading
          ? null
          : () {
              Haptics.tap();
              onRetry();
            },
      child: Container(
        height: AppSizes.retryButtonHeight,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: p.accent, width: AppBorder.thin),
        ),
        child: Text(
          loading ? AppStrings.dash : AppStrings.retry,
          style: t.caption.copyWith(color: p.accent),
        ),
      ),
    );
    return FlatCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusDot(color: p.accent, hollow: true),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  stale ? AppStrings.staleData : AppStrings.serverOffline,
                  style: t.label.copyWith(color: p.accent),
                ),
              ),
            ],
          ),
          if (!stale) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(AppStrings.serverOfflineHint, style: t.bodySmall),
          ],
          const SizedBox(height: AppSpacing.md),
          Align(alignment: Alignment.centerLeft, child: retry),
        ],
      ),
    );
  }
}
