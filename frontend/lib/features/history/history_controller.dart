import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/constants/app_sizes.dart';
import '../../data/chat_api.dart';
import '../../data/conversation.dart';
import '../../data/conversations_api.dart';

class HistoryController extends ChangeNotifier {
  HistoryController(this._api);

  final ConversationsApi _api;

  List<ConversationSummary> items = [];
  bool loading = true;
  String? error;
  String query = '';

  /// Showing the archive instead of the main list.
  bool archived = false;
  Timer? _debounce;
  int _request = 0;

  Future<void> load() async {
    final request = ++_request;
    try {
      final result = await _api.list(query: query, archived: archived);
      if (request != _request) return;
      items = result;
      error = null;
    } on ApiException catch (e) {
      if (request != _request) return;
      error = e.message;
    }
    loading = false;
    notifyListeners();
  }

  /// Chats matching [text] without touching the visible list (merge picker).
  Future<List<ConversationSummary>> find(String text) => _api.list(query: text);

  void search(String text) {
    query = text;
    _debounce?.cancel();
    _debounce = Timer(AppDurations.searchDebounce, load);
  }

  Future<ConversationSummary?> rename(String id, String title) async {
    try {
      final updated = await _api.rename(id, title);
      items = [for (final c in items) c.id == id ? updated : c];
      notifyListeners();
      return updated;
    } on ApiException {
      return null;
    }
  }

  void showArchived(bool value) {
    if (archived == value) return;
    archived = value;
    items = [];
    loading = true;
    notifyListeners();
    load();
  }

  /// Pins or unpins, then reloads so the order is right.
  Future<bool> setPinned(String id, bool pinned) async {
    try {
      await _api.setPinned(id, pinned);
      await load();
      return true;
    } on ApiException {
      return false;
    }
  }

  /// Moves a chat in or out of the archive; it leaves the current list.
  Future<bool> setArchived(String id, bool value) async {
    try {
      await _api.setArchived(id, value);
      if (value != archived) {
        items = items.where((c) => c.id != id).toList();
        notifyListeners();
      } else {
        await load();
      }
      return true;
    } on ApiException {
      return false;
    }
  }

  Future<bool> delete(String id) async {
    try {
      await _api.delete(id);
      items = items.where((c) => c.id != id).toList();
      notifyListeners();
      return true;
    } on ApiException {
      return false;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
