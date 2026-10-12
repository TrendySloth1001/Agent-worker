import 'package:flutter/services.dart';

/// One place for every vibration, so the feel stays consistent.
abstract final class Haptics {
  /// Master switch, set from settings.
  static bool enabled = true;

  /// Buttons, chips, list picks.
  static void tap() => _run(HapticFeedback.selectionClick);

  /// Message sent.
  static void send() => _run(HapticFeedback.lightImpact);

  /// Pulse while the model is generating.
  static void tick() => _run(HapticFeedback.selectionClick);

  /// Reply arrived.
  static void received() => _run(HapticFeedback.mediumImpact);

  /// Request failed.
  static void error() => _run(HapticFeedback.heavyImpact);

  /// Dictation started / stopped.
  static void recordStart() => _run(HapticFeedback.mediumImpact);
  static void recordStop() => _run(HapticFeedback.lightImpact);

  static void _run(Future<void> Function() fn) {
    if (enabled) fn();
  }
}
