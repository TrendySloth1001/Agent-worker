import 'package:flutter/foundation.dart';

import '../../core/constants/notify_copy.dart';
import '../../core/notify/notification_center.dart';
import '../../core/notify/notify_kind.dart';
import '../../core/notify/notify_target.dart';
import '../../data/usage.dart';
import '../../data/usage_api.dart';

/// Loads provider quotas, service stats and server health for settings.
class UsageController extends ChangeNotifier {
  UsageController(this._api);

  final UsageApi _api;

  UsageSnapshot? usage;
  HealthStatus? health;
  bool loading = false;
  bool _disposed = false;

  /// True when the last usage call failed (values shown may be stale).
  bool offline = false;

  KbStats? get kb => usage?.kb;

  Future<void> refresh() async {
    if (loading) return;
    loading = true;
    notifyListeners();
    final results = await Future.wait([
      _api.fetchUsage().then<Object?>((v) => v).catchError((_) => null),
      _api.fetchHealth().then<Object?>((v) => v).catchError((_) => null),
    ]);
    if (_disposed) return;
    final u = results[0] as UsageSnapshot?;
    offline = u == null;
    usage = u ?? usage;
    if (u != null) notifyLimits(u);
    health = (results[1] as HealthStatus?) ?? const HealthStatus(null);
    loading = false;
    notifyListeners();
  }

  /// A provider close to its daily limit: one heads-up (the center backs off
  /// for a while) that leads to the models page.
  void notifyLimits(UsageSnapshot u, {NotificationCenter? center}) {
    for (final p in u.providers) {
      final q = p.quota;
      final f = q?.fraction;
      if (!p.configured ||
          q == null ||
          q.period != QuotaPeriod.day ||
          f == null ||
          f < NotifyConfig.usageThreshold) {
        continue;
      }
      (center ?? NotificationCenter.instance).post(
        NotifyKind.usage,
        key: p.id,
        title: NotifyCopy.usageTitle,
        body: NotifyCopy.usageBody(p.name, (f * 100).floor()),
        target: const SettingsTarget('models'),
      );
      return;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
