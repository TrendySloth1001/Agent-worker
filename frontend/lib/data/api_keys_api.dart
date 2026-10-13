import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/constants/api_keys.dart';
import '../core/constants/app_config.dart';
import '../core/constants/app_sizes.dart';
import 'api_client.dart';
import 'chat_api.dart';

/// What a key's last check found (the server's `status`).
enum KeyStatus {
  untested,
  valid,
  invalid,
  quota;

  static KeyStatus parse(Object? v) => switch (v) {
    'valid' => valid,
    'invalid' => invalid,
    'quota' => quota,
    _ => untested,
  };
}

/// The outcome of a live test (the server's `result`).
enum KeyCheck {
  valid,
  invalid,
  quota,
  network;

  static KeyCheck parse(Object? v) => switch (v) {
    'valid' => valid,
    'invalid' => invalid,
    'quota' => quota,
    _ => network,
  };
}

/// A saved key as the server describes it: never the key itself.
class SavedKey {
  const SavedKey({
    required this.hint,
    required this.status,
    this.label = '',
    this.lastCheckedAt,
  });

  factory SavedKey.fromJson(Map<String, dynamic> j) => SavedKey(
    hint: j['hint'] as String? ?? '',
    status: KeyStatus.parse(j['status']),
    label: j['label'] as String? ?? '',
    lastCheckedAt: DateTime.tryParse(j['lastCheckedAt'] as String? ?? ''),
  );

  /// Last 4 characters.
  final String hint;
  final KeyStatus status;
  final String label;
  final DateTime? lastCheckedAt;

  SavedKey withStatus(KeyStatus s) => SavedKey(
    hint: hint,
    status: s,
    label: label,
    lastCheckedAt: lastCheckedAt,
  );
}

/// A provider the user can bring a key for (name and link come from the server).
class KeyProviderInfo {
  const KeyProviderInfo({
    required this.id,
    required this.name,
    this.blurb = '',
    this.keyUrl = '',
    this.placeholder = '',
    this.key,
  });

  factory KeyProviderInfo.fromJson(Map<String, dynamic> j) => KeyProviderInfo(
    id: j['id'] as String? ?? '',
    name: j['name'] as String? ?? '',
    blurb: j['blurb'] as String? ?? '',
    keyUrl: j['keyUrl'] as String? ?? '',
    placeholder: j['placeholder'] as String? ?? '',
    key: j['key'] is Map<String, dynamic>
        ? SavedKey.fromJson(j['key'] as Map<String, dynamic>)
        : null,
  );

  final String id, name, blurb, keyUrl, placeholder;
  final SavedKey? key;

  KeyProviderInfo withKey(SavedKey? k) => KeyProviderInfo(
    id: id,
    name: name,
    blurb: blurb,
    keyUrl: keyUrl,
    placeholder: placeholder,
    key: k,
  );
}

class KeysPage {
  const KeysPage({required this.providers, required this.hasValidKey});
  final List<KeyProviderInfo> providers;
  final bool hasValidKey;
}

/// Result of saving or testing a key.
class KeyTestResult {
  const KeyTestResult({required this.result, this.key});
  final KeyCheck result;

  /// The key as saved (null for a plain test).
  final SavedKey? key;
}

/// One day / model / provider row of the usage view.
class UsageBucket {
  const UsageBucket({
    required this.label,
    this.provider = '',
    required this.requests,
    required this.tokens,
    required this.errors,
    this.avgLatencyMs,
  });

  factory UsageBucket.fromJson(Map<String, dynamic> j, String labelKey) =>
      UsageBucket(
        label: j[labelKey] as String? ?? '',
        provider: j['provider'] as String? ?? '',
        requests: (j['requests'] as num?)?.toInt() ?? 0,
        tokens: (j['tokens'] as num?)?.toInt() ?? 0,
        errors: (j['errors'] as num?)?.toInt() ?? 0,
        avgLatencyMs: (j['avgLatencyMs'] as num?)?.toInt(),
      );

  /// A date (YYYY-MM-DD), a model id or a provider id.
  final String label, provider;
  final int requests, tokens, errors;
  final int? avgLatencyMs;
}

/// The caller's own key usage over a window.
class KeyUsage {
  const KeyUsage({
    required this.days,
    required this.requests,
    required this.errors,
    required this.tokens,
    this.avgLatencyMs,
    required this.byDay,
    required this.byModel,
    required this.byProvider,
    this.enabled = true,
  });

  factory KeyUsage.fromJson(Map<String, dynamic> j) {
    final t = j['totals'] as Map<String, dynamic>? ?? const {};
    List<UsageBucket> list(String key, String label) => [
      for (final x in j[key] as List? ?? const [])
        if (x is Map<String, dynamic>) UsageBucket.fromJson(x, label),
    ];
    return KeyUsage(
      days: (j['days'] as num?)?.toInt() ?? 7,
      enabled: j['enabled'] == true,
      requests: (t['requests'] as num?)?.toInt() ?? 0,
      errors: (t['errors'] as num?)?.toInt() ?? 0,
      tokens: (t['tokens'] as num?)?.toInt() ?? 0,
      avgLatencyMs: (t['avgLatencyMs'] as num?)?.toInt(),
      byDay: list('byDay', 'day'),
      byModel: list('byModel', 'model'),
      byProvider: list('byProvider', 'provider'),
    );
  }

  final int days, requests, errors, tokens;
  final int? avgLatencyMs;
  final bool enabled;
  final List<UsageBucket> byDay, byModel, byProvider;
}

/// Calls under /me/keys and /me/usage. All throw [ApiException].
class ApiKeysApi {
  ApiKeysApi._();
  static final instance = ApiKeysApi._();

  final _client = AuthClient();

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final request = http.Request(
      method,
      Uri.parse('${AppConfig.apiBaseUrl}$path'),
    )..headers.addAll(apiHeaders(json: body != null));
    if (body != null) request.body = jsonEncode(body);
    final response = await http.Response.fromStream(
      await _client.send(request).timeout(AppDurations.usageTimeout),
    );
    if (response.statusCode >= 400) {
      throw ApiException.fromResponse(response.body, response.statusCode);
    }
    return response;
  }

  Map<String, dynamic> _json(http.Response r) =>
      jsonDecode(r.body) as Map<String, dynamic>;

  Future<KeysPage> list() async {
    final j = _json(await _send('GET', ApiKeysPaths.keys));
    return KeysPage(
      providers: [
        for (final p in j['providers'] as List? ?? const [])
          if (p is Map<String, dynamic>) KeyProviderInfo.fromJson(p),
      ],
      hasValidKey: j['hasValidKey'] == true,
    );
  }

  /// Saves (or replaces) the key, then the server tests it.
  Future<KeyTestResult> save(String provider, String key) async {
    final j = _json(
      await _send('PUT', ApiKeysPaths.key(provider), body: {'key': key}),
    );
    return KeyTestResult(
      result: KeyCheck.parse(j['result']),
      key: j['key'] is Map<String, dynamic>
          ? SavedKey.fromJson(j['key'] as Map<String, dynamic>)
          : null,
    );
  }

  Future<KeyTestResult> test(String provider) async {
    final j = _json(await _send('POST', ApiKeysPaths.test(provider)));
    return KeyTestResult(result: KeyCheck.parse(j['result']));
  }

  Future<void> remove(String provider) async {
    await _send('DELETE', ApiKeysPaths.key(provider));
  }

  Future<KeyUsage> usage(int days) async => KeyUsage.fromJson(
    _json(await _send('GET', '${ApiKeysPaths.usage}?days=$days')),
  );
}
