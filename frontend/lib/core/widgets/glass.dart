import 'dart:ui';

import 'package:flutter/material.dart';

import '../constants/app_sizes.dart';
import '../theme/app_palette.dart';

/// Blurred, bordered capsule that floats over content.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = AppRadius.pill,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    return ClipRRect(
      borderRadius: shape,
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: AppSizes.glassBlur,
          sigmaY: AppSizes.glassBlur,
        ),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: context.palette.glass,
            borderRadius: shape,
            border: Border.all(
              color: context.palette.border,
              width: AppBorder.thin,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
