import 'dart:async';
import 'dart:isolate';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/chat_api.dart';
import '../../features/auth/auth_controller.dart';
import '../constants/errors.dart';
import '../update/update_controller.dart';
import 'breadcrumbs.dart';
import 'error_queue.dart';
import 'error_settings.dart';
import 'errors_api.dart';
import 'session_tracker.dart';

/// The Kotlin side: the crash file and the previous process's exit reason (`sparky/diagnostics`).
typedef NativeDiagnostics = Future<Map<String, dynamic>?> Function();

Future<Map<String, dynamic>?> _platformDiagnostics() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
  try {
    const channel = MethodChannel(ErrorsConfig.diagnosticsChannel);
    final r = await channel.invokeMapMethod<String, dynamic>('takePending');
    return r;
  } catch (_) {
    return null;
  }
}

/// Collects Dart and platform errors, keeps the last 30 breadcrumbs and a small offline queue,
/// and sends batches to the sparky server when it is allowed (Settings → "Send crash reports";
/// the owner is always on). It sends only a type, a short message, a stack, the build, a few
/// device facts and the breadcrumbs, never chat content.
class ErrorReporter with WidgetsBindingObserver {
  ErrorReporter({
    required SharedPreferences prefs,
    ErrorsApi? api,
    this.assist = false,
    bool Function()? isOwner,
    bool Function()? signedIn,
    this.build = 0,
    DateTime Function()? clock,
    Breadcrumbs? crumbs,
    NativeDiagnostics? native,
    Map<String, dynamic> device = const {},
  }) : _prefs = prefs,
       _api = api,
       _isOwner =
           isOwner ?? (() => AuthController.instance.user?.isOwner ?? false),
       _signedIn = signedIn ?? (() => AuthController.instance.signedIn),
       _clock = clock ?? DateTime.now,
       crumbs = crumbs ?? Breadcrumbs.instance,
       _native = native ?? _platformDiagnostics,
       _device = Map.of(device) {
    queue = ErrorQueue(
      prefs,
      assist ? ErrorsPrefs.assistErrorQueue : ErrorsPrefs.errorQueue,
      clock: _clock,
    );
    sessions = SessionTracker(
      prefs: prefs,
      build: build,
      enabled: () => enabled,
      clock: _clock,
      onChange: scheduleFlush,
    );
  }

  /// The running reporter, set by [install]. Null until then (and in tests).
  static ErrorReporter? current;

  /// The assistant overlay's engine: its own queue, no sessions.
  final bool assist;
  final int build;
  final Breadcrumbs crumbs;
  late final ErrorQueue queue;
  late final SessionTracker sessions;

  final SharedPreferences _prefs;
  ErrorsApi? _api;
  final bool Function() _isOwner;
  final bool Function() _signedIn;
  final DateTime Function() _clock;
  final NativeDiagnostics _native;
  final Map<String, dynamic> _device;

  ErrorsApi get api => _api ??= ErrorsApi();

  // Rate limits (per process = per session).
  final _lastSeen = <String, DateTime>{};
  Timer? _flushTimer;
  bool _flushing = false;
  bool _foreground = true;
  String? _net;
  String? _mem;
  RawReceivePort? _isolatePort;

  /// What is sent and queued right now.
  bool get enabled => ErrorSettings.effective(_prefs, isOwner: _isOwner());

  // ---- capture -------------------------------------------------------------

  /// Framework errors (`FlutterError.onError`).
  void recordFlutterError(FlutterErrorDetails details) => unawaited(
    record(
      kind: 'dart',
      type: details.exception.runtimeType.toString(),
      message: details.exceptionAsString(),
      stack: details.stack?.toString() ?? '',
    ),
  );

  /// Async and platform errors (`PlatformDispatcher.onError`). Always true: handled.
  bool recordPlatformError(Object cause, StackTrace stack) {
    unawaited(
      record(
        kind: 'platform',
        type: cause.runtimeType.toString(),
        message: cause.toString(),
        stack: stack.toString(),
      ),
    );
    return true;
  }

  /// Errors from the main isolate or a spawned one: `[error, stack]` as strings.
  void recordIsolateError(Object? pair) {
    if (pair is! List || pair.length < 2) return;
    unawaited(
      record(
        kind: 'isolate',
        type: 'IsolateError',
        message: '${pair[0]}',
        stack: '${pair[1]}',
      ),
    );
  }

  /// A SendPort for `Isolate.spawn(..., onError: port)` or `addErrorListener`.
  SendPort get isolateErrorPort => (_isolatePort ??= RawReceivePort(
    recordIsolateError,
    'sparky-errors',
  )).sendPort;

  /// The dedupe key: the type and the first frames with line numbers and addresses removed.
  static String keyOf(String type, String stack) {
    final frames = stack
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .take(4)
        .map(
          (l) => l.replaceAll(RegExp(r':\d+(:\d+)?|0x[0-9a-fA-F]+|\d{4,}'), ''),
        )
        .join('|');
    return '$type|$frames';
  }

  /// Records one error unless reporting is off or a limit is hit. Returns whether it was queued.
  Future<bool> record({
    required String kind,
    required String type,
    required String message,
    required String stack,
    DateTime? at,
    String? sessionId,
    int? buildOverride,
  }) async {
    if (!enabled) return false;
    final now = _clock();
    final key = keyOf(type, stack);
    final seen = _lastSeen[key];
    if (seen != null) {
      if (now.difference(seen) < ErrorsConfig.sameErrorEvery) return false;
    } else if (_lastSeen.length >= ErrorsConfig.maxDistinctPerSession) {
      return false;
    }
    _lastSeen[key] = now;
    final firstLine = message.split('\n').first;
    final payload = <String, dynamic>{
      'kind': kind,
      'type': _cut(type, ErrorsConfig.maxType),
      'message': _cut(firstLine, ErrorsConfig.maxMessage),
      'stack': _cut(stack, ErrorsConfig.maxStack),
      'build': buildOverride ?? build,
      'at': (at ?? now).millisecondsSinceEpoch,
      'sessionId': ?(sessionId ?? sessions.currentId),
      'breadcrumbs': crumbs.toJson(),
      'device': _deviceInfo(),
    };
    await queue.add(payload);
    scheduleFlush();
    return true;
  }

  static String _cut(String s, int max) =>
      s.length > max ? s.substring(0, max) : s;

  Map<String, dynamic> _deviceInfo() => {
    ..._device,
    'locale': PlatformDispatcher.instance.locale.toLanguageTag(),
    'fg': _foreground,
    'net': ?_net,
    'memBucket': ?_mem,
  };

  // ---- sending -------------------------------------------------------------

  void scheduleFlush() {
    if (_flushTimer?.isActive ?? false) return;
    _flushTimer = Timer(ErrorsConfig.flushDelay, () => unawaited(flush()));
  }

  /// Sends what is queued (errors in batches of 10, then sessions). Never throws.
  /// With reporting off the queue is emptied instead.
  Future<void> flush() async {
    if (_flushing) return;
    _flushing = true;
    try {
      if (!enabled) {
        await clearQueues();
        return;
      }
      if (!_signedIn()) return;
      await queue.reload();
      if (!await _drain(queue, ErrorsConfig.errorBatch, api.sendErrors)) return;
      if (!assist) {
        await _drain(
          sessions.queue,
          ErrorsConfig.sessionBatch,
          api.sendSessions,
        );
      }
    } catch (_) {
      // Reporting must never throw into the app.
    } finally {
      _flushing = false;
    }
  }

  /// True when the queue is empty or fully sent; false when a failure should stop the flush.
  Future<bool> _drain(
    ErrorQueue q,
    int batch,
    Future<void> Function(List<Map<String, dynamic>>) send,
  ) async {
    while (true) {
      final entries = q.read().take(batch).toList();
      if (entries.isEmpty) return true;
      try {
        await send([for (final e in entries) e.payload]);
        await q.remove(entries.map((e) => e.key));
      } on ApiException catch (e) {
        final s = e.status ?? 0;
        // Bad request / not allowed: retrying cannot help, so drop. Sign-in, rate limit, server and network trouble keep the queue.
        if (s >= 400 && s < 500 && s != 401 && s != 408 && s != 429) {
          await q.remove(entries.map((e) => e.key));
          continue;
        }
        return false;
      } catch (_) {
        return false;
      }
    }
  }

  /// Turning the switch off clears everything waiting to be sent.
  Future<void> clearQueues() async {
    await queue.clear();
    await sessions.queue.clear();
  }

  // ---- lifecycle, memory, connectivity, updates -------------------------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    crumbs.lifecycle(state);
    _foreground = state == AppLifecycleState.resumed;
    if (assist) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(sessions.end());
      // The process may be killed soon: try to send now.
      unawaited(flush());
    } else if (state == AppLifecycleState.resumed) {
      unawaited(sessions.resume().then((_) => flush()));
    }
  }

  @override
  void didHaveMemoryPressure() {
    crumbs.memoryPressure();
    _mem = 'low';
  }

  StreamSubscription<List<ConnectivityResult>>? _net$;
  VoidCallback? _updatesListener;
  UpdatePhase? _lastPhase;

  void _listen(UpdateController updates) {
    _lastPhase = updates.phase;
    _updatesListener = () {
      if (updates.phase == _lastPhase) return;
      _lastPhase = updates.phase;
      crumbs.update(updates.phase);
    };
    updates.addListener(_updatesListener!);
  }

  // ---- install -----------------------------------------------------------------

  /// Hooks the global handlers to [record]. Safe to call once per entry point.
  void installHandlers() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      recordFlutterError(details);
      if (previous != null) {
        previous(details);
      } else {
        FlutterError.presentError(details);
      }
    };
    PlatformDispatcher.instance.onError = recordPlatformError;
    if (!kIsWeb) Isolate.current.addErrorListener(isolateErrorPort);
  }

  /// Observers, connectivity and update-phase breadcrumbs, and the previous run's crash.
  Future<void> start({UpdateController? updates}) async {
    WidgetsBinding.instance.addObserver(this);
    try {
      _net$ = Connectivity().onConnectivityChanged.listen((types) {
        crumbs.net(types);
        _net = types.map((t) => t.name).join('+');
        if (types.any((t) => t != ConnectivityResult.none)) scheduleFlush();
      });
    } catch (_) {
      // No connectivity plugin (tests, unsupported platform): breadcrumbs only.
    }
    if (updates != null) _listen(updates);
    if (assist) return;
    final previous = await sessions.begin(native: await _native());
    if (previous != null) await _reportPrevious(previous);
    scheduleFlush();
  }

  /// The last run's Kotlin crash and Android exit reason become error events on the build that crashed.
  Future<void> _reportPrevious(PreviousRun p) async {
    final crash = p.crash;
    final exit = p.exit;
    if (crash != null) {
      await record(
        kind: 'kotlin',
        type: '${crash['type']}',
        message: '${crash['message']}',
        stack: '${crash['stack']}',
        at: _time(crash['at']),
        sessionId: p.sessionId,
        buildOverride: p.build,
      );
      return;
    }
    if (exit == null) return;
    final reason = '${exit['reason']}';
    // Memory kills and signals only matter when the session never ended cleanly.
    if ((reason == 'low_memory' || reason == 'signaled') &&
        p.outcome != 'killed') {
      return;
    }
    await record(
      kind: reason == 'anr' ? 'anr' : 'native_signal',
      type: reason == 'anr' ? 'ANR' : reason,
      message: '${exit['description'] ?? ''}',
      stack: '',
      at: _time(exit['at']),
      sessionId: p.sessionId,
      buildOverride: p.build,
    );
  }

  static DateTime? _time(Object? ms) => ms is num && ms > 0
      ? DateTime.fromMillisecondsSinceEpoch(ms.toInt())
      : null;

  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    _flushTimer?.cancel();
    await _net$?.cancel();
    _isolatePort?.close();
  }

  /// Wires a running reporter for this entry point. Never throws.
  static Future<ErrorReporter?> install({
    bool assist = false,
    UpdateController? updates,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var build = 0;
      try {
        final info = await PackageInfo.fromPlatform();
        build = _buildOf(int.tryParse(info.buildNumber) ?? 0);
      } catch (_) {}
      final r = ErrorReporter(
        prefs: prefs,
        assist: assist,
        build: build,
        device: await _deviceFacts(),
      );
      current = r;
      r.installHandlers();
      await r.start(updates: updates);
      AuthController.instance.addListener(() {
        if (AuthController.instance.signedIn) r.scheduleFlush();
      });
      return r;
    } catch (_) {
      return null;
    }
  }

  static int _buildOf(int code) =>
      code >= ErrorsConfig.abiOffset ? code - ErrorsConfig.abiOffset : code;

  static Future<Map<String, dynamic>> _deviceFacts() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return {};
    try {
      const channel = MethodChannel(ErrorsConfig.diagnosticsChannel);
      return await channel.invokeMapMethod<String, dynamic>('device') ?? {};
    } catch (_) {
      return {};
    }
  }

  /// Runs [body] (the pre-binding setup) so an error there is recorded too instead of vanishing.
  /// Only this synchronous slice is zoned; `runApp` stays in the root zone.
  static void runGuarded(void Function() body) {
    runZonedGuarded(body, (error, stack) {
      final r = current;
      if (r != null) {
        r.recordPlatformError(error, stack);
      } else {
        FlutterError.reportError(
          FlutterErrorDetails(exception: error, stack: stack),
        );
      }
    });
  }
}
