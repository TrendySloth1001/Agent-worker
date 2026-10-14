import 'package:shared_preferences/shared_preferences.dart';

import '../constants/errors.dart';

/// The "Send crash reports" choice (Settings → Privacy). On by default; the owner's
/// reports are always sent, whatever the switch says.
class ErrorSettings {
  ErrorSettings._();

  /// What the switch shows and what is sent: the owner is always on.
  static bool effective(SharedPreferences p, {required bool isOwner}) =>
      isOwner || (p.getBool(ErrorsPrefs.sendReports) ?? true);

  static bool stored(SharedPreferences p) =>
      p.getBool(ErrorsPrefs.sendReports) ?? true;

  static Future<void> set(SharedPreferences p, bool on) =>
      p.setBool(ErrorsPrefs.sendReports, on);
}
