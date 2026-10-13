import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/constants/error_copy.dart';
import '../../core/constants/storage.dart';
import '../../data/chat_api.dart';
import '../../data/files_api.dart';

/// State of the Storage screen: usage, the filtered file list (paged),
/// and the multi-selection.
class StorageController extends ChangeNotifier {
  StorageController({FilesApi? api}) : _api = api ?? FilesApi.instance;

  final FilesApi _api;

  StorageUsage? usage;
  final List<FileInfo> files = [];
  FileKind? kind;
  String query = '';
  StorageSort sort = StorageSort.newest;

  bool loading = false;
  bool loadingMore = false;
  String? error;
  String? _cursor;
  bool get hasMore => _cursor != null;

  /// Ids of selected files; selection mode while non-empty or [selecting].
  final Set<String> selected = {};
  bool _selecting = false;
  bool get selecting => _selecting || selected.isNotEmpty;

  /// Bumped per [reload] so a slow older response never replaces a newer one.
  int _generation = 0;
  Timer? _debounce;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> reload() async {
    final gen = ++_generation;
    loading = true;
    error = null;
    _notify();
    try {
      final results = await Future.wait([
        _api.list(kind: kind, query: query, sort: sort),
        _api.usage(),
      ]);
      if (gen != _generation) return;
      final page = results[0] as FilePage;
      usage = results[1] as StorageUsage;
      files
        ..clear()
        ..addAll(page.files);
      _cursor = page.nextCursor;
      selected.removeWhere((id) => !files.any((f) => f.id == id));
    } catch (e) {
      if (gen != _generation) return;
      error = e is ApiException
          ? friendlyException(e)
          : StorageStrings.loadFailed;
    } finally {
      if (gen == _generation) {
        loading = false;
        _notify();
      }
    }
  }

  Future<void> loadMore() async {
    final cursor = _cursor;
    if (cursor == null || loadingMore || loading) return;
    final gen = _generation;
    loadingMore = true;
    _notify();
    try {
      final page = await _api.list(
        kind: kind,
        query: query,
        sort: sort,
        cursor: cursor,
      );
      if (gen != _generation) return;
      final known = files.map((f) => f.id).toSet();
      files.addAll(page.files.where((f) => !known.contains(f.id)));
      _cursor = page.nextCursor;
    } catch (_) {
      // The LOAD MORE button stays; the user can try again.
    } finally {
      loadingMore = false;
      _notify();
    }
  }

  void setKind(FileKind? value) {
    if (value == kind) return;
    kind = value;
    unawaited(reload());
  }

  void setSort(StorageSort value) {
    if (value == sort) return;
    sort = value;
    unawaited(reload());
  }

  /// Debounced search as the user types.
  void setQuery(String value) {
    if (value.trim() == query.trim()) return;
    query = value;
    _debounce?.cancel();
    _debounce = Timer(StorageConfig.searchDebounce, reload);
  }

  // ---- selection --------------------------------------------------------

  void startSelecting([String? id]) {
    _selecting = true;
    if (id != null) selected.add(id);
    _notify();
  }

  void toggle(String id) {
    if (!selected.remove(id)) selected.add(id);
    _notify();
  }

  void selectAll() {
    selected.addAll(files.map((f) => f.id));
    _notify();
  }

  void clearSelection() {
    selected.clear();
    _selecting = false;
    _notify();
  }

  // ---- changes ------------------------------------------------------------

  /// Deletes [ids] on the server; returns how many were removed, or null
  /// on failure (nothing changes locally then).
  Future<int?> delete(List<String> ids) async {
    if (ids.isEmpty) return 0;
    try {
      final n = ids.length == 1
          ? await _api.delete(ids.first).then((_) => 1)
          : await _api.bulkDelete(ids);
      final gone = ids.toSet();
      files.removeWhere((f) => gone.contains(f.id));
      selected.removeAll(gone);
      if (selected.isEmpty) _selecting = false;
      _notify();
      unawaited(_refreshUsage());
      return n;
    } catch (_) {
      return null;
    }
  }

  Future<bool> rename(FileInfo file, String name) async {
    try {
      final fresh = await _api.rename(file.id, name);
      final i = files.indexWhere((f) => f.id == file.id);
      if (i >= 0) files[i] = files[i].renamed(fresh.name);
      _notify();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _refreshUsage() async {
    try {
      usage = await _api.usage();
      _notify();
    } catch (_) {
      /* the meter keeps the last value */
    }
  }
}
