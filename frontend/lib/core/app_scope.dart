import 'package:flutter/widgets.dart';

import '../data/chat_api.dart';
import '../features/settings/settings_controller.dart';
import '../features/settings/usage_controller.dart';

/// Shared app objects, available below the root.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.settings,
    required this.usage,
    required this.api,
    required this.baseUrl,
    required super.child,
  });

  final SettingsController settings;
  final UsageController usage;
  final ChatApi api;
  final String baseUrl;

  static AppScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope old) =>
      settings != old.settings ||
      usage != old.usage ||
      api != old.api ||
      baseUrl != old.baseUrl;
}
