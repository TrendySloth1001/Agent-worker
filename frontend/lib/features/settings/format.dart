import '../../core/constants/app_sizes.dart';
import '../../core/constants/app_strings.dart';

/// Plain count, or a dash when unknown.
String count(int? v) => v == null ? AppStrings.dash : '$v';

/// Compact count for tight spaces: 1363 -> 1.4K.
String compact(int? v) {
  if (v == null) return AppStrings.dash;
  String one(double x, String suffix) {
    final s = x.toStringAsFixed(1);
    return '${s.endsWith('.0') ? s.substring(0, s.length - 2) : s}$suffix';
  }

  if (v >= AppUnits.million) {
    return one(v / AppUnits.million, AppStrings.millionSuffix);
  }
  if (v >= AppUnits.thousand) {
    return one(v / AppUnits.thousand, AppStrings.thousandSuffix);
  }
  return '$v';
}

/// Short span such as "5H" or "12M". Never negative.
String span(Duration d) {
  if (d.inDays >= 1) return '${d.inDays}${AppStrings.unitDay}';
  if (d.inHours >= 1) return '${d.inHours}${AppStrings.unitHour}';
  return '${d.inMinutes < 1 ? 1 : d.inMinutes}${AppStrings.unitMinute}';
}

/// "RESETS IN 5H", or "RESETS NOW" once the time has passed.
String resetsLabel(DateTime at, [DateTime? now]) {
  final d = at.difference(now ?? DateTime.now());
  if (d.isNegative) return AppStrings.resetsNow;
  return '${AppStrings.resetsIn} ${span(d)}';
}

/// "5H AGO".
String agoLabel(DateTime at, [DateTime? now]) {
  final d = (now ?? DateTime.now()).difference(at);
  return '${span(d.isNegative ? Duration.zero : d)} ${AppStrings.ago}';
}

/// Full count with thousands separators: 8000 -> 8,000.
String grouped(int? v) {
  if (v == null) return AppStrings.dash;
  final digits = v.abs().toString();
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) {
      out.write(AppStrings.groupSeparator);
    }
    out.write(digits[i]);
  }
  return '${v < 0 ? '-' : ''}$out';
}
