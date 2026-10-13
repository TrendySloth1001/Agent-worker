import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../constants/update.dart';

/// How an install attempt ended.
enum InstallStatus {
  /// Installed (the app is usually replaced before this is seen).
  success,

  /// The user closed the system confirmation.
  cancelled,

  /// The APK is signed by someone else; nothing was installed.
  signatureMismatch,

  /// Anything else.
  failed,
}

/// The device side of an update: the Kotlin `sparky/updater` channel.
abstract class UpdateInstaller {
  /// May this app install packages ("Install unknown apps" allowed)?
  Future<bool> canInstall();

  /// Opens the system page where the user allows it.
  Future<void> openInstallSettings();

  /// Installs the APK at [path] and waits for the result.
  Future<InstallStatus> install(String path);
}

class PlatformUpdateInstaller implements UpdateInstaller {
  PlatformUpdateInstaller();

  static const _channel = MethodChannel(UpdateConfig.channel);

  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<bool> canInstall() async {
    if (!_supported) return false;
    try {
      return await _channel.invokeMethod<bool>('canInstall') ?? false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> openInstallSettings() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('openInstallSettings');
    } on PlatformException {
      // Nothing to open; the user can find it in system settings.
    }
  }

  @override
  Future<InstallStatus> install(String path) async {
    if (!_supported) return InstallStatus.failed;
    try {
      final status = await _channel.invokeMethod<String>('install', {
        'path': path,
      });
      return switch (status) {
        'success' => InstallStatus.success,
        'cancelled' => InstallStatus.cancelled,
        'signature_mismatch' => InstallStatus.signatureMismatch,
        _ => InstallStatus.failed,
      };
    } on PlatformException {
      return InstallStatus.failed;
    }
  }
}
