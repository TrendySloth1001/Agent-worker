import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../constants/sso_constants.dart';

/// A bundled brand logo: the GitHub mark (tinted, like an icon) or the
/// four-color Google "G" (never tinted). Works before sign-in.
class BrandMark extends StatelessWidget {
  const BrandMark.github({super.key, required this.size, this.color})
    : asset = SsoAssets.githubMark,
      tinted = true;

  const BrandMark.google({super.key, required this.size})
    : asset = SsoAssets.googleG,
      tinted = false,
      color = null;

  final String asset;
  final double size;
  final bool tinted;

  /// Tint of the GitHub mark; the default is the icon color around it.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? IconTheme.of(context).color;
    return SvgPicture.asset(
      asset,
      width: size,
      height: size,
      excludeFromSemantics: true,
      colorFilter: tinted && tint != null
          ? ColorFilter.mode(tint, BlendMode.srcIn)
          : null,
    );
  }
}
