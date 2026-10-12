import 'package:flutter/material.dart';

import '../../core/constants/app_sizes.dart';
import '../../core/theme/app_palette.dart';
import '../../core/widgets/dot_grid_background.dart';
import '../../data/auth_models.dart';
import 'onboarding_screen.dart';
import 'onboarding_store.dart';

enum _Phase { deciding, tour, app }

/// Shows the first-run tour to a signed-in account that has not seen it,
/// then [child] (the chat, a fresh new chat). Returning accounts go
/// straight to [child].
class OnboardingGate extends StatefulWidget {
  const OnboardingGate({
    super.key,
    required this.user,
    required this.child,
    this.store,
  });

  final AuthUser? user;
  final Widget child;

  /// Defaults to [OnboardingStore.instance].
  final OnboardingStore? store;

  @override
  State<OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends State<OnboardingGate> {
  _Phase _phase = _Phase.deciding;

  OnboardingStore get _store => widget.store ?? OnboardingStore.instance;

  @override
  void initState() {
    super.initState();
    _decide();
  }

  Future<void> _decide() async {
    final user = widget.user;
    if (user == null) return _set(_Phase.app);
    switch (await _store.need(user)) {
      case TourNeed.show:
        _set(_Phase.tour);
      case TourNeed.skip:
        _set(_Phase.app);
      case TourNeed.unknown:
        // Older server: open the chat now, switch to the tour only if the
        // account turns out to be brand new.
        _set(_Phase.app);
        if (await _store.resolveUnknown(user)) _set(_Phase.tour);
    }
  }

  void _set(_Phase phase) {
    if (mounted && phase != _phase) setState(() => _phase = phase);
  }

  Future<void> _done() async {
    final user = widget.user;
    if (user != null) await _store.markDone(user);
    _set(_Phase.app);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : AppDurations.slow,
      child: switch (_phase) {
        _Phase.deciding => const _Blank(key: ValueKey('deciding')),
        _Phase.tour => OnboardingScreen(
          key: const ValueKey('tour'),
          onDone: _done,
        ),
        _Phase.app => KeyedSubtree(
          key: const ValueKey('app'),
          child: widget.child,
        ),
      },
    );
  }
}

/// The page background while the flag is read (a frame or two).
class _Blank extends StatelessWidget {
  const _Blank({super.key});

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.palette.background,
    child: const DotGridBackground(),
  );
}
