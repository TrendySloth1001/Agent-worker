import 'package:flutter/material.dart';

/// The app-wide snackbar host (MaterialApp.scaffoldMessengerKey), for
/// messages that outlive the screen that caused them, e.g. a GitHub sign-in
/// finishing after a cold start from a deep link.
abstract final class AppMessenger {
  static final key = GlobalKey<ScaffoldMessengerState>();

  static void show(String text, {Duration? duration}) {
    final m = key.currentState;
    if (m == null) return;
    m.hideCurrentSnackBar();
    final content = Text(text);
    m.showSnackBar(
      duration == null
          ? SnackBar(content: content)
          : SnackBar(content: content, duration: duration),
    );
  }
}
