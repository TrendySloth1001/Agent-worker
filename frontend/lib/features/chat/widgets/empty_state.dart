import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_palette.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(AppStrings.emptyTitle, style: context.text.display),
          const SizedBox(height: AppSpacing.sm),
          Text(AppStrings.emptySubtitle, style: context.text.bodySmall),
        ],
      ),
    );
  }
}
