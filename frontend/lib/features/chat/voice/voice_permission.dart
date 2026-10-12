import 'package:permission_handler/permission_handler.dart';

enum VoicePermissionState { granted, denied, blocked }

/// The microphone permission, behind an interface so tests need no platform.
abstract class VoicePermission {
  /// Current state, without asking.
  Future<VoicePermissionState> check();

  /// Shows the system prompt (a no-op result when it is blocked).
  Future<VoicePermissionState> request();

  Future<void> openSettings();
}

class SystemVoicePermission implements VoicePermission {
  const SystemVoicePermission();

  static VoicePermissionState _map(PermissionStatus s) {
    if (s.isGranted) return VoicePermissionState.granted;
    if (s.isPermanentlyDenied || s.isRestricted) {
      return VoicePermissionState.blocked;
    }
    return VoicePermissionState.denied;
  }

  @override
  Future<VoicePermissionState> check() async =>
      _map(await Permission.microphone.status);

  @override
  Future<VoicePermissionState> request() async =>
      _map(await Permission.microphone.request());

  @override
  Future<void> openSettings() async {
    await openAppSettings();
  }
}
