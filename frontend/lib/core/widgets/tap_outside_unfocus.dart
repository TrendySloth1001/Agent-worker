import 'package:flutter/material.dart';

/// Tapping anywhere that is not a field (or a button, a link, a handle...)
/// drops the focus, so the keyboard closes.
///
/// A translucent tap detector over the whole app: taps that something
/// below handles (buttons, the fields themselves, selection handles) win the
/// gesture arena and never reach it, and drags and scrolls are unaffected.
/// Kept out of the semantics tree so screen readers do not see a giant
/// "tap" target.
class TapOutsideUnfocus extends StatelessWidget {
  const TapOutsideUnfocus({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    excludeFromSemantics: true,
    onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
    child: child,
  );
}
