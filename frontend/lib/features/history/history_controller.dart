import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/constants/error_copy.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/constants/chat_cleanup.dart';
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

  /// Selection mode: rows show a check and taps pick chats.
  bool selecting = false;

  /// Picked chat ids. Kept while scrolling, searching and paging.
  final Set<String> selected = {};

  /// "Select all" is loading the pages not seen yet.
  bool selectingAll = false;

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
      error = friendlyException(e);
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

  // ---- Selection ---------------------------------------------------------------

  /// Enters selection mode, picking [id] when given.
  void startSelection([String? id]) {
    selecting = true;
    renamingId = null;
    if (id != null) selected.add(id);
    notifyListeners();
  }

  void endSelection() {
    if (!selecting && selected.isEmpty) return;
    selecting = false;
    selectingAll = false;
    selected.clear();
    notifyListeners();
  }

  void toggleSelected(String id) {
    if (!selected.remove(id)) selected.add(id);
    notifyListeners();
  }

  bool isSelected(String id) => selected.contains(id);

  /// Every listed chat is picked and there are no pages left to load.
  bool get allSelected {
    final list = visible;
    return !hasMore &&
        list.isNotEmpty &&
        list.every((c) => selected.contains(c.id));
  }

  /// Picks every chat in the current list (all of it, or every match of
  /// the search), loading the pages not shown yet first.
  Future<void> selectAll() async {
    selecting = true;
    selectingAll = true;
    notifyListeners();
    var pages = 0;
    while (hasMore && error == null && pages++ < ChatCleanupSizes.maxPages) {
      final before = visible.length;
      await loadMore();
      if (!selectingAll) return; // left selection mode meanwhile
      if (visible.length == before) break;
    }
    selectingAll = false;
    selected.addAll(visible.map((c) => c.id));
    notifyListeners();
  }

  void selectNone() {
    selected.clear();
    notifyListeners();
  }

  /// Picked chats this list knows about.
  List<ConversationSummary> get selectedChats {
    final seen = <String>{};
    return [
      for (final c in [...items, ...?_found])
        if (selected.contains(c.id) && seen.add(c.id)) c,
    ];
  }

  /// Every picked chat is pinned (the action then unpins).
  bool get selectionPinned {
    final chats = selectedChats;
    return chats.isNotEmpty && chats.every((c) => c.pinned);
  }

  /// Runs [op] for [ids], a few at a time. Returns the ids it worked for.
  Future<List<String>> _each(
    List<String> ids,
    Future<void> Function(String id) op,
  ) async {
    final done = <String>[];
    for (var i = 0; i < ids.length; i += ChatCleanupSizes.parallel) {
      final end = i + ChatCleanupSizes.parallel;
      final group = ids.sublist(i, end > ids.length ? ids.length : end);
      await Future.wait(
        group.map((id) async {
          try {
            await op(id);
            done.add(id);
          } on ApiException {
            // Reported by the count; the chat stays as it was.
          }
        }),
      );
    }
    return done;
  }

  /// Deletes the picked chats: they leave the list at once and come back
  /// only if the server refuses. Returns the deleted ids, or null.
  Future<List<String>?> deleteSelected() async {
    final ids = selected.toList();
    if (ids.isEmpty) return const [];
    final keepItems = items;
    final keepFound = _found;
    final gone = selected.toSet();
    items = [
      for (final c in items)
        if (!gone.contains(c.id)) c,
    ];
    if (_found != null) {
      _found = [
        for (final c in _found!)
          if (!gone.contains(c.id)) c,
      ];
    }
    selecting = false;
    selectingAll = false;
    selected.clear();
    notifyListeners();
    try {
      await _api.deleteMany(ids);
      return ids;
    } on ApiException {
      items = keepItems;
      _found = keepFound;
      notifyListeners();
      await load(); // some batches may have gone through
      return null;
    }
  }

  /// Archives the picked chats (restores them in the archive). Returns how
  /// many moved; the rest stay picked.
  Future<int> archiveSelected() async {
    final value = !archived;
    final done = await _each(
      selected.toList(),
      (id) => _api.setArchived(id, value),
    );
    final gone = done.toSet();
    items = [
      for (final c in items)
        if (!gone.contains(c.id)) c,
    ];
    if (_found != null) {
      _found = [
        for (final c in _found!)
          if (!gone.contains(c.id)) c,
      ];
    }
    selected.removeAll(gone);
    if (selected.isEmpty) selecting = false;
    notifyListeners();
    return done.length;
  }

  /// Pins the picked chats, or unpins them when all are pinned. Returns
  /// whether every one changed.
  Future<bool> pinSelected() async {
    final pin = !selectionPinned;
    final ids = selected.toList();
    final done = await _each(ids, (id) => _api.setPinned(id, pin));
    selecting = false;
    selected.clear();
    await load();
    return done.length == ids.length;
  }

  void showArchived(bool value) {
    if (archived == value) return;
    archived = value;
    selecting = false;
    selectingAll = false;
    selected.clear();
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
