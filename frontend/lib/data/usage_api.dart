import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/constants/app_sizes.dart';
import 'chat_api.dart';
import 'usage.dart';

/// Read-only calls used by the settings screen. All throw on failure.
class UsageApi {
  UsageApi(this.baseUrl);

  final String baseUrl;

  Future<Map<String, dynamic>> _get(String path) async {
    final response = await http
        .get(Uri.parse('$baseUrl$path'), headers: apiHeaders())
        .timeout(AppDurations.usageTimeout);
    if (response.statusCode >= 400) {
      throw Exception('HTTP ${response.statusCode}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<UsageSnapshot> fetchUsage() async =>
      UsageSnapshot.fromJson(await _get('/usage'));

  Future<HealthStatus> fetchHealth() async =>
      HealthStatus.fromJson(await _get('/health'));
}
