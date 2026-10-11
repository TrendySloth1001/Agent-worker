import 'package:flutter/material.dart';

import 'theme/app_palette.dart';

/// The app-wide snackbar host (MaterialApp.scaffoldMessengerKey), for
/// messages that outlive the screen that caused them, e.g. a GitHub sign-in
/// finishing after a cold start from a deep link.
abstract final class AppMessenger {
  static final key = GlobalKey<ScaffoldMessengerState>();

  static void show(String text) {
    final m = key.currentState;
    if (m == null) return;
    final c = m.context;
    m.hideCurrentSnackBar();
    m.showSnackBar(
      SnackBar(
        backgroundColor: c.palette.surfaceHigh,
        content: Text(text, style: c.text.label),
      ),
    );
  }
}
