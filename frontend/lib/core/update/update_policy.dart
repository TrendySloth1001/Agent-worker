import '../constants/update.dart';
import 'update_models.dart';

/// What the app does about an available update.
enum UpdatePrompt {
  /// Up to date.
  none,

  /// Only a dot on Settings → About.
  dot,

  /// The bottom sheet may show at the next calm moment.
  sheet,

  /// Full-screen "update to continue".
  blocking,
}

/// What is remembered about prompting for one version.
class PromptState {
  const PromptState({
    this.promptedBuild,
    this.promptCount = 0,
    this.nextPromptAt,
  });

  /// The build the sheet was last shown for.
  final int? promptedBuild;

  /// Times the sheet was shown for [promptedBuild] (0..maxPrompts).
  final int promptCount;

  /// When "Later" lets the sheet come back; null means never again.
  final DateTime? nextPromptAt;

  static const fresh = PromptState();
}

/// The rules, pure: no clock, storage or platform in here.
abstract final class UpdatePolicy {
  /// The prompt for [info] given what was shown before, at [now].
  ///
  /// - nothing newer: none;
  /// - critical, or this build is below the minimum: blocking;
  /// - patch: dot only;
  /// - feature / major: the sheet once per version, then again after 3 days,
  ///   then after 7 more, then never (dot only).
  static UpdatePrompt decide(UpdateInfo info, PromptState state, DateTime now) {
    final latest = info.latest;
    if (latest == null) return UpdatePrompt.none;
    if (info.required || latest.kind == UpdateKind.critical) {
      return UpdatePrompt.blocking;
    }
    if (!latest.kind.promptsSheet) return UpdatePrompt.dot;
    // A version never prompted before.
    if (state.promptedBuild != latest.build) return UpdatePrompt.sheet;
    if (state.promptCount >= UpdateConfig.maxPrompts) return UpdatePrompt.dot;
    final next = state.nextPromptAt;
    if (next == null) return UpdatePrompt.dot;
    return now.isBefore(next) ? UpdatePrompt.dot : UpdatePrompt.sheet;
  }

  /// The state after the sheet was shown for [build] at [now].
  static PromptState afterShown(PromptState s, int build, DateTime now) {
    final count = s.promptedBuild == build ? s.promptCount + 1 : 1;
    final Duration? wait = switch (count) {
      1 => UpdateConfig.firstReminder,
      2 => UpdateConfig.secondReminder,
      _ => null,
    };
    return PromptState(
      promptedBuild: build,
      promptCount: count,
      nextPromptAt: wait == null ? null : now.add(wait),
    );
  }

  /// One local notification per version, for kinds that prompt the sheet.
  static bool shouldNotify(UpdateInfo info, int? notifiedBuild) {
    final latest = info.latest;
    if (latest == null || !latest.kind.promptsSheet) return false;
    if (info.required) return false;
    return notifiedBuild != latest.build;
  }

  /// Patches download in the background, on Wi-Fi only (or anywhere when the
  /// user turned the Wi-Fi switch off).
  static bool shouldAutoDownload(
    UpdateInfo info, {
    required bool onWifi,
    required bool wifiOnly,
    required bool haveIt,
  }) {
    final latest = info.latest;
    if (latest == null || latest.kind != UpdateKind.patch) return false;
    if (haveIt || latest.url.isEmpty) return false;
    return onWifi || !wifiOnly;
  }

  /// Whether the periodic check is due on resume.
  static bool checkDue(DateTime? last, DateTime now) =>
      last == null || now.difference(last) > UpdateConfig.resumeAfter;

  /// The server's build number from the installed version code: split-per-abi
  /// builds add [UpdateConfig.abiOffset] (arm64 = 2000 + N).
  static int buildFromVersionCode(int code) =>
      code >= UpdateConfig.abiOffset ? code - UpdateConfig.abiOffset : code;
}
