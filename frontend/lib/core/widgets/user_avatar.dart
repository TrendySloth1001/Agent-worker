import 'package:flutter/material.dart';

import '../../data/auth_models.dart';
import '../constants/app_sizes.dart';
import '../theme/app_palette.dart';

/// Round avatar: the account photo, or initials on a bordered circle.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.user,
    required this.size,
    this.bordered = true,
  });

  final AuthUser? user;
  final double size;

  /// Draws the thin outline.
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final bytes = user?.avatarBytes;
    final url = user?.avatarUrl;
    Widget initials() => Center(
      child: Text(
        user?.initials ?? '?',
        style: context.text.label.copyWith(
          fontSize: size * 0.36,
          letterSpacing: 0,
          color: p.textPrimary,
        ),
      ),
    );
    final Widget child;
    if (bytes != null) {
      child = Image.memory(
        bytes,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => initials(),
      );
    } else if (url != null && url.startsWith('https://')) {
      child = Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => initials(),
      );
    } else {
      child = initials();
    }
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: p.surfaceRaised,
        border: bordered
            ? Border.all(color: p.borderStrong, width: AppBorder.thin)
            : null,
      ),
      child: child,
    );
  }
}
