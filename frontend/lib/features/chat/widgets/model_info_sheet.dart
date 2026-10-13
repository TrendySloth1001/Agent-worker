import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/wait_copy.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/m3_kit_extras.dart';
import '../../../core/widgets/model_logo.dart';
import '../../../data/ai_model.dart';
import '../../settings/settings_pages.dart' show isOwner;

/// Opens the "about this model" sheet for a reply. Normal users see a
/// friendly summary; the owner also sees the raw model id.
Future<void> showModelInfoSheet(
  BuildContext context, {
  required String modelId,
  required String name,
  AiModel? model,
}) {
  Haptics.tap();
  final owner = isOwner();
  return showM3Sheet<void>(
    context,
    builder: (_) => ModelInfoSheet(
      modelId: modelId,
      name: name,
      model: model,
      owner: owner,
    ),
  );
}

class ModelInfoSheet extends StatelessWidget {
  const ModelInfoSheet({
    super.key,
    required this.modelId,
    required this.name,
    this.model,
    this.owner = false,
  });

  final String modelId;
  final String name;

  /// Server description of the model, when the list has loaded.
  final AiModel? model;

  /// Owner view adds the raw model id.
  final bool owner;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    final p = context.palette;
    final m = model;
    final rows = <(String, String, Widget?)>[
      if (m?.maker != null)
        (
          ModelInfoStrings.madeBy,
          m!.maker!,
          ModelLogo(modelId, size: AppSizes.modelLabelLogo),
        ),
      if (m?.about != null) (ModelInfoStrings.goodAt, m!.about!, null),
      if (m?.contextTokens != null)
        (
          ModelInfoStrings.memory,
          ModelInfoStrings.memoryOf(m!.contextTokens!),
          null,
        ),
      if (ModelInfoStrings.speeds[m?.speed] != null)
        (ModelInfoStrings.feel, ModelInfoStrings.speeds[m!.speed]!, null),
      if (owner) (ModelInfoStrings.modelId, modelId, null),
    ];
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenPadding,
          0,
          AppSpacing.screenPadding,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(ModelInfoStrings.title, style: t.caption),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                ModelLogo(modelId, size: AppSizes.modelSheetLogo),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: Text(name, style: t.title)),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            if (rows.isEmpty)
              Text(
                ModelInfoStrings.noInfo,
                style: t.bodySmall.copyWith(color: p.textSecondary),
              ),
            for (final (label, value, logo) in rows) ...[
              Divider(height: 1, color: p.border),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: AppSizes.modelSheetLabelWidth,
                      child: Text(label, style: t.caption),
                    ),
                    if (logo != null) ...[
                      logo,
                      const SizedBox(width: AppSpacing.sm),
                    ],
                    Expanded(
                      child: label == ModelInfoStrings.modelId
                          ? SelectableText(value, style: t.code)
                          : Text(value, style: t.body),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
