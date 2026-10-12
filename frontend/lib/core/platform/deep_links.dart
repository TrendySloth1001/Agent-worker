import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../constants/sso_constants.dart';

/// sparky:// links from MainActivity: the one the app was launched with
/// (cold start) and the ones that arrive while it runs.
abstract final class DeepLinks {
  static const _channel = MethodChannel(DeepLinkChannel.name);
  static final _links = StreamController<Uri>.broadcast();
  static bool _listening = false;

  static bool get supported => !kIsWeb && Platform.isAndroid;

  /// Links arriving while the app runs.
  static Stream<Uri> get links {
    if (!_listening && supported) {
      _listening = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method != DeepLinkChannel.onLink) return;
        final uri = Uri.tryParse(call.arguments as String? ?? '');
        if (uri != null) _links.add(uri);
      });
    }
    return _links.stream;
  }

  static Future<Uri?>? _initial;

  /// The launch link (null when there is none). Fetched once and shared, so
  /// every listener (GitHub sign-in, connected apps) sees it.
  static Future<Uri?> initial() => _initial ??= _fetchInitial();

  static Future<Uri?> _fetchInitial() async {
    if (!supported) return null;
    try {
      final raw = await _channel.invokeMethod<String>(
        DeepLinkChannel.initialLink,
      );
      return raw == null ? null : Uri.tryParse(raw);
    } catch (_) {
      return null;
    }
  }
}
