import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../constants/vault.dart';

/// Android's FLAG_SECURE: no screenshots, screen recording or Recents preview
/// while a secret is on screen. A no-op where the channel isn't there.
abstract final class SecureScreen {
  static const _channel = MethodChannel(VaultConfig.secureChannel);

  static Future<void> set(bool on) async {
    try {
      await _channel.invokeMethod<void>('setSecure', {'on': on});
    } catch (e) {
      if (kDebugMode) debugPrint('[secure] setSecure failed: $e');
    }
  }
}
