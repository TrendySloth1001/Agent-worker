import '../../core/constants/app_strings.dart';
import '../../core/constants/history.dart';
import '../../data/conversation.dart';

/// One labelled run of chats in the sidebar.
class HistoryGroup {
  const HistoryGroup(this.label, this.items, {this.isPinned = false});

  final String label;
  final List<ConversationSummary> items;
  final bool isPinned;
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Label of the bucket an unpinned chat last touched at [at] falls in, seen
/// from [now]: today, yesterday, the last 7 and 30 days, then its month.
String historyBucket(DateTime at, DateTime now) {
  final days = _day(now).difference(_day(at)).inDays;
  if (days <= 0) return HistoryStrings.today;
  if (days == 1) return HistoryStrings.yesterday;
  if (days <= 7) return HistoryStrings.previous7;
  if (days <= 30) return HistoryStrings.previous30;
  final month = HistoryStrings.months[at.month - 1];
  return at.year == now.year ? month : '$month ${at.year}';
}

/// Splits [items] (server order: pinned first, then newest first) into
/// groups. Pinned chats form one group; the rest follow their buckets in the
/// order they first appear.
List<HistoryGroup> groupConversations(
  List<ConversationSummary> items,
  DateTime now,
) {
  final pinned = [
    for (final c in items)
      if (c.pinned) c,
  ];
  final buckets = <String, List<ConversationSummary>>{};
  for (final c in items) {
    if (c.pinned) continue;
    buckets.putIfAbsent(historyBucket(c.updatedAt, now), () => []).add(c);
  }
  return [
    if (pinned.isNotEmpty)
      HistoryGroup(HistoryStrings.pinned, pinned, isPinned: true),
    for (final e in buckets.entries) HistoryGroup(e.key, e.value),
  ];
}

/// Short relative time for rows that show one: 5m, 3h, 2d, then a date.
String historyTime(DateTime at, DateTime now) {
  final diff = now.difference(at);
  if (diff.inMinutes < 1) return HistoryStrings.justNow;
  if (diff.inHours < 1) return '${diff.inMinutes}m';
  if (diff.inDays < 1) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  final month = AppStrings.months[at.month - 1];
  return at.year == now.year
      ? '${at.day} $month'
      : '${at.day} $month ${at.year}';
}
