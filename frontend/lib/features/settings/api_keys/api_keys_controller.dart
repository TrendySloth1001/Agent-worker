import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/api_keys.dart';
import '../../../data/api_keys_api.dart';
import '../../auth/auth_controller.dart';

/// State of Settings → Your API keys: the provider rows, which one is busy,
/// the last live test result per provider and whether the intro was seen.
class ApiKeysController extends ChangeNotifier {
  ApiKeysController({
    ApiKeysApi? api,
    Future<SharedPreferences> Function()? prefs,
    String? userId,
  }) : _api = api ?? ApiKeysApi.instance,
       _prefs = prefs ?? SharedPreferences.getInstance,
       _userId = userId;

  final ApiKeysApi _api;
  final Future<SharedPreferences> Function() _prefs;
  final String? _userId;

  List<KeyProviderInfo> providers = [];
  bool hasValidKey = false;
  bool loading = false;
  bool loaded = false;
  String? error;

  /// Providers with a save / test / remove in flight.
  final busy = <String>{};

  /// Last live result per provider (cleared when the key changes or goes).
  final results = <String, KeyCheck>{};

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  String get _uid => _userId ?? AuthController.instance.user?.id ?? '';

  KeyProviderInfo? provider(String id) {
    for (final p in providers) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<void> reload() async {
    loading = true;
    error = null;
    _notify();
    try {
      final page = await _api.list();
      providers = page.providers;
      hasValidKey = page.hasValidKey;
      loaded = true;
    } catch (_) {
      error = ApiKeysStrings.loadFailed;
    }
    loading = false;
    _notify();
  }

  void _setKey(String id, SavedKey? key) {
    providers = [for (final p in providers) p.id == id ? p.withKey(key) : p];
    hasValidKey = providers.any((p) => p.key?.status == KeyStatus.valid);
  }

  /// Saves [key] for [id] and lets the server test it. Null when it failed to
  /// save; otherwise what the test found.
  Future<KeyCheck?> save(String id, String key) async {
    busy.add(id);
    results.remove(id);
    _notify();
    try {
      final r = await _api.save(id, key.trim());
      _setKey(id, r.key);
      results[id] = r.result;
      return r.result;
    } catch (_) {
      return null;
    } finally {
      busy.remove(id);
      _notify();
    }
  }

  Future<KeyCheck?> test(String id) async {
    busy.add(id);
    results.remove(id);
    _notify();
    try {
      final r = await _api.test(id);
      final current = provider(id)?.key;
      if (current != null && r.result != KeyCheck.network) {
        _setKey(
          id,
          current.withStatus(switch (r.result) {
            KeyCheck.valid => KeyStatus.valid,
            KeyCheck.invalid => KeyStatus.invalid,
            KeyCheck.quota => KeyStatus.quota,
            KeyCheck.network => current.status,
          }),
        );
      }
      results[id] = r.result;
      return r.result;
    } catch (_) {
      results[id] = KeyCheck.network;
      return KeyCheck.network;
    } finally {
      busy.remove(id);
      _notify();
    }
  }

  Future<bool> remove(String id) async {
    busy.add(id);
    _notify();
    try {
      await _api.remove(id);
      _setKey(id, null);
      results.remove(id);
      return true;
    } catch (_) {
      return false;
    } finally {
      busy.remove(id);
      _notify();
    }
  }

  // ---- intro ---------------------------------------------------------------

  Future<bool> introSeen() async {
    try {
      return (await _prefs()).getBool(ApiKeysPrefs.introSeen(_uid)) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> markIntroSeen() async {
    try {
      await (await _prefs()).setBool(ApiKeysPrefs.introSeen(_uid), true);
    } catch (_) {
      // Seen again next time: harmless.
    }
  }
}
