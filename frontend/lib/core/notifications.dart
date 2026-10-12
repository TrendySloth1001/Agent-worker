import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'constants/app_notifications.dart';
import 'constants/docs.dart';
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

  /// Document id from a tapped document notification (payload `doc:<id>`).
  /// The chat screen opens the reader and sets this back to null.
  final openedDoc = ValueNotifier<String?>(null);

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
    if (id == null || id.isEmpty) return;
    if (id.startsWith(NotifyConfig.docPayload)) {
      openedDoc.value = id.substring(NotifyConfig.docPayload.length);
    } else {
      opened.value = id;
    }
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

  /// Notification id that owns the foreground service, if any.
  int? _aliveId;

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
  Future<void> keepAlive(String body, {String? payload}) => _keepAlive(
    id: NotifyConfig.tableId,
    title: TableWaitStrings.progressTitle,
    body: body,
    payload: payload,
    details: _progressDetails,
  );

  Future<void> _keepAlive({
    required int id,
    required String title,
    required String body,
    required AndroidNotificationDetails details,
    String? payload,
  }) async {
    // One foreground service at a time; its owner keeps the process alive
    // for any other background work too.
    if (!_ready || _aliveId != null) return;
    try {
      await _android?.startForegroundService(
        id: id,
        title: title,
        body: body,
        notificationDetails: details,
        payload: payload,
        startType: AndroidServiceStartType.startNotSticky,
        foregroundServiceTypes: {
          AndroidServiceForegroundType.foregroundServiceTypeDataSync,
        },
      );
      _aliveId = id;
    } catch (_) {
      // Without it the answer still works while the app stays open.
    }
  }

  Future<void> _release(int id) async {
    if (_aliveId != id) return;
    _aliveId = null;
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
    await _release(NotifyConfig.tableId);
    try {
      await _plugin.cancel(id: NotifyConfig.tableId);
    } catch (_) {}
  }

  // ---- documents ---------------------------------------------------------------

  static const _docProgressDetails = AndroidNotificationDetails(
    NotifyConfig.docProgressChannel,
    DocStrings.notifyProgressChannel,
    channelDescription: DocStrings.notifyProgressChannelInfo,
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

  /// Silent, ongoing "section x/y" progress for a document being written.
  /// [maxProgress] and [progress] draw a determinate bar when known.
  Future<void> showDocProgress(
    String docId,
    String body, {
    int progress = 0,
    int maxProgress = 0,
  }) => _show(
    id: NotifyConfig.docProgressId,
    title: DocStrings.notifyProgressTitle,
    body: body,
    payload: NotifyConfig.docPayload + docId,
    details: maxProgress > 0
        ? AndroidNotificationDetails(
            NotifyConfig.docProgressChannel,
            DocStrings.notifyProgressChannel,
            channelDescription: DocStrings.notifyProgressChannelInfo,
            importance: Importance.low,
            priority: Priority.low,
            ongoing: true,
            autoCancel: false,
            silent: true,
            onlyAlertOnce: true,
            showProgress: true,
            maxProgress: maxProgress,
            progress: progress,
            playSound: false,
            enableVibration: false,
            styleInformation: BigTextStyleInformation(body),
            category: AndroidNotificationCategory.progress,
          )
        : _docProgressDetails,
  );

  /// Foreground service for a document being written (start it while the
  /// app is visible; Android refuses it from the background).
  Future<void> keepDocAlive(String docId, String body) => _keepAlive(
    id: NotifyConfig.docProgressId,
    title: DocStrings.notifyProgressTitle,
    body: body,
    payload: NotifyConfig.docPayload + docId,
    details: _docProgressDetails,
  );

  Future<void> cancelDocProgress() async {
    if (!_ready) return;
    await _release(NotifyConfig.docProgressId);
    try {
      await _plugin.cancel(id: NotifyConfig.docProgressId);
    } catch (_) {}
  }

  /// "Document ready" (or stopped / failed): replaces the progress one.
  /// Tapping opens the document.
  Future<void> showDocFinished(
    String docId, {
    required String title,
    required String body,
  }) async {
    await cancelDocProgress();
    await _show(
      id:
          NotifyConfig.docDoneBase +
          (docId.hashCode & NotifyConfig.docDoneMask),
      title: title,
      body: body,
      payload: NotifyConfig.docPayload + docId,
      details: AndroidNotificationDetails(
        NotifyConfig.docDoneChannel,
        DocStrings.notifyDoneChannel,
        channelDescription: DocStrings.notifyDoneChannelInfo,
        importance: Importance.high,
        priority: Priority.high,
        styleInformation: BigTextStyleInformation(body),
        category: AndroidNotificationCategory.message,
      ),
    );
  }

  Future<void> _show({
    required String title,
    required String body,
    required AndroidNotificationDetails details,
    String? payload,
    int id = NotifyConfig.tableId,
  }) async {
    if (!_ready) return;
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(android: details),
        payload: payload,
      );
    } catch (_) {}
  }
}
