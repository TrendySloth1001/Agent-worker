import 'package:flutter/foundation.dart';

import '../../core/errors/errors_api.dart';
import '../../core/errors/errors_models.dart';

/// State of the owner's Errors screen: error groups for a build (most users first),
/// the crash-free sessions per build, and resolve/ignore.
class ErrorsController extends ChangeNotifier {
  ErrorsController(this.api);

  final ErrorsApi api;

  ErrorGroupList? groups;
  List<BuildHealth> health = const [];
  bool loading = false;
  bool failed = false;

  /// Null: all builds.
  int? build;
  ErrorStatus? status = ErrorStatus.open;

  Future<void> load() async {
    if (loading) return;
    loading = true;
    failed = false;
    notifyListeners();
    try {
      final results = await Future.wait([
        api.groups(build: build, status: status?.name ?? 'all'),
        api.buildHealth(),
      ]);
      groups = results[0] as ErrorGroupList;
      health = results[1] as List<BuildHealth>;
    } catch (_) {
      failed = true;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> selectBuild(int? value) {
    build = value;
    return load();
  }

  Future<void> selectStatus(ErrorStatus? value) {
    status = value;
    return load();
  }

  List<ErrorGroup> get items => groups?.groups ?? const [];
  List<int> get builds => groups?.builds ?? const [];
}

/// State of one group's detail page.
class ErrorDetailController extends ChangeNotifier {
  ErrorDetailController(this.api, this.fingerprint);

  final ErrorsApi api;
  final String fingerprint;

  ErrorGroupDetail? detail;
  bool loading = false;
  bool failed = false;

  /// event id -> e-mail (or '' when none), fetched on an explicit tap.
  final emails = <String, String>{};

  Future<void> load() async {
    if (loading) return;
    loading = true;
    failed = false;
    notifyListeners();
    try {
      detail = await api.detail(fingerprint);
    } catch (_) {
      failed = true;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<bool> setStatus(ErrorStatus status) async {
    try {
      await api.setStatus(fingerprint, status);
      detail = await api.detail(fingerprint);
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> revealUser(String eventId) async {
    try {
      emails[eventId] = await api.userEmail(eventId) ?? '';
    } catch (_) {
      emails[eventId] = '';
    }
    notifyListeners();
  }
}
