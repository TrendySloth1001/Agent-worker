import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/constants/error_copy.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/constants/app_strings.dart';
import '../../core/notify/job_watch.dart';
import '../../data/chat_api.dart';
import '../../data/kb_source.dart';
import '../../data/knowledge_api.dart';

class KnowledgeController extends ChangeNotifier {
  KnowledgeController(this._api);

  final KnowledgeApi _api;

  List<KbSource> sources = [];
  bool loading = true;

  /// Set when the list could not be loaded.
  String? loadError;

  Timer? _poll;
  bool _disposed = false;

  Future<void> load() async {
    try {
      sources = await _api.list();
      loadError = null;
      for (final s in sources) {
        JobWatch.instance.watchSource(s);
      }
    } catch (error) {
      if (sources.isEmpty) loadError = _message(error);
    }
    loading = false;
    _syncPolling();
    _notify();
  }

  /// Returns an error message, or null when the source was queued.
  Future<String?> add(String input, {required String type, int? limit}) async {
    try {
      final source = await _api.add(input, type: type, limit: limit);
      sources = [source, ...sources.where((s) => s.id != source.id)];
      JobWatch.instance.watchSource(source);
      loadError = null;
      _syncPolling();
      _notify();
      return null;
    } catch (error) {
      return _message(error);
    }
  }

  Future<void> refresh(String id) async {
    try {
      final updated = await _api.refresh(id);
      sources = [for (final s in sources) s.id == id ? updated : s];
      JobWatch.instance.watchSource(updated);
      _syncPolling();
      _notify();
    } catch (_) {
      await load();
    }
  }

  Future<void> delete(String id) async {
    sources = sources.where((s) => s.id != id).toList();
    _syncPolling();
    _notify();
    try {
      await _api.delete(id);
    } catch (_) {
      await load();
    }
  }

  /// Polls only while something is queued or running.
  void _syncPolling() {
    final active = sources.any((s) => s.isActive);
    if (active && _poll == null && !_disposed) {
      _poll = Timer.periodic(AppDurations.kbPoll, (_) => load());
    } else if (!active) {
      _poll?.cancel();
      _poll = null;
    }
  }

  String _message(Object error) => error is ApiException
      ? friendlyException(error)
      : AppStrings.errorGeneric;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    super.dispose();
  }
}
