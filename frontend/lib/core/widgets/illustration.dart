import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../constants/illustrations.dart';
import '../theme/app_palette.dart';

/// Which hand-drawn scene to show.
enum IllustrationKind {
  login(IllustrationAssets.login),
  hello(IllustrationAssets.hello),
  github(IllustrationAssets.github),
  emptyKnowledge(IllustrationAssets.emptyKnowledge),
  emptyHistory(IllustrationAssets.emptyHistory);

  const IllustrationKind(this.asset);

  final String asset;
}

/// A theme-tinted line-art illustration (Open Peeps, CC0).
///
/// The SVGs are drawn with black ink, white paper and one red accent. Ink
/// becomes [AppPalette.textPrimary] and paper becomes [paper] (the page
/// background by default) so the art reads on both themes; red is kept.
/// Fades in with a small rise unless animations are disabled.
class Illustration extends StatelessWidget {
  const Illustration({
    super.key,
    required this.kind,
    this.height,
    this.paper,
    this.semanticLabel,
  });

  final IllustrationKind kind;
  final double? height;

  /// Color of the fills behind the lines; set it to the surface the art sits
  /// on when that is not the page background (cards, drawers).
  final Color? paper;

  /// Decorative by default.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    // Snap to the theme's end colors so a theme cross-fade doesn't parse a
    // new picture every frame.
    final p = context.palette.isDark ? AppPalette.dark : AppPalette.light;
    final h = height ?? IllustrationSizes.defaultHeight;
    final art = SvgPicture.asset(
      kind.asset,
      height: h,
      fit: BoxFit.contain,
      // Equal mappers share one parsed picture in flutter_svg's cache.
      colorMapper: _InkMapper(p.textPrimary, paper ?? p.background),
      excludeFromSemantics: semanticLabel == null,
      semanticsLabel: semanticLabel,
      placeholderBuilder: (_) => SizedBox(height: h),
    );
    if (MediaQuery.disableAnimationsOf(context)) return art;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: IllustrationDurations.entrance,
      curve: Curves.easeOutCubic,
      child: art,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * IllustrationSizes.rise),
          child: child,
        ),
      ),
    );
  }
}

@immutable
class _InkMapper extends ColorMapper {
  const _InkMapper(this.ink, this.paper);

  final Color ink, paper;

  @override
  Color substitute(
    String? id,
    String elementName,
    String attributeName,
    Color color,
  ) {
    final rgb = color.toARGB32() & 0xFFFFFF;
    if (rgb == IllustrationAssets.ink.toARGB32() & 0xFFFFFF) {
      return ink.withValues(alpha: ink.a * color.a);
    }
    if (rgb == IllustrationAssets.paper.toARGB32() & 0xFFFFFF) {
      return paper.withValues(alpha: paper.a * color.a);
    }
    return color;
  }

  @override
  bool operator ==(Object other) =>
      other is _InkMapper && other.ink == ink && other.paper == paper;

  @override
  int get hashCode => Object.hash(ink, paper);
}
