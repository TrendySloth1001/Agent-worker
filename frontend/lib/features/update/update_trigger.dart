import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../core/constants/update.dart';
import '../../core/update/update_controller.dart';
import 'update_sheet.dart';

/// Waits for a calm moment on the home screen and then shows the update
/// sheet, at most once per app session.
///
/// Calm means: an update sheet is due, the app has been open a while, the
/// screen is in the foreground and on top (no other screen, sheet or
/// onboarding above it), and the app is not busy answering.
class UpdateSheetTrigger {
  UpdateSheetTrigger({
    required this.context,
    required this.isBusy,
    UpdateController? controller,
  }) : _controller = controller ?? UpdateController.instance;

  /// The home screen's context (read lazily; it must stay mounted).
  final BuildContext Function() context;

  /// True while a reply is streaming or similar.
  final bool Function() isBusy;

  final UpdateController _controller;
  Timer? _timer;

  void start() {
    _timer ??= Timer.periodic(UpdateConfig.calmPoll, (_) => _tick());
  }

  void dispose() => _timer?.cancel();

  /// What's new was shown this launch: no update sheet until next time.
  void whatsNewShown() => _controller.suppressSheetThisSession();

  bool get _calm {
    if (!_controller.sheetDue || !_controller.openLongEnough) return false;
    if (isBusy()) return false;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      return false;
    }
    final ctx = context();
    if (!ctx.mounted) return false;
    return ModalRoute.of(ctx)?.isCurrent ?? false;
  }

  Future<void> _tick() async {
    if (!_calm) return;
    // Stop polling once the sheet is on screen: it is once per session.
    _timer?.cancel();
    _timer = null;
    final ctx = context();
    if (!ctx.mounted) return;
    await UpdateSheet.maybeShow(ctx, controller: _controller);
  }
}
