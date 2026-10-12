import 'package:flutter/material.dart';

/// The app-wide snackbar host (MaterialApp.scaffoldMessengerKey), for
/// messages that outlive the screen that caused them, e.g. a GitHub sign-in
/// finishing after a cold start from a deep link.
abstract final class AppMessenger {
  static final key = GlobalKey<ScaffoldMessengerState>();

  static void show(String text) {
    final m = key.currentState;
    if (m == null) return;
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(content: Text(text)));
  }
}
