import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/constants/memory.dart';
import '../../data/memory_api.dart';

/// State of the Memory screen: the on/off switch, the (searchable) list and
/// optimistic edits that roll back when the server refuses them.
class MemoryController extends ChangeNotifier {
  MemoryController({MemoryApi? api}) : _api = api ?? MemoryApi.instance;

  final MemoryApi _api;

  bool enabled = true;
  bool chatRecall = true;
  List<MemoryItem> items = [];
  int total = 0;
  String query = '';
  bool loading = false;
  String? error;

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
      final page = await _api.list(query: query);
      if (gen != _generation) return;
      enabled = page.enabled;
      chatRecall = page.chatRecall;
      total = page.total;
      items = page.items;
    } catch (_) {
      if (gen != _generation) return;
      error = MemoryStrings.loadFailed;
    }
    loading = false;
    _notify();
  }

  void setQuery(String value) {
    query = value;
    _debounce?.cancel();
    _debounce = Timer(MemoryConfig.searchDebounce, reload);
  }

  /// Returns false (and keeps the old value) when the server refuses.
  Future<bool> setEnabled(bool value) async {
    final before = enabled;
    enabled = value;
    _notify();
    try {
      enabled = await _api.setEnabled(value);
      _notify();
      return true;
    } catch (_) {
      enabled = before;
      _notify();
      return false;
    }
  }

  /// Returns false (and keeps the old value) when the server refuses.
  Future<bool> setChatRecall(bool value) async {
    final before = chatRecall;
    chatRecall = value;
    _notify();
    try {
      chatRecall = await _api.setChatRecall(value);
      _notify();
      return true;
    } catch (_) {
      chatRecall = before;
      _notify();
      return false;
    }
  }

  Future<bool> add(String text) async {
    try {
      await _api.create(text);
      await reload();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> edit(MemoryItem item, String text) => _patch(item, text: text);

  Future<bool> togglePin(MemoryItem item) => _patch(item, pinned: !item.pinned);

  Future<bool> _patch(MemoryItem item, {String? text, bool? pinned}) async {
    try {
      final saved = await _api.update(item.id, text: text, pinned: pinned);
      final i = items.indexWhere((m) => m.id == item.id);
      if (i >= 0) items = [...items]..[i] = saved;
      // Pinned memories sort first.
      items = [
        ...items.where((m) => m.pinned),
        ...items.where((m) => !m.pinned),
      ];
      _notify();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> delete(MemoryItem item) async {
    final before = items;
    items = items.where((m) => m.id != item.id).toList();
    total = (total - 1).clamp(0, 1 << 30);
    _notify();
    try {
      await _api.delete(item.id);
      return true;
    } catch (_) {
      items = before;
      total += 1;
      _notify();
      return false;
    }
  }

  Future<bool> clearAll() async {
    try {
      await _api.clear();
      items = [];
      total = 0;
      _notify();
      return true;
    } catch (_) {
      return false;
    }
  }
}
