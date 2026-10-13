import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/constants/telemetry.dart';
import 'api_client.dart';
import 'chat_api.dart';
import 'telemetry.dart';

/// Filters shared by every telemetry call; null means all.
class TelemetryFilters {
  const TelemetryFilters({this.provider, this.model, this.kind});

  final String? provider, model, kind;

  Map<String, String> get query => {
    'provider': ?provider,
    'model': ?model,
    'kind': ?kind,
  };

  TelemetryFilters copyWith({
    String? Function()? provider,
    String? Function()? model,
    String? Function()? kind,
  }) => TelemetryFilters(
    provider: provider == null ? this.provider : provider(),
    model: model == null ? this.model : model(),
    kind: kind == null ? this.kind : kind(),
  );

  bool matches(TelemetryEvent e) =>
      (provider == null || e.provider == provider) &&
      (model == null || e.model == model) &&
      (kind == null || e.purpose == kind || e.kind == kind);
}

/// Owner-only telemetry endpoints. All calls throw on failure (403 for others).
class TelemetryApi {
  TelemetryApi(this.baseUrl);

  final String baseUrl;

  Uri _uri(String path, Map<String, String> q) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: q.isEmpty ? null : q);

  Future<Map<String, dynamic>> _get(String path, Map<String, String> q) async {
    final response = await apiHttp
        .get(_uri(path, q), headers: apiHeaders())
        .timeout(TelemetryDurations.timeout);
    if (response.statusCode >= 400) {
      // Owner-only screen: keeps the raw server detail.
      throw ApiException(
        rawErrorMessage(response.body) ?? 'HTTP ${response.statusCode}',
        status: response.statusCode,
        code: errorCode(response.body),
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<TelemetryOverview> overview(String window, TelemetryFilters f) async =>
      TelemetryOverview.fromJson(
        await _get(TelemetryPaths.overview, {'window': window, ...f.query}),
      );

  Future<TelemetrySeries> series(
    String window,
    String? bucket,
    TelemetryFilters f,
  ) async => TelemetrySeries.fromJson(
    await _get(TelemetryPaths.timeseries, {
      'window': window,
      'bucket': ?bucket,
      ...f.query,
    }),
  );

  Future<EventsPage> events(
    TelemetryFilters f, {
    String? before,
    bool failedOnly = false,
    int limit = TelemetrySizes.pageSize,
  }) async => EventsPage.fromJson(
    await _get(TelemetryPaths.events, {
      'limit': '$limit',
      'before': ?before,
      if (failedOnly) 'ok': 'false',
      ...f.query,
    }),
  );

  /// New events as the server records them. Ends when [client] is closed or
  /// the connection drops; the caller reconnects.
  /// [onOpen] runs once the server accepted the stream.
  Stream<TelemetryEvent> live(
    http.Client client, {
    void Function()? onOpen,
  }) async* {
    final request = http.Request('GET', _uri(TelemetryPaths.stream, const {}))
      ..headers.addAll({...apiHeaders(), 'Accept': 'text/event-stream'});
    final response = await AuthClient(
      client,
    ).send(request).timeout(TelemetryDurations.timeout);
    if (response.statusCode != 200) {
      await response.stream.drain<void>().catchError((_) {});
      throw ApiException(
        'HTTP ${response.statusCode}',
        status: response.statusCode,
      );
    }
    onOpen?.call();
    final lines = response.stream
        .timeout(
          TelemetryDurations.streamIdle,
          onTimeout: (sink) => sink.addError(TimeoutException('idle')),
        )
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    var event = '';
    final data = StringBuffer();
    await for (final line in lines) {
      if (line.isEmpty) {
        if (event == TelemetryPaths.usageEvent && data.isNotEmpty) {
          final decoded = jsonDecode(data.toString());
          if (decoded is Map<String, dynamic>) {
            yield TelemetryEvent.fromJson(decoded);
          }
        }
        event = '';
        data.clear();
      } else if (line.startsWith('event:')) {
        event = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        data.write(line.substring(5).trimLeft());
      }
    }
  }
}
