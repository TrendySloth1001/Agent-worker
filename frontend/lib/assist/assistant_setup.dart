import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/constants/assist.dart';

/// Whether sparky is the default digital assistant, and the system's
/// screen-context switches (null when the phone does not say).
class AssistantStatus {
  const AssistantStatus({
    required this.isDefault,
    this.screenText,
    this.screenshot,
    this.manufacturer = '',
  });

  final bool isDefault;
  final bool? screenText;
  final bool? screenshot;
  final String manufacturer;

  bool get isNothing =>
      manufacturer.toLowerCase().contains(AssistConfig.nothingManufacturer);

  static const unknown = AssistantStatus(isDefault: false);
}

/// The app's `app/assistant` channel (AssistantSetup.kt).
class AssistantSetup {
  const AssistantSetup();

  static const _channel = MethodChannel(AssistSetupChannel.name);

  static bool get supported => !kIsWeb && Platform.isAndroid;

  Future<AssistantStatus> status() async {
    if (!supported) return AssistantStatus.unknown;
    try {
      final m = await _channel.invokeMapMethod<String, Object?>(
        AssistSetupChannel.status,
      );
      if (m == null) return AssistantStatus.unknown;
      return AssistantStatus(
        isDefault: m[AssistSetupChannel.isDefault] == true,
        screenText: m[AssistSetupChannel.screenText] as bool?,
        screenshot: m[AssistSetupChannel.screenshot] as bool?,
        manufacturer: m[AssistSetupChannel.manufacturer] as String? ?? '',
      );
    } catch (_) {
      return AssistantStatus.unknown;
    }
  }

  /// Asks to become the assistant: 'granted', 'settings' (the system page
  /// opened instead) or 'failed'.
  Future<String> request() => _string(AssistSetupChannel.request);

  Future<void> openSettings() => _string(AssistSetupChannel.openSettings);

  /// Opens the overlay over the app (no screen to share).
  Future<void> tryIt() => _string(AssistSetupChannel.tryIt);

  Future<String> _string(String method) async {
    if (!supported) return AssistSetupChannel.failed;
    try {
      final r = await _channel.invokeMethod<Object?>(method);
      return r is String
          ? r
          : (r == true ? AssistSetupChannel.ok : AssistSetupChannel.failed);
    } catch (_) {
      return AssistSetupChannel.failed;
    }
  }
}
