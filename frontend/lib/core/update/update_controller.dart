import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../constants/update.dart';
import '../notify/notification_center.dart';
import '../notify/notify_kind.dart';
import '../notify/notify_target.dart';
import 'app_build.dart';
import 'update_api.dart';
import 'update_downloader.dart';
import 'update_events.dart';
import 'update_installer.dart';
import 'update_models.dart';
import 'update_policy.dart';
import 'update_store.dart';

/// Where the download / install of the available update stands.
enum UpdatePhase {
  idle,
  downloading,

  /// Downloaded and verified, waiting for the user to install.
  ready,

  /// The "install unknown apps" permission is missing.
  needsPermission,
  installing,
  failed,
}

enum UpdateFailure { network, verify, signature, install }

/// Result of a manual "Check for updates".
enum UpdateCheck { upToDate, available, failed }

/// Everything about app updates: when to check, what to show, the download
/// and the hand-over to the installer. One instance per app; the UI listens.
///
/// The pure rules live in [UpdatePolicy]; this class is the plumbing (network,
/// storage, platform) around them. Every dependency is injectable for tests.
class UpdateController extends ChangeNotifier with WidgetsBindingObserver {
  UpdateController({
    UpdateApi? api,
    UpdateInstaller? installer,
    UpdateDownloader? downloader,
    Future<UpdateStore> Function()? store,
    Future<int> Function()? currentBuild,
    Future<bool> Function()? onWifi,
    DateTime Function()? clock,
    Future<void> Function(UpdateRelease release)? notify,
    Duration? startDelay,
    UpdateEventReporter? events,
  }) : _apiOverride = api,
       _eventsOverride = events,
       _installerOverride = installer,
       _downloaderOverride = downloader,
       _openStore = store ?? UpdateStore.open,
       _currentBuild = currentBuild ?? _installedBuild,
       _onWifi = onWifi ?? _wifiNow,
       _clock = clock ?? DateTime.now,
       _notify = notify ?? _notifyNow,
       _startDelay = startDelay ?? UpdateConfig.startDelay;

  /// The app's controller.
  static final instance = UpdateController();

  final UpdateApi? _apiOverride;
  final UpdateEventReporter? _eventsOverride;
  final UpdateInstaller? _installerOverride;
  final UpdateDownloader? _downloaderOverride;
  final Future<UpdateStore> Function() _openStore;
  final Future<int> Function() _currentBuild;
  final Future<bool> Function() _onWifi;
  final DateTime Function() _clock;
  final Future<void> Function(UpdateRelease) _notify;
  final Duration _startDelay;

  // Real services are made on first use, so building the controller (and
  // widget tests that only look at it) never touches plugins.
  late final UpdateApi _api = _apiOverride ?? UpdateApi();
  late final UpdateInstaller _installer =
      _installerOverride ?? PlatformUpdateInstaller();
  late final UpdateDownloader _downloader =
      _downloaderOverride ?? UpdateDownloader();
  late final UpdateEventReporter _events =
      _eventsOverride ?? UpdateEventReporter(send: _api.sendEvents);

  UpdateStore? _store;
  Timer? _startTimer;
  bool _started = false;
  bool _checking = false;
  DateTime? _sessionStart;
  bool _sheetDone = false;

  UpdateInfo? _info;
  UpdatePrompt _prompt = UpdatePrompt.none;
  UpdatePhase _phase = UpdatePhase.idle;
  double _progress = 0;
  UpdateFailure? _failure;
  String? _apkPath;
  bool _wifiOnly = true;
  bool _everChecked = false;

  // ---- state for the UI ----------------------------------------------------

  UpdateInfo? get info => _info;
  UpdateRelease? get latest => _info?.latest;
  UpdatePrompt get prompt => _prompt;
  UpdatePhase get phase => _phase;

  /// 0..1 while [phase] is downloading.
  double get progress => _progress;
  UpdateFailure? get failure => _failure;
  bool get checking => _checking;
  bool get wifiOnly => _wifiOnly;

  /// False until the first check ended (any outcome).
  bool get everChecked => _everChecked;

  /// A newer build exists (the dot).
  bool get hasUpdate => latest != null;

  /// The full-screen "update to continue" must cover the app.
  bool get blocking => _prompt == UpdatePrompt.blocking && hasUpdate;

  // ---- lifecycle -----------------------------------------------------------

  /// Schedules the first check, and checks again when the app comes back after
  /// a long time away. Safe to call more than once.
  void start() {
    if (_started) return;
    _started = true;
    _sessionStart = _clock();
    WidgetsBinding.instance.addObserver(this);
    _startTimer = Timer(_startDelay, () => unawaited(check()));
    unawaited(_loadSettings());
    unawaited(_onLaunch());
  }

  /// Called when someone signs in: the check needs a session.
  void onSignedIn() {
    if (_info == null && _started) unawaited(check());
  }

  @override
  void dispose() {
    _startTimer?.cancel();
    if (_started) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(_events.flush());
    if (_phase == UpdatePhase.needsPermission) {
      unawaited(_resumeInstall());
      return;
    }
    unawaited(_checkIfDue());
  }

  Future<UpdateStore> _s() async => _store ??= await _openStore();

  // ---- install health events ---------------------------------------------------

  /// First start of a build: when it is newer than the last one that ran, an
  /// update just landed. Reports it (and the install itself when the system
  /// never told us), then sends whatever is queued.
  Future<void> _onLaunch() async {
    try {
      final build = await _currentBuild();
      AppBuild.current = build;
      final s = await _s();
      final prev = s.lastBuild;
      final pending = s.pending;
      if (FirstLaunch.afterUpdate(prev, build)) {
        if (pending != null && pending.to == build) {
          // The old process died in the install, so no result reached it.
          await _events.record(
            build: pending.from,
            toBuild: build,
            stage: InstallStage.installOk,
            code: 'relaunch',
          );
        }
        await _events.record(
          build: build,
          toBuild: build,
          stage: InstallStage.firstLaunchOk,
        );
      }
      if (pending != null && pending.to <= build) await s.setPending(null);
      if (prev != build) await s.setLastBuild(build);
      unawaited(_events.flush());
    } catch (_) {}
  }

  Future<void> _emit(
    InstallStage stage,
    UpdateRelease r, {
    String? code,
    int? bytes,
    InstallVia via = InstallVia.full,
  }) async {
    try {
      await _events.record(
        build: await _currentBuild(),
        toBuild: r.build,
        stage: stage,
        code: code,
        bytes: bytes,
        via: via,
      );
    } catch (_) {}
  }

  Future<void> _loadSettings() async {
    final s = await _s();
    _wifiOnly = s.wifiOnly;
    notifyListeners();
  }

  Future<void> _checkIfDue() async {
    final s = await _s();
    if (UpdatePolicy.checkDue(s.lastCheckAt, _clock())) await check();
  }

  /// Checks again when the last check is older than [UpdateConfig.freshFor]:
  /// screens that show the status (About) call this so it is never stale.
  Future<void> refreshIfStale() async {
    final s = await _s();
    final last = s.lastCheckAt;
    if (last == null || _clock().difference(last) > UpdateConfig.freshFor) {
      await check();
    }
  }

  // ---- checking ------------------------------------------------------------

  /// Asks the server for a newer build. Never throws; failures are silent
  /// unless the caller reads the returned [UpdateCheck].
  Future<UpdateCheck> check() async {
    if (_checking) return hasUpdate ? UpdateCheck.available : UpdateCheck.failed;
    _checking = true;
    notifyListeners();
    try {
      final s = await _s();
      _wifiOnly = s.wifiOnly;
      final build = await _currentBuild();
      final info = await _api.check(build, deviceId: await _events.deviceId());
      unawaited(_events.flush());
      await s.setLastCheckAt(_clock());
      _info = info;
      _everChecked = true;
      _recompute(s);
      await _afterCheck(s, info);
      return info.hasUpdate ? UpdateCheck.available : UpdateCheck.upToDate;
    } catch (_) {
      return UpdateCheck.failed;
    } finally {
      _checking = false;
      notifyListeners();
    }
  }

  void _recompute(UpdateStore s) {
    final info = _info;
    _prompt = info == null
        ? UpdatePrompt.none
        : UpdatePolicy.decide(info, s.prompt, _clock());
  }

  Future<void> _afterCheck(UpdateStore s, UpdateInfo info) async {
    final latest = info.latest;
    if (latest == null) {
      // Up to date: the old download is no longer needed.
      if (_phase == UpdatePhase.ready) _phase = UpdatePhase.idle;
      await _forgetDownload(s);
      return;
    }
    // A download from an earlier session that is still good.
    if (_phase == UpdatePhase.idle || _phase == UpdatePhase.failed) {
      final rec = s.downloaded;
      if (rec != null &&
          rec.build == latest.build &&
          rec.sha256 == latest.sha256 &&
          await _downloader.isComplete(latest, rec.path)) {
        _apkPath = rec.path;
        _phase = UpdatePhase.ready;
        _failure = null;
      } else if (rec != null) {
        await _forgetDownload(s);
      }
    }
    if (UpdatePolicy.shouldNotify(info, s.notifiedBuild)) {
      await s.setNotifiedBuild(latest.build);
      try {
        await _notify(latest);
      } catch (_) {}
    }
    final have = _phase == UpdatePhase.ready;
    if (_phase == UpdatePhase.idle &&
        UpdatePolicy.shouldAutoDownload(
          info,
          onWifi: await _onWifi(),
          wifiOnly: _wifiOnly,
          haveIt: have,
        )) {
      unawaited(_download(auto: true));
    }
  }

  Future<void> _forgetDownload(UpdateStore s) async {
    if (s.downloaded == null) return;
    await s.setDownloaded(null);
    try {
      await _downloader.clear();
    } catch (_) {}
    _apkPath = null;
  }

  // ---- the sheet -----------------------------------------------------------

  /// The sheet should show now (a calm moment is the caller's call).
  bool get sheetDue =>
      !_sheetDone &&
      _prompt == UpdatePrompt.sheet &&
      _phase != UpdatePhase.installing;

  /// The app has been open long enough for a non-urgent prompt.
  bool get openLongEnough =>
      _sessionStart != null &&
      _clock().difference(_sessionStart!) >= UpdateConfig.calmAfter;

  /// At most one sheet per session; also used when "What's new" showed.
  void suppressSheetThisSession() => _sheetDone = true;

  /// The sheet is on screen: remember it for the 3-day / 7-day cadence.
  Future<void> markSheetShown() async {
    _sheetDone = true;
    final latest = this.latest;
    if (latest == null) return;
    final s = await _s();
    await s.setPrompt(
      UpdatePolicy.afterShown(s.prompt, latest.build, _clock()),
    );
    _recompute(s);
    notifyListeners();
  }

  // ---- settings ------------------------------------------------------------

  Future<void> setWifiOnly(bool v) async {
    _wifiOnly = v;
    notifyListeners();
    await (await _s()).setWifiOnly(v);
  }

  // ---- download + install ----------------------------------------------------

  /// The user tapped Update: download if needed, then install.
  Future<void> begin() async {
    final latest = this.latest;
    if (latest == null) return;
    switch (_phase) {
      case UpdatePhase.downloading || UpdatePhase.installing:
        return;
      case UpdatePhase.ready || UpdatePhase.needsPermission:
        await install();
      case UpdatePhase.idle || UpdatePhase.failed:
        await _download(auto: false);
        if (_phase == UpdatePhase.ready) await install();
    }
  }

  Future<void> _download({required bool auto}) async {
    final latest = this.latest;
    if (latest == null) return;
    _phase = UpdatePhase.downloading;
    _progress = 0;
    _failure = null;
    notifyListeners();
    final s = await _s();
    var via = InstallVia.full;
    await _emit(InstallStage.downloadStart, latest);
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final path = await _downloader.download(
          latest,
          onProgress: (p) {
            _progress = p;
            notifyListeners();
          },
          refreshUrl: () => _freshUrl(latest),
          onResume: (_) => via = InstallVia.resume,
        );
        await _emit(
          InstallStage.downloadOk,
          latest,
          bytes: latest.size > 0 ? latest.size : null,
          via: via,
        );
        unawaited(_events.flush());
        _apkPath = path;
        await s.setDownloaded(
          DownloadRecord(latest.build, path, latest.sha256),
        );
        _phase = UpdatePhase.ready;
        notifyListeners();
        return;
      } on UpdateVerifyException {
        await _emit(InstallStage.verifyFail, latest, code: 'sha_mismatch');
        // One more go; a second mismatch is a real problem.
        if (attempt == 0) {
          _progress = 0;
          notifyListeners();
          continue;
        }
        unawaited(_events.flush());
        _fail(UpdateFailure.verify, quiet: auto);
        return;
      } catch (_) {
        await _emit(InstallStage.downloadFail, latest, code: 'network');
        unawaited(_events.flush());
        _fail(UpdateFailure.network, quiet: auto);
        return;
      }
    }
  }

  /// A new link for the build being downloaded (the old one expired), or null.
  Future<String?> _freshUrl(UpdateRelease r) async {
    final info = await _api.check(await _currentBuild());
    final l = info.latest;
    return l != null && l.build == r.build && l.sha256 == r.sha256
        ? l.url
        : null;
  }

  void _fail(UpdateFailure f, {bool quiet = false}) {
    // A background download that fails just tries again next time.
    _phase = quiet ? UpdatePhase.idle : UpdatePhase.failed;
    _failure = quiet ? null : f;
    notifyListeners();
  }

  /// Hands the downloaded APK to the system installer, asking for the
  /// "unknown apps" permission first when needed.
  Future<void> install() async {
    final path = _apkPath;
    final latest = this.latest;
    if (path == null || latest == null) return;
    if (!await _downloader.isComplete(latest, path)) {
      _phase = UpdatePhase.idle;
      notifyListeners();
      return begin();
    }
    if (!await _installer.canInstall()) {
      _phase = UpdatePhase.needsPermission;
      notifyListeners();
      return;
    }
    _phase = UpdatePhase.installing;
    _failure = null;
    notifyListeners();
    final store = await _s();
    // Remembered so the next launch can tell the install worked even when
    // the system replaced this process before reporting back.
    await store.setPending(PendingInstall(await _currentBuild(), latest.build));
    await _emit(InstallStage.installStart, latest);
    final status = await _installer.install(path);
    if (status != InstallStatus.success) await store.setPending(null);
    switch (status) {
      case InstallStatus.success:
        // The new app normally replaces this process; if not, we are done.
        await _emit(InstallStage.installOk, latest);
        await store.setPending(null);
        _phase = UpdatePhase.idle;
        await _forgetDownload(store);
      case InstallStatus.cancelled:
        await _emit(InstallStage.cancelled, latest);
        _phase = UpdatePhase.ready;
      case InstallStatus.signatureMismatch:
        await _emit(InstallStage.signatureMismatch, latest);
        unawaited(_events.flush());
        _fail(UpdateFailure.signature);
        return;
      case InstallStatus.failed:
        await _emit(InstallStage.installFail, latest);
        unawaited(_events.flush());
        _fail(UpdateFailure.install);
        return;
    }
    unawaited(_events.flush());
    notifyListeners();
  }

  /// "Open settings" on the permission step.
  Future<void> openPermissionSettings() => _installer.openInstallSettings();

  /// Back from system settings: carry on if the user said yes.
  Future<void> _resumeInstall() async {
    if (await _installer.canInstall()) await install();
  }

  /// Leaves the permission step without installing.
  void cancelPermission() {
    if (_phase != UpdatePhase.needsPermission) return;
    _phase = UpdatePhase.ready;
    notifyListeners();
  }

  /// Clears a failure so the UI shows the buttons again.
  void dismissFailure() {
    if (_phase != UpdatePhase.failed) return;
    _phase = _apkPath == null ? UpdatePhase.idle : UpdatePhase.ready;
    _failure = null;
    notifyListeners();
  }

  // ---- defaults ----------------------------------------------------------------

  static Future<int> _installedBuild() async {
    final info = await PackageInfo.fromPlatform();
    return UpdatePolicy.buildFromVersionCode(
      int.tryParse(info.buildNumber) ?? 0,
    );
  }

  static Future<bool> _wifiNow() async {
    try {
      final r = await Connectivity().checkConnectivity();
      return r.contains(ConnectivityResult.wifi) ||
          r.contains(ConnectivityResult.ethernet);
    } catch (_) {
      return false;
    }
  }

  static Future<void> _notifyNow(UpdateRelease r) async {
    await NotificationCenter.instance.post(
      NotifyKind.appUpdate,
      key: 'build-${r.build}',
      title: UpdateStrings.notifyTitle,
      body: UpdateStrings.notifyBody(r.title),
      target: const SettingsTarget('about'),
    );
  }
}
