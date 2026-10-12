import 'constants/app_strings.dart';

/// Human relative time: "just now", "5 min ago", "2h ago", "3d ago", then a
/// short date. Lower case, for secondary text.
String timeAgo(DateTime at, DateTime now) {
  final diff = now.difference(at);
  if (diff.inMinutes < 1) return TimeAgoStrings.justNow;
  if (diff.inHours < 1) return '${diff.inMinutes} min ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  final month = AppStrings.months[at.month - 1].toLowerCase();
  final date = '${at.day} $month';
  return at.year == now.year ? date : '$date ${at.year}';
}

abstract final class TimeAgoStrings {
  static const justNow = 'just now';
}
