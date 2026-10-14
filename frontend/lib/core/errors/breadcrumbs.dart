import 'package:flutter/widgets.dart';

import '../constants/errors.dart';

/// One trail entry: a category and a short code, never free text.
class Crumb {
  const Crumb(this.at, this.kind, this.label);

  final int at;
  final CrumbKind kind;
  final String label;

  Map<String, dynamic> toJson() => {'t': at, 'c': kind.name, 'm': label};
}

/// A ring buffer of the last [ErrorsConfig.breadcrumbs] things the app did.
///
/// Privacy by construction: there is no method that takes free text. Labels come from
/// enums (update phase, lifecycle state, connectivity type) or from a route name that is
/// reduced to a bare path with ids removed ([routeLabel]). Chat messages, prompts, file
/// names, URLs and request bodies cannot reach this class.
class Breadcrumbs {
  Breadcrumbs({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  static final instance = Breadcrumbs();

  final DateTime Function() _clock;
  final _items = <Crumb>[];

  List<Crumb> get items => List.unmodifiable(_items);

  void _add(CrumbKind kind, String label) {
    _items.add(Crumb(_clock().millisecondsSinceEpoch, kind, label));
    if (_items.length > ErrorsConfig.breadcrumbs) {
      _items.removeRange(0, _items.length - ErrorsConfig.breadcrumbs);
    }
  }

  void route(String action, Route<dynamic>? route) =>
      _add(CrumbKind.route, '$action ${routeLabel(route?.settings.name)}');

  /// [phase] is an enum name such as `downloading`.
  void update(Enum phase) => _add(CrumbKind.update, _code(phase.name));

  void lifecycle(AppLifecycleState state) =>
      _add(CrumbKind.lifecycle, _code(state.name));

  /// [types] are connectivity enum names (`wifi`, `mobile`, `none`).
  void net(Iterable<Enum> types) =>
      _add(CrumbKind.net, types.map((t) => _code(t.name)).join('+'));

  void memoryPressure() => _add(CrumbKind.memory, 'pressure');

  void clear() => _items.clear();

  List<Map<String, dynamic>> toJson() => [for (final c in _items) c.toJson()];

  static String _code(String s) =>
      s.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '').toLowerCase();

  static final _uuid = RegExp(
    r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
  );

  /// A route name as a bare path: query and fragment cut, uuids and long numbers
  /// replaced by `:id`, anything that is not a plain path (spaces, dots, text) becomes
  /// `unnamed`.
  static String routeLabel(String? name) {
    if (name == null || name.isEmpty) return 'unnamed';
    var s = name.split('?').first.split('#').first;
    s = s.replaceAll(_uuid, ':id').replaceAll(RegExp(r'\d{3,}'), ':id');
    if (!RegExp(r'^/[A-Za-z0-9_/:-]*$').hasMatch(s)) return 'unnamed';
    return s.length > ErrorsConfig.maxRouteName
        ? s.substring(0, ErrorsConfig.maxRouteName)
        : s;
  }
}

/// Feeds route changes into [Breadcrumbs]. Add it to `MaterialApp.navigatorObservers`.
class BreadcrumbObserver extends NavigatorObserver {
  BreadcrumbObserver([Breadcrumbs? crumbs])
    : _crumbs = crumbs ?? Breadcrumbs.instance;

  final Breadcrumbs _crumbs;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _crumbs.route('push', route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _crumbs.route('pop', route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _crumbs.route('replace', newRoute);
}
