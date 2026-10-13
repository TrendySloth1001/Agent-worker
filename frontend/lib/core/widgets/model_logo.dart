import 'package:flutter/widgets.dart';

import '../constants/app_sizes.dart';
import '../constants/model_logos.dart';
import '../theme/app_palette.dart';
import 'app_icon.dart';

/// The real logo of the family a model belongs to (see [ModelLogos]).
/// Monochrome marks take [color] (the ink color by default); full-color
/// logos keep their own.
class ModelLogo extends StatelessWidget {
  const ModelLogo(
    this.modelId, {
    super.key,
    this.provider,
    this.size = AppIconSize.sm,
    this.color,
  });

  /// `provider:model` id, or a bare model id with [provider] given apart.
  final String? modelId;
  final String? provider;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => AppIcon(
    ModelLogos.forModelId(modelId, provider: provider),
    size: size,
    color: color ?? context.palette.textPrimary,
  );
}
