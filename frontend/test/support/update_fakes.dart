import 'dart:async';

import 'package:app/core/update/update_api.dart';
import 'package:app/core/update/update_controller.dart';
import 'package:app/core/update/update_downloader.dart';
import 'package:app/core/update/update_installer.dart';
import 'package:app/core/update/update_models.dart';
import 'package:app/core/update/update_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

UpdateRelease fakeRelease({
  UpdateKind kind = UpdateKind.feature,
  int build = 30,
  String version = '1.7.0',
  String title = 'Faster chats and a calmer look',
  List<String> notes = const [
    'Replies start sooner',
    'A new look for settings',
    'Fewer hiccups on slow networks',
  ],
  int size = 25 * 1024 * 1024,
}) => UpdateRelease(
  version: version,
  build: build,
  kind: kind,
  title: title,
  notes: notes,
  size: size,
  sha256: 'abc123',
  url: 'https://files.example/app.apk',
);

class FakeUpdateApi implements UpdateApi {
  FakeUpdateApi({this.info, this.list = const ReleaseList()});

  UpdateInfo? info;
  Object? error;
  int checks = 0;
  ReleaseList list;
  final calls = <String>[];

  @override
  Future<UpdateInfo> check(int build) async {
    checks++;
    if (error != null) throw error!;
    return info ?? UpdateInfo(current: build);
  }

  @override
  Future<ReleaseList> releases() async => list;

  @override
  Future<OwnerRelease> edit(String id, ReleaseEdit edit) async {
    calls.add('edit:$id:${edit.toJson()}');
    final old = list.releases.firstWhere((r) => r.id == id);
    return OwnerRelease(
      id: id,
      release: UpdateRelease(
        version: old.version,
        build: old.build,
        kind: edit.kind ?? old.kind,
        title: edit.title ?? old.title,
        notes: edit.notes ?? old.notes,
        size: old.size,
        sha256: old.release.sha256,
        url: old.release.url,
      ),
      status: edit.status ?? old.status,
      minSupportedBuild: edit.clearMin
          ? null
          : (edit.minSupportedBuild ?? old.minSupportedBuild),
      createdAt: old.createdAt,
      publishedAt: old.publishedAt,
    );
  }

  @override
  Future<void> delete(String id) async => calls.add('delete:$id');

  @override
  Future<OwnerRelease> upload({
    required String path,
    required String version,
    required int build,
    required UpdateKind kind,
    required String title,
    required List<String> notes,
    int? minSupportedBuild,
    bool live = false,
    void Function(double progress)? onProgress,
  }) async {
    calls.add('upload:$version:$build:${kind.name}:live=$live');
    onProgress?.call(0.5);
    return OwnerRelease(
      id: 'new',
      release: UpdateRelease(
        version: version,
        build: build,
        kind: kind,
        title: title,
        notes: notes,
      ),
      status: live ? ReleaseStatus.live : ReleaseStatus.draft,
      createdAt: DateTime(2026, 10, 13),
    );
  }
}

class FakeInstaller implements UpdateInstaller {
  bool allowed = true;
  InstallStatus result = InstallStatus.success;
  final installed = <String>[];
  int settingsOpened = 0;

  @override
  Future<bool> canInstall() async => allowed;

  @override
  Future<void> openInstallSettings() async => settingsOpened++;

  @override
  Future<InstallStatus> install(String path) async {
    installed.add(path);
    return result;
  }
}

class FakeDownloader implements UpdateDownloader {
  Object? error;
  int downloads = 0;
  final existing = <String>{};
  bool cleared = false;

  /// While set, a download stays at 50% until it completes.
  Completer<void>? gate;

  @override
  Future<String> pathFor(UpdateRelease r) async => '/cache/${r.build}.apk';

  @override
  Future<bool> isComplete(UpdateRelease r, String path) async =>
      existing.contains(path);

  @override
  Future<String> download(
    UpdateRelease r, {
    required void Function(double progress) onProgress,
  }) async {
    downloads++;
    onProgress(0.5);
    if (gate != null) await gate!.future;
    if (error != null) throw error!;
    final path = await pathFor(r);
    existing.add(path);
    onProgress(1);
    return path;
  }

  @override
  Future<void> clear() async {
    cleared = true;
    existing.clear();
  }
}

/// A controller wired to fakes, with a clock the test can move.
class UpdateRig {
  UpdateRig({
    UpdateInfo? info,
    this.wifi = true,
    Map<String, Object> prefs = const {},
    this.build = 25,
  }) : api = FakeUpdateApi(info: info) {
    SharedPreferences.setMockInitialValues(prefs);
    controller = UpdateController(
      api: api,
      installer: installer,
      downloader: downloader,
      store: UpdateStore.open,
      currentBuild: () async => build,
      onWifi: () async => wifi,
      clock: () => now,
      notify: (r) async => notified.add(r.build),
      startDelay: const Duration(seconds: 3),
    );
  }

  final FakeUpdateApi api;
  final installer = FakeInstaller();
  final downloader = FakeDownloader();
  late final UpdateController controller;
  bool wifi;
  int build;
  DateTime now = DateTime(2026, 10, 13, 12);
  final notified = <int>[];
}
