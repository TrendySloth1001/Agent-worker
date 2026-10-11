import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'constants/app_notifications.dart';
import 'constants/app_strings.dart';

/// System notifications for Round Table answers, and whether the app is in
/// the background. Android only; elsewhere every call is a no-op.
class AppNotifications with WidgetsBindingObserver {
  AppNotifications._();

  static final instance = AppNotifications._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool _asked = false;

  /// Conversation id from a tapped notification. The chat screen opens it
  /// and sets this back to null.
  final opened = ValueNotifier<String?>(null);

  /// True while the app is not visible.
  final background = ValueNotifier<bool>(false);

  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  Future<void> init() async {
    WidgetsBinding.instance.addObserver(this);
    if (!_supported) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings(NotifyConfig.icon),
        ),
        onDidReceiveNotificationResponse: (r) => _open(r.payload),
      );
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        _open(launch!.notificationResponse?.payload);
      }
      _ready = true;
    } catch (_) {
      // Notifications are a convenience; the app works without them.
    }
  }

  void _open(String? id) {
    if (id != null && id.isNotEmpty) opened.value = id;
  }

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

  /// Whether notifications may be shown, asking once (Android 13+).
  Future<bool> ensurePermission() async {
    if (!_ready) return false;
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

  static const _progressDetails = AndroidNotificationDetails(
    NotifyConfig.progressChannel,
    TableWaitStrings.progressChannel,
    channelDescription: TableWaitStrings.progressChannelInfo,
    importance: Importance.low,
    priority: Priority.low,
    ongoing: true,
    autoCancel: false,
    silent: true,
    onlyAlertOnce: true,
    showProgress: true,
    indeterminate: true,
    playSound: false,
    enableVibration: false,
    category: AndroidNotificationCategory.progress,
  );

  bool _alive = false;

  /// Silent, ongoing progress while a table works in the background.
  Future<void> showProgress(String body, {String? payload}) => _show(
    title: TableWaitStrings.progressTitle,
    body: body,
    payload: payload,
    details: _progressDetails,
  );

  /// Android freezes background apps within seconds, which drops the
  /// answer's stream. A foreground service (started while the app is still
  /// visible) keeps it alive; its notification is the progress one, and
  /// [showProgress] updates it.
  Future<void> keepAlive(String body, {String? payload}) async {
    if (!_ready || _alive) return;
    try {
      await _android?.startForegroundService(
        id: NotifyConfig.tableId,
        title: TableWaitStrings.progressTitle,
        body: body,
        notificationDetails: _progressDetails,
        payload: payload,
        startType: AndroidServiceStartType.startNotSticky,
        foregroundServiceTypes: {
          AndroidServiceForegroundType.foregroundServiceTypeDataSync,
        },
      );
      _alive = true;
    } catch (_) {
      // Without it the answer still works while the app stays open.
    }
  }

  Future<void> _release() async {
    if (!_alive) return;
    _alive = false;
    try {
      await _android?.stopForegroundService();
    } catch (_) {}
  }

  /// Replaces the progress notification with an alerting one.
  Future<void> showFinished({
    required String title,
    required String body,
    String? payload,
  }) async {
    await cancelProgress();
    await _show(
      title: title,
      body: body,
      payload: payload,
      details: AndroidNotificationDetails(
        NotifyConfig.doneChannel,
        TableWaitStrings.doneChannel,
        channelDescription: TableWaitStrings.doneChannelInfo,
        importance: Importance.high,
        priority: Priority.high,
        styleInformation: BigTextStyleInformation(body),
        category: AndroidNotificationCategory.message,
      ),
    );
  }

  Future<void> cancelProgress() async {
    if (!_ready) return;
    await _release();
    try {
      await _plugin.cancel(id: NotifyConfig.tableId);
    } catch (_) {}
  }

  Future<void> _show({
    required String title,
    required String body,
    required AndroidNotificationDetails details,
    String? payload,
  }) async {
    if (!_ready) return;
    try {
      await _plugin.show(
        id: NotifyConfig.tableId,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(android: details),
        payload: payload,
      );
    } catch (_) {}
  }
}
