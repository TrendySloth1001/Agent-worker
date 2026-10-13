import 'package:flutter/foundation.dart';

import '../../core/constants/update.dart';
import '../../core/update/update_api.dart';
import '../../core/update/update_models.dart';
import '../../data/chat_api.dart';

/// State of the owner's Releases screen: the list, the adoption numbers and
/// the actions on a release. Every action returns whether it worked.
class ReleasesController extends ChangeNotifier {
  ReleasesController(this.api);

  final UpdateApi api;

  ReleaseList? data;
  bool loading = false;
  bool failed = false;

  /// 0..1 while an APK is being uploaded; null otherwise.
  double? uploadProgress;

  List<OwnerRelease> get releases => data?.releases ?? const [];
  List<AdoptionRow> get adoption => data?.adoption ?? const [];

  Future<void> load() async {
    if (loading) return;
    loading = true;
    failed = false;
    notifyListeners();
    try {
      data = await api.releases();
    } catch (_) {
      failed = true;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<bool> goLive(OwnerRelease r) =>
      edit(r, const ReleaseEdit(status: ReleaseStatus.live));

  Future<bool> pull(OwnerRelease r) =>
      edit(r, const ReleaseEdit(status: ReleaseStatus.pulled));

  Future<bool> edit(OwnerRelease r, ReleaseEdit change) async {
    try {
      final updated = await api.edit(r.id, change);
      _replace(updated);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> delete(OwnerRelease r) async {
    try {
      await api.delete(r.id);
      final d = data;
      if (d != null) {
        data = ReleaseList(
          releases: [
            for (final x in d.releases)
              if (x.id != r.id) x,
          ],
          adoption: d.adoption,
        );
      }
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Uploads an APK. Returns null on success, else a message for the owner.
  Future<String?> upload({
    required String path,
    required String version,
    required int build,
    required UpdateKind kind,
    required String title,
    required List<String> notes,
    int? minSupportedBuild,
    bool live = false,
  }) async {
    uploadProgress = 0;
    notifyListeners();
    try {
      final created = await api.upload(
        path: path,
        version: version,
        build: build,
        kind: kind,
        title: title,
        notes: notes,
        minSupportedBuild: minSupportedBuild,
        live: live,
        onProgress: (p) {
          uploadProgress = p;
          notifyListeners();
        },
      );
      final d = data ?? const ReleaseList();
      data = ReleaseList(
        releases: [created, ...d.releases],
        adoption: d.adoption,
      );
      return null;
    } on ApiException catch (e) {
      return e.status == 409 ? UpdateStrings.buildExists : e.message;
    } catch (_) {
      return UpdateStrings.uploadFailed;
    } finally {
      uploadProgress = null;
      notifyListeners();
    }
  }

  void _replace(OwnerRelease updated) {
    final d = data;
    if (d == null) return;
    data = ReleaseList(
      releases: [for (final x in d.releases) x.id == updated.id ? updated : x],
      adoption: d.adoption,
    );
    notifyListeners();
  }
}
