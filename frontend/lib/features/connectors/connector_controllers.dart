import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/connect_api.dart';
import 'connector_auth.dart';

/// Shared load state: the last good data survives a failed refresh, so an
/// offline or rate-limited screen keeps showing it with a retry banner.
abstract class ConnectorListController<T> extends ChangeNotifier {
  ConnectorListController({ConnectApi? api}) : _apiOverride = api;

  final ConnectApi? _apiOverride;
  ConnectApi get api => _apiOverride ?? ConnectApi.instance;

  List<T>? items;
  bool loading = false;
  ConnectException? error;
  String query = '';
  int _seq = 0;

  bool get loaded => items != null;
  bool get offline => error?.offline ?? false;
  bool get rateLimited => error?.rateLimited ?? false;
  bool get needsReauth => error?.needsReauth ?? false;

  @protected
  Future<List<T>> fetch(String query);

  Future<void> load() async {
    final seq = ++_seq;
    loading = true;
    notifyListeners();
    try {
      final r = await fetch(query);
      if (seq != _seq) return;
      items = r;
      error = null;
    } on ConnectException catch (e) {
      if (seq != _seq) return;
      error = e;
    } finally {
      if (seq == _seq) {
        loading = false;
        notifyListeners();
      }
    }
  }

  void setQuery(String q) {
    if (q == query) return;
    query = q;
    unawaited(load());
  }

  /// Signed out or disconnected: forget the data.
  void clear() {
    _seq++;
    items = null;
    error = null;
    loading = false;
    query = '';
    notifyListeners();
  }
}

/// Files sparky can see in Drive; reloads after the picker added some.
class DriveController extends ConnectorListController<DriveFile> {
  DriveController({super.api}) {
    _sub = ConnectorAuth.instance.outcomes.listen((o) {
      if (o.flow == ConnectorFlow.picker && o.ok) unawaited(load());
    });
  }

  StreamSubscription<ConnectorOutcome>? _sub;

  @override
  Future<List<DriveFile>> fetch(String query) => api.driveFiles(query: query);

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

/// Pages and databases shared with sparky; [query] searches them.
class NotionController extends ConnectorListController<NotionItem> {
  NotionController({super.api});

  @override
  Future<List<NotionItem>> fetch(String query) =>
      api.notionSearch(query: query);
}
