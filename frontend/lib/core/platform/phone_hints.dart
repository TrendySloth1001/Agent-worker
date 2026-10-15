import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../constants/location.dart';

/// Coarse facts about the phone, read natively with no permission: SIM and
/// network country (ISO-2), time zone id and locale. Sent with chat requests
/// so the server can work out a rough location when a question needs one.
/// Never throws; an unavailable phone gives an empty map.
abstract final class PhoneHints {
  static const _channel = MethodChannel(LocationConfig.channel);

  static Map<String, String>? _cache;
  static DateTime? _at;

  static bool get supported => !kIsWeb && Platform.isAndroid;

  @visibleForTesting
  static void debugSet(Map<String, String>? hints) {
    _cache = hints;
    _at = hints == null ? null : DateTime.now();
  }

  /// The hints, non-empty values only. Network country can change when
  /// travelling, so an answer is reused for a few minutes, not forever.
  static Future<Map<String, String>> read() async {
    final at = _at;
    if (_cache != null &&
        at != null &&
        DateTime.now().difference(at) < const Duration(minutes: 10)) {
      return _cache!;
    }
    if (!supported) return const {};
    try {
      final raw = await _channel
          .invokeMapMethod<String, String>(LocationConfig.hintsMethod)
          .timeout(LocationConfig.readTimeout);
      final hints = <String, String>{
        for (final e in (raw ?? const <String, String>{}).entries)
          if (e.value.trim().isNotEmpty) e.key: e.value.trim(),
      };
      _cache = hints;
      _at = DateTime.now();
      return hints;
    } catch (e) {
      if (kDebugMode) debugPrint('[phone hints] failed: $e');
      return _cache ?? const {};
    }
  }
}
