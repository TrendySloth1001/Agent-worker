import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/widget_chart.dart';
import '../../../../core/haptics.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/widgets/app_icon.dart';
import 'chart_model.dart';
import 'chart_views.dart';

/// Full-page chart for a closer look.
class ChartFullscreen extends StatelessWidget {
  const ChartFullscreen({super.key, required this.spec, required this.title});
  final ChartSpec spec;
  final String title;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.background,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: p.border)),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () {
                      Haptics.tap();
                      Navigator.of(context).pop();
                    },
                    icon: AppIcon(
                      ChartIcons.back,
                      color: p.textPrimary,
                      semanticLabel: 'Back',
                    ),
                  ),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.label,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: LayoutBuilder(
                  builder: (context, c) =>
                      c.maxHeight < ChartSizes.fullscreenMinHeight
                      ? SingleChildScrollView(child: ChartPanel(spec: spec))
                      : ChartPanel(spec: spec, fill: true),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
