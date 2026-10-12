import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hugeicons/hugeicons.dart';

import '../constants/app_icons.dart';
import '../constants/app_sizes.dart';
import '../constants/brand_logos.dart';

/// The app's icon widget. Color falls back to the surrounding [IconTheme].
/// A [BrandLogos] entry draws the bundled official logo instead.
class AppIcon extends StatelessWidget {
  const AppIcon(
    this.icon, {
    super.key,
    this.size,
    this.color,
    this.semanticLabel,
  });

  final AppIconData icon;
  final double? size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final box = size ?? theme.size ?? AppIconSize.md;
    final glyph = SizedBox.square(
      dimension: box,
      child: Center(
        child: _logo(box, color ?? theme.color) ??
            HugeIcon(
              icon: icon,
              size: box * AppIconSize.optical,
              color: color ?? theme.color,
              strokeWidth: AppIconSize.stroke,
            ),
      ),
    );
    if (semanticLabel == null) return ExcludeSemantics(child: glyph);
    return Semantics(
      label: semanticLabel,
      child: ExcludeSemantics(child: glyph),
    );
  }

  Widget? _logo(double box, Color? tint) {
    final asset = BrandLogos.assetOf(icon);
    if (asset == null) return null;
    final side = box * AppIconSize.optical;
    return SvgPicture.asset(
      asset,
      width: side,
      height: side,
      colorFilter: BrandLogos.tinted(icon) && tint != null
          ? ColorFilter.mode(tint, BlendMode.srcIn)
          : null,
    );
  }
}
