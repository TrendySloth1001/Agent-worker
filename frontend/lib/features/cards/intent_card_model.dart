import 'dart:convert';

import '../../core/constants/intent_cards.dart';

/// One thing a button asks the phone to do. Built only through [parse], which
/// applies the same allow-lists as the server and CardIntents.kt: an unknown
/// action, scheme, host, extra or package never becomes a runnable intent.
class CardIntent {
  const CardIntent({
    required this.action,
    this.uri,
    this.package,
    this.fallback,
    this.chooser = false,
    this.extras = const {},
  });

  final String action;
  final String? uri;
  final String? package;

  /// https link tried when the intent cannot run (the app is missing).
  final String? fallback;
  final bool chooser;
  final Map<String, Object> extras;

  static CardIntent? parse(Object? raw) {
    if (raw is! Map) return null;
    final action = raw[IntentCardWire.action];
    if (action is! String || !IntentCardPolicy.uriSchemes.containsKey(action)) {
      return null;
    }
    final schemes = IntentCardPolicy.uriSchemes[action]!;
    final uriRaw = raw[IntentCardWire.uri];
    String? uri;
    if (uriRaw != null) {
      if (uriRaw is! String || !_allowedUri(uriRaw, schemes)) return null;
      uri = uriRaw;
    } else if (schemes.isNotEmpty) {
      return null;
    }
    final pkgRaw = raw[IntentCardWire.package];
    final package =
        pkgRaw is String && IntentCardPolicy.packagePattern.hasMatch(pkgRaw)
        ? pkgRaw
        : null;
    if (action == 'launch' && package == null) return null;
    final fbRaw = raw[IntentCardWire.fallback];
    final fallback = fbRaw is String && _allowedUri(fbRaw, const ['https'])
        ? fbRaw
        : null;
    final extras = <String, Object>{};
    final extrasRaw = raw[IntentCardWire.extras];
    if (extrasRaw is Map) {
      for (final e in extrasRaw.entries) {
        final v = e.value;
        if (e.key is! String ||
            !IntentCardPolicy.extraKeys[action]!.contains(e.key)) {
          continue;
        }
        if (v is String || v is num || v is bool) {
          extras[e.key as String] = v as Object;
        }
      }
    }
    return CardIntent(
      action: action,
      uri: uri,
      package: package,
      fallback: fallback,
      chooser: raw[IntentCardWire.chooser] == true,
      extras: extras,
    );
  }

  static bool _allowedUri(String uri, List<String> schemes) {
    if (uri.length > 2000) return false;
    final u = Uri.tryParse(uri);
    if (u == null || !schemes.contains(u.scheme.toLowerCase())) return false;
    if (u.scheme.toLowerCase() == 'https') {
      return IntentCardPolicy.hosts.contains(u.host.toLowerCase()) &&
          u.userInfo.isEmpty;
    }
    return true;
  }

  /// The channel arguments: event times become epoch milliseconds in the
  /// phone's own time zone.
  Map<String, Object?> toChannel() {
    final x = Map<String, Object>.from(extras);
    final begin = x.remove(IntentCardWire.begin);
    final end = x.remove(IntentCardWire.end);
    if (begin is String) {
      final t = DateTime.tryParse(begin);
      if (t != null) x[IntentCardWire.beginMs] = t.millisecondsSinceEpoch;
    }
    if (end is String) {
      final t = DateTime.tryParse(end);
      if (t != null) x[IntentCardWire.endMs] = t.millisecondsSinceEpoch;
    }
    return {
      IntentCardWire.action: action,
      IntentCardWire.uri: ?uri,
      IntentCardWire.package: ?package,
      IntentCardWire.chooser: chooser,
      IntentCardWire.extras: x,
    };
  }
}

class CardButton {
  const CardButton({
    required this.id,
    required this.label,
    required this.app,
    required this.intent,
    this.primary = false,
    this.chip = false,
    this.group,
  });

  final String id;
  final String label;

  /// Names the logo (IntentCardIcons).
  final String app;
  final CardIntent intent;
  final bool primary;

  /// A small chip (timers), not a full button.
  final bool chip;

  /// Buttons of one group are alternatives (Amazon / Flipkart): installed first.
  final String? group;

  CardButton copyWith({bool? primary}) => CardButton(
    id: id,
    label: label,
    app: app,
    intent: intent,
    primary: primary ?? this.primary,
    chip: chip,
    group: group,
  );
}

/// A card parsed from a ```sparky-card block.
class IntentCardSpec {
  const IntentCardSpec({
    required this.type,
    required this.title,
    this.subtitle,
    this.rows = const [],
    this.notice,
    required this.actions,
  });

  final IntentCardType type;
  final String title;
  final String? subtitle;
  final List<(String, String)> rows;
  final String? notice;
  final List<CardButton> actions;

  /// Null when [source] is not a finished card (or holds nothing runnable).
  static IntentCardSpec? parse(String source) {
    final Object? json;
    try {
      json = jsonDecode(source.trim());
    } catch (_) {
      return null;
    }
    if (json is! Map) return null;
    final type = IntentCardType.byWire(json[IntentCardWire.type]);
    final title = _text(json[IntentCardWire.title]);
    if (type == null || title == null) return null;
    final buttons = <CardButton>[];
    final raw = json[IntentCardWire.actions];
    if (raw is List) {
      for (final a in raw) {
        if (a is! Map || buttons.length >= IntentCardPolicy.maxActions) {
          continue;
        }
        final intent = CardIntent.parse(a[IntentCardWire.intent]);
        final id = _text(a[IntentCardWire.id]);
        final label = _text(a[IntentCardWire.label]);
        if (intent == null || id == null || label == null) continue;
        buttons.add(
          CardButton(
            id: id,
            label: label,
            app: _text(a[IntentCardWire.app]) ?? '',
            intent: intent,
            primary: a[IntentCardWire.primary] == true,
            chip: a[IntentCardWire.chip] == true,
            group: _text(a[IntentCardWire.group]),
          ),
        );
      }
    }
    if (buttons.isEmpty) return null;
    final rows = <(String, String)>[];
    final rawRows = json[IntentCardWire.rows];
    if (rawRows is List) {
      for (final r in rawRows) {
        if (r is! Map || rows.length >= IntentCardPolicy.maxRows) continue;
        final k = _text(r[IntentCardWire.rowKey]);
        final v = _text(r[IntentCardWire.rowValue]);
        if (k != null && v != null) rows.add((k, v));
      }
    }
    return IntentCardSpec(
      type: type,
      title: title,
      subtitle: _text(json[IntentCardWire.subtitle]),
      rows: rows,
      notice: _text(json[IntentCardWire.notice]),
      actions: buttons,
    );
  }

  /// Buttons in the order shown: alternatives of one group with an installed
  /// app first (the first of them is then the primary), the rest unchanged.
  List<CardButton> ordered(Set<String> installedPackages) {
    final list = [...actions];
    final grouped = [
      for (final a in list)
        if (a.group != null) a,
    ];
    if (grouped.length < 2 || installedPackages.isEmpty) return list;
    bool has(CardButton b) =>
        b.intent.package != null &&
        installedPackages.contains(b.intent.package);
    final sorted = [...grouped.where(has), ...grouped.where((b) => !has(b))];
    final hadPrimary = grouped.any((b) => b.primary);
    final out = <CardButton>[];
    var i = 0;
    for (final a in list) {
      if (a.group == null) {
        out.add(a);
        continue;
      }
      out.add(sorted[i].copyWith(primary: hadPrimary && i == 0));
      i++;
    }
    return out;
  }

  static String? _text(Object? v) {
    if (v is! String) return null;
    final t = v.trim();
    return t.isEmpty
        ? null
        : t.length > IntentCardPolicy.maxText
        ? t.substring(0, IntentCardPolicy.maxText)
        : t;
  }
}
