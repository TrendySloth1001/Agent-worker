/// User-set window with no sound or vibration, as minutes from midnight.
/// It may cross midnight (22:00 to 07:00).
class QuietHours {
  const QuietHours({
    required this.enabled,
    required this.startMinute,
    required this.endMinute,
  });

  final bool enabled;
  final int startMinute, endMinute;

  /// Whether [t] falls inside the window. Equal start and end is an empty
  /// window, not the whole day.
  bool contains(DateTime t) {
    if (!enabled || startMinute == endMinute) return false;
    final m = t.hour * 60 + t.minute;
    return startMinute < endMinute
        ? m >= startMinute && m < endMinute
        : m >= startMinute || m < endMinute;
  }

  static String format(int minute) {
    final h = (minute ~/ 60) % 24;
    final m = minute % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }
}

enum NotifyDecision {
  /// Nothing is shown.
  skip,

  /// Shown normally.
  post,

  /// Shown without sound or vibration (quiet hours).
  postQuiet,
}

/// The one place that decides whether a notification may be posted.
abstract final class NotifyPolicy {
  /// [force] is the user asking for this one ("notify me"): it passes the
  /// per-kind switch, the background rule and the "looking at it" rule, but
  /// never the master switch.
  static NotifyDecision decide({
    required bool masterOn,
    required bool kindOn,
    required bool backgroundOnly,
    required bool appInBackground,
    required bool quiet,
    bool lookingAt = false,
    bool force = false,
  }) {
    if (!masterOn) return NotifyDecision.skip;
    if (!force) {
      if (!kindOn) return NotifyDecision.skip;
      if (backgroundOnly && !appInBackground) return NotifyDecision.skip;
      // Looking at the very thing it is about: the screen says it already.
      if (lookingAt && !appInBackground) return NotifyDecision.skip;
    }
    return quiet ? NotifyDecision.postQuiet : NotifyDecision.post;
  }

  /// Whether a repeating alert fired too recently to fire again.
  static bool tooSoon(DateTime? last, DateTime now, Duration gap) =>
      last != null && gap > Duration.zero && now.difference(last) < gap;
}
