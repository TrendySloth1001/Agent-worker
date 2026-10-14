import 'package:hugeicons/hugeicons.dart';

import 'app_icons.dart';

/// In-house crash and error reporting: limits, preference keys, copy, icons
/// and sizes for the reporter, Settings → Privacy and the owner's Errors screen.

abstract final class ErrorsConfig {
  /// Breadcrumb ring buffer.
  static const breadcrumbs = 30;

  /// At most this many distinct errors are recorded per session.
  static const maxDistinctPerSession = 10;

  /// The same error is recorded at most once per this interval.
  static const sameErrorEvery = Duration(seconds: 60);

  /// Offline queue: entries, bytes (of the JSON), and age before dropping.
  static const queueMaxEntries = 50;
  static const queueMaxBytes = 200 * 1024;
  static const queueMaxAge = Duration(days: 7);

  /// Server batch limits.
  static const errorBatch = 10;
  static const sessionBatch = 20;

  /// Field limits (the server truncates to the same numbers).
  static const maxMessage = 200;
  static const maxStack = 8 * 1024;
  static const maxType = 80;
  static const maxRouteName = 40;

  /// Waiting after a record before the queue is sent, so a burst goes in one batch.
  static const flushDelay = Duration(seconds: 5);
  static const requestTimeout = Duration(seconds: 15);

  static const diagnosticsChannel = 'sparky/diagnostics';

  /// Flutter's `--split-per-abi` adds this to the version code (arm64); same as [UpdateConfig.abiOffset].
  static const abiOffset = 2000;
}

abstract final class ErrorsPrefs {
  static const sendReports = 'errors.sendReports';
  static const errorQueue = 'errors.queue';
  static const assistErrorQueue = 'errors.queue.assist';
  static const sessionQueue = 'errors.sessions';
  static const currentSession = 'errors.currentSession';
}

/// Breadcrumb categories (the server stores them as short strings).
enum CrumbKind { route, update, net, lifecycle, memory }

abstract final class ErrorsStrings {
  static const sendReportsTitle = 'Send crash reports';
  static const sendReportsHelp =
      'Sends a short technical report when sparky crashes. Never your chats, '
      'files or anything you type.';
  static const sendReportsOwner = 'Always on for the owner account.';
  static const sectionTitle = 'Diagnostics';
  static const sendReportsKeywords =
      'crash reports errors diagnostics bugs privacy send';

  // Owner screen.
  static const screenTitle = 'Crashes & errors';
  static const entryTitle = 'Crashes & errors';
  static const entrySummary = 'Error groups, crash-free sessions';
  static const buildHeader = 'Crash-free sessions';
  static const groupsHeader = 'Error groups';
  static const buildPickerLabel = 'Build';
  static const allBuilds = 'All builds';
  static const emptyTitle = 'No errors';
  static const emptyHint = 'Nothing has been reported for this build.';
  static const noSessions = 'No sessions yet';
  static const loadFailed = 'Could not load reports';
  static const retry = 'Try again';

  static const statusOpen = 'Open';
  static const statusResolved = 'Resolved';
  static const statusIgnored = 'Ignored';
  static const filterAll = 'All';

  static const resolve = 'Resolve';
  static const ignore = 'Ignore';
  static const reopen = 'Reopen';
  static const updated = 'Updated';
  static const actionFailed = 'That did not work. Try again.';

  static const samplesHeader = 'Samples';
  static const buildsHeader = 'By build';
  static const breadcrumbsHeader = 'Before the error';
  static const stackHeader = 'Stack';
  static const deviceHeader = 'Device';
  static const noSamples = 'No sample kept for this group yet.';
  static const symbolizeHeader = 'Symbolize';
  static const copyCommand = 'Copy command';
  static const copied = 'Copied';
  static const showUser = 'Show user';
  static const userHidden = 'User hidden';
  static const noEmail = 'No e-mail on record';

  static String symbolize(String fingerprint) =>
      'scripts/symbolize.sh $fingerprint';

  static String users(int n) => n == 1 ? '1 user' : '$n users';
  static String events(int n) => n == 1 ? '1 event' : '$n events';
  static String sessions(int n) => n == 1 ? '1 session' : '$n sessions';
  static String buildLabel(int b) => 'Build $b';
  static String buildRange(int a, int b) =>
      a == b ? 'Build $a' : 'Builds $a to $b';
  static String crashFree(double rate) {
    final pct = rate * 100;
    final text = pct >= 99.995 ? '100' : pct.toStringAsFixed(2);
    return '$text%';
  }

  static String crashed(int n) => '$n crashed';
}

abstract final class ErrorsIcons {
  static const entry = HugeIcons.strokeRoundedBug01;
  static const sendReports = HugeIcons.strokeRoundedBug02;
  static const open = HugeIcons.strokeRoundedAlertDiamond;
  static const resolved = HugeIcons.strokeRoundedCheckmarkCircle02;
  static const ignored = HugeIcons.strokeRoundedBlocked;
  static const users = HugeIcons.strokeRoundedUserMultiple;
  static const device = HugeIcons.strokeRoundedSmartPhone01;
  static const health = HugeIcons.strokeRoundedActivity01;
  static const copy = AppIcons.copy;
  static const chevron = AppIcons.chevronRight;
}

abstract final class ErrorsSizes {
  static const stackMaxLines = 14;
  static const titleMaxLines = 3;
  static const sampleSpacing = 12.0;
  static const barHeight = 6.0;
  static const rateWidth = 72.0;
  static const chipGap = 8.0;
  static const monoSize = 12.0;
  static const listLimit = 100;
}
