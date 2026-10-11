import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../data/sso_api.dart';
import '../constants/sso_constants.dart';

/// Native "Sign in with Google" through Android's Credential Manager (the
/// system bottom sheet), implemented in MainActivity. Returns an ID token
/// whose audience is [serverClientId], the server's WEB OAuth client id
/// (GET /auth/providers). No google-services.json: Google matches this app
/// by package name + signing SHA-1 against an Android OAuth client in the
/// same Google Cloud project.
abstract final class GoogleAuth {
  static const _channel = MethodChannel(GoogleAuthChannel.name);

  static bool get supported => !kIsWeb && Platform.isAndroid;

  /// The ID token, or null when the person closed the sheet (or, with
  /// [auto], when no account has authorized the app yet). Throws
  /// [SsoException] with a readable message otherwise.
  static Future<String?> idToken(
    String serverClientId, {
    bool auto = false,
  }) async {
    if (!supported) throw const SsoException(SsoStrings.googleUnavailable);
    try {
      final token = await _channel
          .invokeMethod<String>(GoogleAuthChannel.idToken, {
            'serverClientId': serverClientId,
            'mode': auto
                ? GoogleAuthChannel.modeAuto
                : GoogleAuthChannel.modeButton,
          });
      if (token == null || token.isEmpty) {
        throw const SsoException(SsoStrings.googleNoToken);
      }
      return token;
    } on PlatformException catch (e) {
      switch (e.code) {
        case GoogleAuthChannel.cancelled:
          return null;
        case GoogleAuthChannel.noAccount:
          if (auto) return null;
          throw const SsoException(SsoStrings.googleNoAccount);
      }
      final m = e.message ?? '';
      // 10 / 28444: the OAuth clients don't match this build (package, SHA-1).
      if (RegExp(
        r'28444|DEVELOPER_ERROR|Developer console|\b10:',
      ).hasMatch(m)) {
        throw const SsoException(SsoStrings.googleMisconfigured);
      }
      throw const SsoException(SsoStrings.googleFailed);
    } on MissingPluginException {
      throw const SsoException(SsoStrings.googleUnavailable);
    }
  }

  /// Forgets the Google account chosen in this app (on sign-out), so the
  /// next sign-in asks again.
  static Future<void> signOut() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>(GoogleAuthChannel.signOut);
    } catch (_) {}
  }
}
