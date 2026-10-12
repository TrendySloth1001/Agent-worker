import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:timezone/timezone.dart' as tz;

import '../../data/memory_api.dart';
import '../constants/notify_copy.dart';
import 'notify_kind.dart';
import 'notify_policy.dart';
import 'notify_prefs.dart';
import 'notify_target.dart';

/// State of the Android notification permission.
enum NotifyPermission { granted, denied, unavailable }

/// The one door for system notifications. Features never touch the plugin:
/// they pick a [NotifyKind] and call [post], [progress] or [keepAlive]. The
/// center applies the user's choices (master switch, per-kind switch, quiet
/// hours), the "app in the background" rule, grouping, ids and channels, and
/// routes taps (cold start or warm) to [target].
///
/// To add a new notification: add a [NotifyKind], call [post] where it
/// happens. Android only; elsewhere every call is a no-op.
class NotificationCenter with WidgetsBindingObserver {
  NotificationCenter._();

  static final instance = NotificationCenter._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool _asked = false;

  /// The user's choices; replaced by the persisted ones at start-up.
  NotifyPrefs prefs = NotifyPrefs(null);

  /// A tapped notification, waiting for the UI to open it. The consumer
  /// sets it back to null.
  final target = ValueNotifier<NotifyTarget?>(null);

  /// True while the app is not visible.
  final background = ValueNotifier<bool>(false);

  /// The chat on screen, for notifications that point "back here".
  String? Function() currentChat = () => null;

  /// Injectable for tests.
  DateTime Function() clock = DateTime.now;

  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  /// Whether the plugin is set up (Android, initialised).
  bool get ready => _ready;

  /// Uses the persisted preferences (call before [init]).
  void attach(NotifyPrefs p) => prefs = p;

  Future<void> init() async {
    WidgetsBinding.instance.addObserver(this);
    if (!_supported) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings(NotifyConfig.icon),
        ),
        onDidReceiveNotificationResponse: _onResponse,
      );
      _ready = true;
      await _createChannels();
      await _clearStale();
      // Cold start: the tap that launched the app.
      final launch = await _plugin.getNotificationAppLaunchDetails();
      final r = launch?.notificationResponse;
      if ((launch?.didNotificationLaunchApp ?? false) && r != null) {
        _onResponse(r);
      }
    } catch (_) {
      // Notifications are a convenience; the app works without them.
    }
  }

  /// Every channel exists from the start, so each shows in the system
  /// settings with its description before the first notification.
  Future<void> _createChannels() async {
    final android = _android;
    if (android == null) return;
    for (final kind in NotifyKind.values) {
      for (final c in kind.channels) {
        await android.createNotificationChannel(
          AndroidNotificationChannel(
            c.id,
            c.name,
            description: c.description,
            importance: c.importance,
            playSound: c.sound,
            enableVibration: c.vibrate,
          ),
        );
      }
    }
  }

  /// A progress notification left behind by a process that died (crash,
  /// swipe from recents) has nothing running behind it any more.
  Future<void> _clearStale() async {
    try {
      await _android?.stopForegroundService();
    } catch (_) {}
    for (final kind in NotifyKind.values) {
      if (kind.progress == null) continue;
      try {
        await _plugin.cancel(id: kind.progressId);
      } catch (_) {}
    }
  }

  // ---- taps --------------------------------------------------------------

  /// Hands a target to the UI (also used by in-app links).
  void open(NotifyTarget t) => target.value = t;

  void _onResponse(NotificationResponse r) {
    final t = NotifyTarget.parse(r.payload);
    if (NotifyAction.byId(r.actionId) == NotifyAction.undo) {
      _undo(t);
      return;
    }
    if (t != null) open(t);
  }

  /// "Undo" on a memory note: forget what was just remembered.
  void _undo(NotifyTarget? t) {
    if (t is! MemoryTarget || t.id == null) return;
    unawaited(MemoryApi.instance.delete(t.id!).catchError((Object _) {}));
  }

  // ---- lifecycle ---------------------------------------------------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // `inactive` also fires for the notification shade; only real leaves count.
    if (state == AppLifecycleState.resumed) {
      background.value = false;
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      background.value = true;
    }
  }

  // ---- permission --------------------------------------------------------

  Future<bool> _enabled() async {
    if (!_ready) return false;
    try {
      return await _android?.areNotificationsEnabled() ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<NotifyPermission> permission() async {
    if (!_ready) return NotifyPermission.unavailable;
    return await _enabled()
        ? NotifyPermission.granted
        : NotifyPermission.denied;
  }

  /// Whether notifications may be shown, asking once per run (Android 13+).
  /// False too when the user switched them all off in the app.
  Future<bool> ensurePermission() async {
    if (!_ready || !prefs.master) return false;
    final android = _android;
    if (android == null) return false;
    try {
      if (await android.areNotificationsEnabled() ?? false) return true;
      if (_asked) return false;
      _asked = true;
      return await android.requestNotificationsPermission() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// The settings "Allow" button: the system dialog the first time, the
  /// app's system settings when the dialog can no longer appear.
  Future<NotifyPermission> allow() async {
    if (!_ready) return NotifyPermission.unavailable;
    if (await _enabled()) return NotifyPermission.granted;
    final android = _android;
    final before = prefs.asked;
    final clock = Stopwatch()..start();
    try {
      await android?.requestNotificationsPermission();
    } catch (_) {}
    prefs.markAsked();
    if (await _enabled()) return NotifyPermission.granted;
    // Asked before, or the answer came back without a dialog: Android will
    // not show it again, only the settings page can change it.
    if (before || clock.elapsed < NotifyConfig.dialogMin) {
      try {
        await ph.openAppSettings();
      } catch (_) {}
    }
    return await permission();
  }

  // ---- decisions ---------------------------------------------------------

  /// Whether [kind] may be posted now. [lookingAt]: the user is on the
  /// screen this is about. [force]: the user asked for this one.
  NotifyDecision decide(
    NotifyKind kind, {
    bool lookingAt = false,
    bool force = false,
  }) {
    final now = clock();
    final d = NotifyPolicy.decide(
      masterOn: prefs.master,
      kindOn: prefs.isOn(kind),
      backgroundOnly: kind.backgroundOnly,
      appInBackground: background.value,
      quiet: prefs.quiet.contains(now),
      lookingAt: lookingAt,
      force: force,
    );
    if (d == NotifyDecision.skip) return d;
    if (!force &&
        NotifyPolicy.tooSoon(prefs.lastSeen(kind), now, kind.minGap)) {
      return NotifyDecision.skip;
    }
    return d;
  }

  // ---- posting -----------------------------------------------------------

  /// Posts a finished / failed / informational notification and ends the
  /// kind's progress one. [key] names the thing it is about (chat, doc or
  /// file id): the same key replaces its earlier notification. Returns
  /// whether it was shown.
  Future<bool> post(
    NotifyKind kind, {
    required String key,
    required String title,
    required String body,
    NotifyTarget? target,
    bool lookingAt = false,
    bool force = false,
  }) async {
    if (!_ready) return false;
    if (kind.progress != null) await finishProgress(kind);
    final d = decide(kind, lookingAt: lookingAt, force: force);
    if (d == NotifyDecision.skip) return false;
    final text = _clip(body);
    final id = kind.idFor(key);
    final shown = await _show(
      id: id,
      title: title,
      body: text,
      payload: target?.payload,
      details: _doneDetails(kind, text, quiet: d == NotifyDecision.postQuiet),
    );
    if (!shown) return false;
    if (kind.minGap > Duration.zero) prefs.markPosted(kind, clock());
    unawaited(_syncGroup(kind, id, title));
    return true;
  }

  /// Ongoing, silent progress. Shown when the user wants this kind; an
  /// already running foreground service keeps its own notification either
  /// way (see [keepAlive]).
  Future<void> progress(
    NotifyKind kind, {
    required String title,
    required String body,
    NotifyTarget? target,
    int done = 0,
    int total = 0,
    bool force = false,
  }) async {
    if (!_ready || !prefs.master || !(force || prefs.isOn(kind))) return;
    final details = _progressDetails(kind, body, done: done, total: total);
    _owners[kind.progressId]?.update(title, body, target?.payload, details);
    await _show(
      id: kind.progressId,
      title: title,
      body: body,
      payload: target?.payload,
      details: details,
    );
  }

  /// Removes the kind's progress notification and releases its service.
  Future<void> finishProgress(NotifyKind kind) async {
    if (!_ready) return;
    await _release(kind.progressId);
    try {
      await _plugin.cancel(id: kind.progressId);
    } catch (_) {}
  }

  /// Removes one finished notification (its subject was opened elsewhere).
  Future<void> cancel(NotifyKind kind, String key) async {
    if (!_ready) return;
    try {
      await _plugin.cancel(id: kind.idFor(key));
    } catch (_) {}
  }

  // ---- foreground service ------------------------------------------------

  final _owners = <int, _Owner>{};
  int? _serviceId;

  /// Android freezes background apps within seconds, which drops a running
  /// stream. A foreground service started while the app is still visible
  /// keeps the process alive; its notification is the kind's progress one,
  /// and [progress] updates it. Several kinds can share the service: it
  /// stops when the last one finishes. The service starts even when the
  /// user switched this kind off, since it protects the work itself.
  Future<void> keepAlive(
    NotifyKind kind, {
    required String title,
    required String body,
    NotifyTarget? target,
  }) async {
    if (!_ready) return;
    final id = kind.progressId;
    final owner = _owners[id] = _Owner(
      id,
      title,
      body,
      target?.payload,
      _progressDetails(kind, body),
    );
    if (_serviceId != null) return;
    await _startService(owner);
  }

  /// Whether [kind] currently owns (or shares) the foreground service.
  bool isAlive(NotifyKind kind) => _owners.containsKey(kind.progressId);

  Future<void> _startService(_Owner o) async {
    try {
      await _android?.startForegroundService(
        id: o.id,
        title: o.title,
        body: o.body,
        notificationDetails: o.details,
        payload: o.payload,
        startType: AndroidServiceStartType.startNotSticky,
        foregroundServiceTypes: {
          AndroidServiceForegroundType.foregroundServiceTypeDataSync,
        },
      );
      _serviceId = o.id;
    } catch (_) {
      // Without it the work still runs while the app stays open.
      _owners.remove(o.id);
    }
  }

  Future<void> _release(int id) async {
    if (_owners.remove(id) == null) return;
    if (_serviceId != id) return;
    _serviceId = null;
    if (_owners.isEmpty) {
      try {
        await _android?.stopForegroundService();
      } catch (_) {}
    } else {
      // Another kind still needs the process: move the service to it.
      await _startService(_owners.values.first);
    }
  }

  // ---- reminders ---------------------------------------------------------

  /// A local reminder for [key] after [delay] (no server, no push).
  Future<void> schedule(
    NotifyKind kind, {
    required String key,
    required String title,
    required String body,
    required Duration delay,
    NotifyTarget? target,
  }) async {
    if (!_ready || !prefs.allows(kind)) return;
    try {
      await _plugin.zonedSchedule(
        id: kind.idFor(key),
        title: title,
        body: _clip(body),
        scheduledDate: tz.TZDateTime.now(tz.UTC).add(delay),
        notificationDetails: NotificationDetails(
          android: _doneDetails(kind, body, quiet: true),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: target?.payload,
      );
    } catch (_) {}
  }

  // ---- test --------------------------------------------------------------

  /// A sample notification, regardless of the per-kind switches. False when
  /// the system blocks notifications.
  Future<bool> sendTest() async {
    if (!_ready || !await _enabled()) return false;
    return _show(
      id: NotifyConfig.testId,
      title: NotifyCopy.testTitle,
      body: NotifyCopy.testBody,
      payload: const SettingsTarget('notifications').payload,
      details: _doneDetails(
        NotifyKind.reply,
        NotifyCopy.testBody,
        quiet: prefs.quiet.contains(clock()),
        grouped: false,
      ),
    );
  }

  // ---- details -----------------------------------------------------------

  AndroidNotificationDetails _progressDetails(
    NotifyKind kind,
    String body, {
    int done = 0,
    int total = 0,
  }) {
    final c = kind.progress ?? kind.channel;
    return AndroidNotificationDetails(
      c.id,
      c.name,
      channelDescription: c.description,
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      silent: true,
      onlyAlertOnce: true,
      showProgress: true,
      indeterminate: total <= 0,
      maxProgress: total > 0 ? total : 0,
      progress: total > 0 ? done : 0,
      playSound: false,
      enableVibration: false,
      styleInformation: BigTextStyleInformation(body),
      category: AndroidNotificationCategory.progress,
    );
  }

  AndroidNotificationDetails _doneDetails(
    NotifyKind kind,
    String body, {
    required bool quiet,
    bool grouped = true,
  }) {
    final c = kind.channel;
    return AndroidNotificationDetails(
      c.id,
      c.name,
      channelDescription: c.description,
      importance: c.importance,
      priority: _priority(c.importance),
      groupKey: grouped ? kind.group.key : null,
      styleInformation: BigTextStyleInformation(body),
      category: AndroidNotificationCategory.message,
      // Quiet hours and quiet channels: no sound, no buzz.
      silent: quiet || !c.sound,
      playSound: !quiet && c.sound,
      enableVibration: !quiet && c.vibrate,
      actions: [
        for (final a in kind.actions)
          AndroidNotificationAction(
            a.id,
            a.label,
            showsUserInterface: true,
            cancelNotification: true,
          ),
      ],
    );
  }

  static Priority _priority(Importance i) => switch (i) {
    Importance.max || Importance.high => Priority.high,
    Importance.low || Importance.min || Importance.none => Priority.low,
    _ => Priority.defaultPriority,
  };

  static String _clip(String s) => s.length <= NotifyConfig.bodyMax
      ? s
      : '${s.substring(0, NotifyConfig.bodyMax - 1).trimRight()}…';

  Future<bool> _show({
    required int id,
    required String title,
    required String body,
    required AndroidNotificationDetails details,
    String? payload,
  }) async {
    if (!_ready) return false;
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(android: details),
        payload: payload,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---- grouping ----------------------------------------------------------

  final _live = <NotifyGroup, Map<int, String>>{};

  /// Keeps a summary notification for a group with more than two live
  /// notifications, and drops it when fewer remain.
  Future<void> _syncGroup(NotifyKind kind, int id, String title) async {
    final g = kind.group;
    final live = _live.putIfAbsent(g, () => {});
    live[id] = title;
    try {
      final active = {
        for (final n in await _plugin.getActiveNotifications()) ?n.id,
      };
      live.removeWhere((k, _) => !active.contains(k));
      if (live.length <= NotifyConfig.summaryAfter) {
        await _plugin.cancel(id: g.summaryId);
        return;
      }
      final c = kind.channel;
      await _plugin.show(
        id: g.summaryId,
        title: NotifyCopy.groupTitle,
        body: NotifyCopy.groupSummary(live.length),
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            c.id,
            c.name,
            channelDescription: c.description,
            importance: Importance.low,
            priority: Priority.low,
            groupKey: g.key,
            setAsGroupSummary: true,
            silent: true,
            onlyAlertOnce: true,
            styleInformation: InboxStyleInformation(
              live.values.toList(),
              contentTitle: NotifyCopy.groupTitle,
              summaryText: NotifyCopy.groupSummary(live.length),
            ),
          ),
        ),
      );
    } catch (_) {}
  }
}

class _Owner {
  _Owner(this.id, this.title, this.body, this.payload, this.details);

  final int id;
  String title, body;
  String? payload;
  AndroidNotificationDetails details;

  void update(
    String title,
    String body,
    String? payload,
    AndroidNotificationDetails details,
  ) {
    this.title = title;
    this.body = body;
    this.payload = payload;
    this.details = details;
  }
}
