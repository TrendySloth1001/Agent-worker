import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/constants/telemetry.dart';
import '../../../data/telemetry.dart';
import '../../../data/telemetry_api.dart';

enum LiveState { connecting, live, offline }

/// State of the telemetry screen (or one model's detail screen): overview,
/// bucketed series, the event log and the live stream that feeds it.
class TelemetryController extends ChangeNotifier {
  TelemetryController(this._api, {this.locked = const TelemetryFilters()})
    : filters = locked;

  final TelemetryApi _api;

  /// Filters the screen cannot change (the model detail screen's model).
  final TelemetryFilters locked;

  String window = TelemetryWindows.hour;

  /// Null: the server picks the finest bucket the window allows.
  String? bucket;
  TelemetryFilters filters;
  bool failedOnly = false;
  bool paused = false;

  TelemetryOverview? overview;
  TelemetrySeries? series;
  final List<TelemetryEvent> events = [];
  String? _nextBefore;
  bool get hasMore => _nextBefore != null;

  bool loading = false;
  bool loadingMore = false;
  Object? error;
  LiveState live = LiveState.connecting;

  /// Events that arrived while paused (shown on resume).
  final List<TelemetryEvent> _held = [];
  int get heldCount => _held.length;

  /// Ids that arrived live since the last full load (row highlight).
  final Set<String> fresh = {};

  bool _disposed = false;
  http.Client? _streamClient;
  Timer? _refreshTimer;
  int _loadSeq = 0;

  void start() {
    unawaited(reload());
    unawaited(_liveLoop());
  }

  // ---- loading -------------------------------------------------------------

  Future<void> reload() async {
    final seq = ++_loadSeq;
    loading = true;
    notifyListeners();
    try {
      final results = await Future.wait([
        _api.overview(window, filters),
        _api.series(window, bucket, filters),
        _api.events(filters, failedOnly: failedOnly),
      ]);
      if (_disposed || seq != _loadSeq) return;
      overview = results[0] as TelemetryOverview;
      series = results[1] as TelemetrySeries;
      final page = results[2] as EventsPage;
      events
        ..clear()
        ..addAll(page.events);
      _nextBefore = page.nextBefore;
      fresh.clear();
      error = null;
    } catch (e) {
      if (_disposed || seq != _loadSeq) return;
      error = e;
    }
    loading = false;
    notifyListeners();
  }

  /// Totals and charts only; the log is kept (it is fed live).
  Future<void> _refreshAggregates() async {
    final seq = _loadSeq;
    try {
      final results = await Future.wait([
        _api.overview(window, filters),
        _api.series(window, bucket, filters),
      ]);
      if (_disposed || seq != _loadSeq) return;
      overview = results[0] as TelemetryOverview;
      series = results[1] as TelemetrySeries;
      notifyListeners();
    } catch (_) {
      // Keep the last good numbers; the next event retries.
    }
  }

  Future<void> loadMore() async {
    final before = _nextBefore;
    if (before == null || loadingMore) return;
    loadingMore = true;
    notifyListeners();
    final seq = _loadSeq;
    try {
      final page = await _api.events(
        filters,
        before: before,
        failedOnly: failedOnly,
      );
      if (_disposed || seq != _loadSeq) return;
      events.addAll(page.events);
      _nextBefore = page.nextBefore;
    } catch (_) {
      // Leave the cursor; the user can try again.
    }
    loadingMore = false;
    notifyListeners();
  }

  // ---- user changes ----------------------------------------------------------

  void setWindow(String w) {
    if (w == window) return;
    window = w;
    bucket = null;
    unawaited(reload());
  }

  void setBucket(String? b) {
    if (b == bucket) return;
    bucket = b;
    unawaited(_refreshAggregates());
  }

  void setProvider(String? p) {
    if (locked.provider != null) return;
    filters = filters.copyWith(provider: () => p);
    unawaited(reload());
  }

  void setKind(String? k) {
    if (locked.kind != null) return;
    filters = filters.copyWith(kind: () => k);
    unawaited(reload());
  }

  void setFailedOnly(bool v) {
    if (v == failedOnly) return;
    failedOnly = v;
    unawaited(reload());
  }

  void togglePause() {
    paused = !paused;
    if (!paused && _held.isNotEmpty) {
      for (final e in _held) {
        _insert(e);
      }
      _held.clear();
    }
    notifyListeners();
  }

  // ---- live ------------------------------------------------------------------

  Future<void> _liveLoop() async {
    var wait = TelemetryDurations.reconnectMin;
    while (!_disposed) {
      final client = http.Client();
      _streamClient = client;
      live = LiveState.connecting;
      notifyListeners();
      try {
        final stream = _api.live(
          client,
          onOpen: () {
            if (_disposed) return;
            live = LiveState.live;
            wait = TelemetryDurations.reconnectMin;
            notifyListeners();
          },
        );
        await for (final e in stream) {
          if (_disposed) break;
          _onEvent(e);
        }
      } catch (_) {
        // Dropped or refused; retry with backoff.
      } finally {
        client.close();
      }
      if (_disposed) return;
      live = LiveState.offline;
      notifyListeners();
      await Future<void>.delayed(wait);
      wait = Duration(
        milliseconds: math.min(
          wait.inMilliseconds * 2,
          TelemetryDurations.reconnectMax.inMilliseconds,
        ),
      );
    }
  }

  void _onEvent(TelemetryEvent e) {
    if (!filters.matches(e)) return;
    _scheduleRefresh();
    if (failedOnly && e.ok) return;
    if (paused) {
      _held.insert(0, e);
      if (_held.length > TelemetrySizes.maxEvents) _held.removeLast();
    } else {
      _insert(e);
    }
    notifyListeners();
  }

  void _insert(TelemetryEvent e) {
    if (events.any((x) => x.id == e.id)) return;
    // Newest first; live events are almost always the newest.
    var i = 0;
    while (i < events.length && events[i].order > e.order) {
      i++;
    }
    events.insert(i, e);
    fresh.add(e.id);
    if (events.length > TelemetrySizes.maxEvents) {
      events.removeLast();
      _nextBefore = events.last.id;
    }
  }

  void _scheduleRefresh() {
    if (_refreshTimer?.isActive ?? false) return;
    _refreshTimer = Timer(
      TelemetryDurations.liveRefresh,
      () => unawaited(_refreshAggregates()),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _refreshTimer?.cancel();
    _streamClient?.close();
    super.dispose();
  }
}
