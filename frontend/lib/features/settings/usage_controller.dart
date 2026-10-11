import 'package:flutter/foundation.dart';

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
    health = (results[1] as HealthStatus?) ?? const HealthStatus(null);
    loading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
