import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/constants/app_sizes.dart';
import '../../core/constants/history.dart';
import '../../data/chat_api.dart';
import '../../data/conversation.dart';
import '../../data/conversations_api.dart';

class HistoryController extends ChangeNotifier {
  HistoryController(this._api, {int pageSize = HistorySizes.pageSize})
    : _pageSize = pageSize;

  final ConversationsApi _api;
  final int _pageSize;

  /// The unfiltered list (main or archive).
  List<ConversationSummary> items = [];

  /// Server results for [query]; null until they arrive.
  List<ConversationSummary>? _found;
  String _foundFor = '';

  bool loading = true;
  bool loadingMore = false;
  bool hasMore = false;
  String? error;
  String query = '';

  /// Showing the archive instead of the main list.
  bool archived = false;

  /// Chat being renamed inline, if any.
  String? renamingId;

  Timer? _debounce;
  int _request = 0;

  bool get searching => query.trim().isNotEmpty;

  /// Waiting for the server to answer the current search.
  bool get searchPending => searching && _foundFor != query.trim();

  /// What the list shows: everything, or the matches of [query] (the server's
  /// answer once it is in, a local filter of what is loaded until then).
  List<ConversationSummary> get visible {
    if (!searching) return items;
    final q = query.trim();
    final found = _found;
    if (found != null && _foundFor == q) return found;
    final lower = q.toLowerCase();
    return [
      for (final c in items)
        if ((c.title ?? '').toLowerCase().contains(lower) ||
            c.preview.toLowerCase().contains(lower))
          c,
    ];
  }

  /// First page of the current list (pull to refresh, opening, retry).
  Future<void> load() async {
    final request = ++_request;
    final q = query.trim();
    try {
      final result = await _api.list(
        query: q,
        archived: archived,
        limit: _pageSize,
      );
      if (request != _request) return;
      if (q.isEmpty) {
        items = result;
      } else {
        _found = result;
        _foundFor = q;
      }
      hasMore = result.length >= _pageSize;
      error = null;
    } on ApiException catch (e) {
      if (request != _request) return;
      error = e.message;
    }
    loading = false;
    loadingMore = false;
    notifyListeners();
  }

  /// The next page, once the list scrolls near its end.
  Future<void> loadMore() async {
    if (loading || loadingMore || !hasMore || searchPending) return;
    final list = visible;
    DateTime? cursor;
    for (final c in list.reversed) {
      if (!c.pinned) {
        cursor = c.updatedAt;
        break;
      }
    }
    if (cursor == null) return;
    loadingMore = true;
    notifyListeners();
    final request = _request;
    final q = query.trim();
    try {
      final more = await _api.list(
        query: q,
        archived: archived,
        limit: _pageSize,
        before: cursor,
      );
      if (request != _request) return;
      final seen = {for (final c in list) c.id};
      final fresh = [
        for (final c in more)
          if (!c.pinned && seen.add(c.id)) c,
      ];
      if (q.isEmpty) {
        items = [...items, ...fresh];
      } else {
        _found = [...?_found, ...fresh];
      }
      hasMore = more.length >= _pageSize;
    } on ApiException {
      if (request != _request) return;
      hasMore = false;
    }
    loadingMore = false;
    notifyListeners();
  }

  /// Chats matching [text] without touching the visible list (merge picker).
  Future<List<ConversationSummary>> find(String text) => _api.list(query: text);

  /// Filters locally at once, asks the server after a short pause.
  void search(String text) {
    query = text;
    _debounce?.cancel();
    if (!searching) {
      _found = null;
      _foundFor = '';
      notifyListeners();
      load();
      return;
    }
    notifyListeners();
    _debounce = Timer(AppDurations.searchDebounce, load);
  }

  void clearSearch() => search('');

  void beginRename(String id) {
    renamingId = id;
    notifyListeners();
  }

  void cancelRename() {
    if (renamingId == null) return;
    renamingId = null;
    notifyListeners();
  }

  List<ConversationSummary> _swap(
    List<ConversationSummary> list,
    String id,
    ConversationSummary updated,
  ) => [for (final c in list) c.id == id ? updated : c];

  Future<ConversationSummary?> rename(String id, String title) async {
    try {
      final updated = await _api.rename(id, title);
      items = _swap(items, id, updated);
      if (_found != null) _found = _swap(_found!, id, updated);
      renamingId = null;
      notifyListeners();
      return updated;
    } on ApiException {
      return null;
    }
  }

  void showArchived(bool value) {
    if (archived == value) return;
    archived = value;
    query = '';
    _found = null;
    _foundFor = '';
    renamingId = null;
    items = [];
    loading = true;
    hasMore = false;
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

  void _drop(String id) {
    items = items.where((c) => c.id != id).toList();
    if (_found != null) _found = _found!.where((c) => c.id != id).toList();
    notifyListeners();
  }

  /// Moves a chat in or out of the archive; it leaves the current list.
  Future<bool> setArchived(String id, bool value) async {
    try {
      await _api.setArchived(id, value);
      if (value != archived) {
        _drop(id);
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
      _drop(id);
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
