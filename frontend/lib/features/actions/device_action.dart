import 'dart:convert';

import '../../core/constants/device_actions.dart';
import '../../core/constants/app_icons.dart';
import '../../core/constants/media_apps.dart';

/// What a proposed action does on the phone.
enum DeviceActionType {
  alarm,
  timer,
  reminder,
  event,
  app,
  url,
  dial,
  sms,
  email,
  whatsapp,
  share,
  navigate;

  static DeviceActionType? byName(Object? raw) =>
      values.where((t) => t.name == raw).firstOrNull;

  /// Opens another app on Confirm (the overlay steps aside).
  bool get leaves => switch (this) {
    alarm || timer || reminder => false,
    _ => true,
  };
}

/// One action the model proposed in a ```sparky-action block, checked and
/// normalised. Built only through [parse]: an action that is missing what
/// it needs (a time, a number, a valid link) never becomes a card.
class DeviceAction {
  const DeviceAction._(this.type, this.fields, {this.when, this.until});

  final DeviceActionType type;

  /// The model's fields, trimmed, without empty ones.
  final Map<String, String> fields;

  /// Alarm time (today, only hour and minute count), reminder time, or
  /// event start.
  final DateTime? when;

  /// Event end.
  final DateTime? until;

  String? operator [](String key) => fields[key];

  /// Opens [url], in [app] when it is installed (the "Open in {app}" chips).
  factory DeviceAction.link(String url, {MediaApp? app}) =>
      DeviceAction._(DeviceActionType.url, {
        DeviceActionWire.url: url,
        if (app != null) DeviceActionWire.app: app.label,
        if (app != null) DeviceActionWire.package: app.package,
      });

  /// The media / shopping / maps app a url or app action is for, if known:
  /// by package, by the name the model wrote, else by the link's host.
  MediaApp? get mediaApp => switch (type) {
    DeviceActionType.url =>
      MediaApps.forPackage(fields[DeviceActionWire.package]) ??
          MediaApps.forName(fields[DeviceActionWire.app]) ??
          MediaApps.forUrl(fields[DeviceActionWire.url]!),
    DeviceActionType.app =>
      MediaApps.forPackage(fields[DeviceActionWire.package]) ??
          MediaApps.forName(fields[DeviceActionWire.name]),
    _ => null,
  };

  /// The same link with the app's package (opened in the app). Model
  /// actions name the app at most; the package comes from [mediaApp].
  DeviceAction inApp() {
    final app = mediaApp;
    if (app == null) return this;
    return DeviceAction._(type, {
      ...fields,
      DeviceActionWire.package: app.package,
    });
  }

  /// The same link without a package: Android opens it in the browser.
  DeviceAction inBrowser() => DeviceAction._(type, {
    for (final e in fields.entries)
      if (e.key != DeviceActionWire.package) e.key: e.value,
  });

  /// The app's store page ("Get the app"), or null when the app is unknown.
  DeviceAction? storePage() {
    final app = mediaApp;
    if (app == null) return null;
    return DeviceAction._(DeviceActionType.url, {
      DeviceActionWire.url: MediaAppWire.storePage(app.package),
      DeviceActionWire.store: app.package,
    });
  }

  bool get allDay => fields[DeviceActionWire.allDay] == 'true';

  int get seconds => int.tryParse(fields[DeviceActionWire.seconds] ?? '') ?? 0;

  static final _clock = RegExp(r'^(\d{1,2}):(\d{2})$');
  static final _phone = RegExp(r'^[+\d][\d\s().\-]{2,30}$');

  /// The action in [source] (the fenced block's JSON), or null when it is
  /// not one the phone can run.
  static DeviceAction? parse(String source) {
    Object? raw;
    try {
      raw = jsonDecode(source.trim());
    } catch (_) {
      return null;
    }
    if (raw is! Map) return null;
    final type = DeviceActionType.byName(raw[DeviceActionWire.type]);
    if (type == null) return null;
    final f = <String, String>{
      for (final e in raw.entries)
        if (e.key is String &&
            e.key != DeviceActionWire.type &&
            e.value != null &&
            '${e.value}'.trim().isNotEmpty)
          e.key as String: '${e.value}'.trim(),
    };
    bool has(String k) => f[k] != null;
    switch (type) {
      case DeviceActionType.alarm:
        final m = _clock.firstMatch(f[DeviceActionWire.time] ?? '');
        if (m == null) return null;
        final h = int.parse(m[1]!), min = int.parse(m[2]!);
        if (h > 23 || min > 59) return null;
        return DeviceAction._(type, f, when: DateTime(2000, 1, 1, h, min));
      case DeviceActionType.timer:
        final s = num.tryParse(f[DeviceActionWire.seconds] ?? '')?.round();
        if (s == null || s <= 0 || s > DeviceActionSizes.maxTimerSeconds) {
          return null;
        }
        return DeviceAction._(type, {...f, DeviceActionWire.seconds: '$s'});
      case DeviceActionType.reminder:
        final at = _time(f[DeviceActionWire.at]);
        if (!has(DeviceActionWire.text) || at == null) return null;
        return DeviceAction._(type, f, when: at);
      case DeviceActionType.event:
        final start = _time(f[DeviceActionWire.start]);
        if (!has(DeviceActionWire.title) || start == null) return null;
        final end = _time(f[DeviceActionWire.end]);
        return DeviceAction._(
          type,
          f,
          when: start,
          until: end != null && end.isAfter(start) ? end : null,
        );
      case DeviceActionType.app:
        return has(DeviceActionWire.name) ? DeviceAction._(type, f) : null;
      case DeviceActionType.url:
        final uri = Uri.tryParse(f[DeviceActionWire.url] ?? '');
        if (uri == null ||
            !(uri.scheme == 'https' || uri.scheme == 'http') ||
            uri.host.isEmpty) {
          return null;
        }
        return DeviceAction._(type, f);
      case DeviceActionType.dial:
        return _phone.hasMatch(f[DeviceActionWire.number] ?? '')
            ? DeviceAction._(type, f)
            : null;
      case DeviceActionType.sms:
        final number = f[DeviceActionWire.number];
        if (number != null && !_phone.hasMatch(number)) return null;
        return has(DeviceActionWire.body) || number != null
            ? DeviceAction._(type, f)
            : null;
      case DeviceActionType.email:
        return has(DeviceActionWire.to) ||
                has(DeviceActionWire.subject) ||
                has(DeviceActionWire.body)
            ? DeviceAction._(type, f)
            : null;
      case DeviceActionType.whatsapp:
      case DeviceActionType.share:
        return has(DeviceActionWire.text) ? DeviceAction._(type, f) : null;
      case DeviceActionType.navigate:
        return has(DeviceActionWire.destination)
            ? DeviceAction._(type, f)
            : null;
    }
  }

  /// A local date-time ("2026-10-14T09:00", a date alone is midnight). An
  /// offset, if the model added one, is converted to the phone's time.
  static DateTime? _time(String? raw) {
    if (raw == null) return null;
    final t = DateTime.tryParse(raw);
    if (t == null) return null;
    return t.isUtc ? t.toLocal() : t;
  }

  // ---- what the card shows -------------------------------------------------

  String get kicker => switch (type) {
    DeviceActionType.url ||
    DeviceActionType.app when mediaApp != null => MediaAppStrings.kicker,
    DeviceActionType.alarm => DeviceActionStrings.alarm,
    DeviceActionType.timer => DeviceActionStrings.timer,
    DeviceActionType.reminder => DeviceActionStrings.reminder,
    DeviceActionType.event => DeviceActionStrings.event,
    DeviceActionType.app => DeviceActionStrings.app,
    DeviceActionType.url => DeviceActionStrings.url,
    DeviceActionType.dial => DeviceActionStrings.dial,
    DeviceActionType.sms => DeviceActionStrings.sms,
    DeviceActionType.email => DeviceActionStrings.email,
    DeviceActionType.whatsapp => DeviceActionStrings.whatsapp,
    DeviceActionType.share => DeviceActionStrings.share,
    DeviceActionType.navigate => DeviceActionStrings.navigate,
  };

  AppIconData get icon => switch (type) {
    DeviceActionType.alarm => DeviceActionIcons.alarm,
    DeviceActionType.timer => DeviceActionIcons.timer,
    DeviceActionType.reminder => DeviceActionIcons.reminder,
    DeviceActionType.event => DeviceActionIcons.event,
    DeviceActionType.app => DeviceActionIcons.app,
    DeviceActionType.url => DeviceActionIcons.url,
    DeviceActionType.dial => DeviceActionIcons.dial,
    DeviceActionType.sms => DeviceActionIcons.sms,
    DeviceActionType.email => DeviceActionIcons.email,
    DeviceActionType.whatsapp => DeviceActionIcons.whatsapp,
    DeviceActionType.share => DeviceActionIcons.share,
    DeviceActionType.navigate => DeviceActionIcons.navigate,
  };

  String get title => switch (type) {
    DeviceActionType.url when mediaApp != null => MediaAppStrings.openIn(
      mediaApp!.label,
    ),
    DeviceActionType.alarm => DeviceActionStrings.alarmTitle(clock(when!)),
    DeviceActionType.timer => DeviceActionStrings.timerTitle(
      DeviceActionStrings.duration(seconds),
    ),
    DeviceActionType.reminder => fields[DeviceActionWire.text]!,
    DeviceActionType.event => fields[DeviceActionWire.title]!,
    DeviceActionType.app => DeviceActionStrings.appTitle(
      fields[DeviceActionWire.name]!,
    ),
    DeviceActionType.url => Uri.parse(fields[DeviceActionWire.url]!).host,
    DeviceActionType.dial => DeviceActionStrings.dialTitle(
      fields[DeviceActionWire.number]!,
    ),
    DeviceActionType.sms => DeviceActionStrings.smsTitle,
    DeviceActionType.email => DeviceActionStrings.emailTitle,
    DeviceActionType.whatsapp => DeviceActionStrings.whatsappTitle,
    DeviceActionType.share => DeviceActionStrings.shareTitle,
    DeviceActionType.navigate => DeviceActionStrings.navigateTitle(
      fields[DeviceActionWire.destination]!,
    ),
  };

  /// One line under the title (what Confirm really does), if any.
  String? get hint => switch (type) {
    DeviceActionType.dial => DeviceActionStrings.dialHint,
    DeviceActionType.sms ||
    DeviceActionType.email ||
    DeviceActionType.whatsapp => DeviceActionStrings.sendHint,
    _ => null,
  };

  /// Label / value rows of the card.
  List<(String, String)> get details {
    String? f(String k) => fields[k];
    return switch (type) {
      DeviceActionType.alarm || DeviceActionType.timer => [
        if (f(DeviceActionWire.label) case final l?)
          (DeviceActionStrings.labelLabel, l),
      ],
      DeviceActionType.reminder => [
        (DeviceActionStrings.whenLabel, describeWhen(when!)),
      ],
      DeviceActionType.event => [
        (
          DeviceActionStrings.startLabel,
          allDay
              ? '${day(when!)} · ${DeviceActionStrings.allDayValue}'
              : describeWhen(when!),
        ),
        if (until != null && !allDay)
          (DeviceActionStrings.endLabel, describeWhen(until!)),
        if (f(DeviceActionWire.location) case final l?)
          (DeviceActionStrings.whereLabel, l),
        if (f(DeviceActionWire.notes) case final n?)
          (DeviceActionStrings.notesLabel, n),
      ],
      DeviceActionType.url => [
        (DeviceActionStrings.linkLabel, f(DeviceActionWire.url)!),
      ],
      DeviceActionType.sms || DeviceActionType.whatsapp => [
        if (f(DeviceActionWire.number) case final n?)
          (DeviceActionStrings.toLabel, n),
        if (f(DeviceActionWire.body) ?? f(DeviceActionWire.text) case final m?)
          (DeviceActionStrings.messageLabel, m),
      ],
      DeviceActionType.email => [
        if (f(DeviceActionWire.to) case final t?)
          (DeviceActionStrings.toLabel, t),
        if (f(DeviceActionWire.subject) case final s?)
          (DeviceActionStrings.subjectLabel, s),
        if (f(DeviceActionWire.body) case final b?)
          (DeviceActionStrings.messageLabel, b),
      ],
      DeviceActionType.share => [
        (DeviceActionStrings.messageLabel, f(DeviceActionWire.text)!),
      ],
      DeviceActionType.navigate => [
        if (f(DeviceActionWire.travel) case final t?)
          (DeviceActionStrings.travelLabel, t),
      ],
      DeviceActionType.app || DeviceActionType.dial => const [],
    };
  }

  /// What the card says after Confirm worked.
  String get doneLabel => switch (type) {
    DeviceActionType.alarm => DeviceActionStrings.alarmDone,
    DeviceActionType.timer => DeviceActionStrings.timerDone,
    DeviceActionType.reminder => DeviceActionStrings.reminderDone,
    _ => DeviceActionStrings.opened,
  };

  /// The arguments of DeviceActions.kt `run` (reminders stay in Dart).
  Map<String, Object?> toChannel() {
    String? f(String k) => fields[k];
    return {
      DeviceActionWire.type: type.name,
      ...switch (type) {
        DeviceActionType.alarm => {
          DeviceActionWire.hour: when!.hour,
          DeviceActionWire.minute: when!.minute,
          DeviceActionWire.label: f(DeviceActionWire.label),
        },
        DeviceActionType.timer => {
          DeviceActionWire.seconds: seconds,
          DeviceActionWire.label: f(DeviceActionWire.label),
        },
        DeviceActionType.event => {
          DeviceActionWire.title: f(DeviceActionWire.title),
          DeviceActionWire.beginMs: when!.millisecondsSinceEpoch,
          DeviceActionWire.endMs: until?.millisecondsSinceEpoch,
          DeviceActionWire.allDay: allDay,
          DeviceActionWire.location: f(DeviceActionWire.location),
          DeviceActionWire.notes: f(DeviceActionWire.notes),
        },
        DeviceActionType.whatsapp => {
          DeviceActionWire.number: f(DeviceActionWire.number),
          DeviceActionWire.text: f(DeviceActionWire.text),
        },
        _ => fields,
      },
    };
  }

  /// A stable key for the card's remembered outcome.
  String get key => '${type.name}:${jsonEncode(fields)}';
}

// ---- formatting --------------------------------------------------------------

String _two(int n) => n.toString().padLeft(2, '0');

/// 24-hour clock, like the rest of the Nothing UI: "07:30".
String clock(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

/// "Tue 14 Oct".
String day(DateTime t) =>
    '${DeviceActionDates.weekdays[t.weekday - 1]} ${t.day} '
    '${DeviceActionDates.months[t.month - 1]}';

/// "Tue 14 Oct, 15:00"; a year only when it is not this one.
String describeWhen(DateTime t, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final year = t.year == n.year ? '' : ' ${t.year}';
  return '${day(t)}$year, ${clock(t)}';
}
