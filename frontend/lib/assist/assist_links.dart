import 'dart:async';

import '../core/constants/assist.dart';
import '../core/notify/notification_center.dart';
import '../core/notify/notify_target.dart';
import '../core/platform/deep_links.dart';

/// App side of the assistant overlay's hand-offs: `sparky://chat/<id>`
/// ("Open in sparky") and `sparky://settings/assistant` (the gear next to
/// sparky in the system's Digital assistant settings). Both go through the
/// same router as a tapped notification.
abstract final class AssistLinks {
  static bool _started = false;

  static Future<void> init() async {
    if (_started || !DeepLinks.supported) return;
    _started = true;
    DeepLinks.links.listen(_open);
    final first = await DeepLinks.initial();
    if (first != null) _open(first);
  }

  static void _open(Uri uri) {
    final target = targetFor(uri);
    if (target != null) NotificationCenter.instance.open(target);
  }

  /// The in-app target of an overlay link, or null for other links.
  static NotifyTarget? targetFor(Uri uri) {
    if (uri.scheme != AssistConfig.linkScheme) return null;
    final id = uri.pathSegments.isEmpty ? '' : uri.pathSegments.first;
    if (id.isEmpty) return null;
    return switch (uri.host) {
      AssistConfig.chatHost => ChatTarget(id),
      AssistConfig.settingsHost => SettingsTarget(id),
      _ => null,
    };
  }
}
