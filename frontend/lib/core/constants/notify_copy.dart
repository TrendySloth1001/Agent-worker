/// Copy for the notification center: channels (what Android shows in the
/// system settings), notification text and the settings page.
abstract final class NotifyCopy {
  // Channel names and descriptions.
  static const replyChannel = 'Chat replies';
  static const replyChannelInfo =
      'Sent when a long reply finishes while you are away from the app.';
  static const replyProgressChannel = 'Chat reply progress';
  static const replyProgressChannelInfo =
      'Ongoing, silent notice while a long reply is still being written.';
  static const tableChannel = 'Round table finished';
  static const tableChannelInfo = 'Sent when a round table answer is ready.';
  static const tableProgressChannel = 'Round table progress';
  static const tableProgressChannelInfo =
      'Ongoing progress while a round table works in the background.';
  static const docChannel = 'Document finished';
  static const docChannelInfo = 'Sent when a document is ready.';
  static const docProgressChannel = 'Document progress';
  static const docProgressChannelInfo =
      'Ongoing progress while a document is being written.';
  static const fileChannel = 'Files and media';
  static const fileChannelInfo =
      'Sent when a large video, audio file or document finishes processing.';
  static const fileProgressChannel = 'Processing progress';
  static const fileProgressChannelInfo =
      'Ongoing, silent notice while files and sources are processed.';
  static const sourceChannel = 'Knowledge sources';
  static const sourceChannelInfo =
      'Sent when a website or GitHub source finishes (or fails) indexing.';
  static const reviewChannel = 'GitHub reviews';
  static const reviewChannelInfo =
      'Sent when a long AI pull request review is ready.';
  static const reviewProgressChannel = 'Review progress';
  static const reviewProgressChannelInfo =
      'Ongoing, silent notice while a pull request is being reviewed.';
  static const memoryChannel = 'Memory';
  static const memoryChannelInfo =
      'A quiet note when sparky remembers something new, with an undo.';
  static const usageChannel = 'Usage limits';
  static const usageChannelInfo = 'Sent when a daily limit is nearly used up.';
  static const githubChannel = 'GitHub connection';
  static const githubChannelInfo =
      'Sent when GitHub access expired and needs to be connected again.';
  static const resumeChannel = 'Reminders';
  static const resumeChannelInfo =
      'A gentle reminder about work you left unfinished.';
  static const reminderChannel = 'Your reminders';
  static const reminderChannelInfo =
      'Reminders you asked sparky to set (an action card you confirmed).';

  // Settings page: one switch per kind.
  static const replyLabel = 'Long replies';
  static const replyHelp = 'A reply that finished while you were away.';
  static const tableLabel = 'Tell me when a round table is done';
  static const tableHelp = 'A notification if you left the app meanwhile.';
  static const docLabel = 'Documents';
  static const docHelp = 'Ready, stopped or failed, and live progress.';
  static const fileLabel = 'Video, audio and files';
  static const fileHelp = 'Large uploads that finish processing.';
  static const sourceLabel = 'Knowledge sources';
  static const sourceHelp = 'Websites and GitHub repos that finish indexing.';
  static const reviewLabel = 'GitHub reviews';
  static const reviewHelp = 'A pull request review that is ready.';
  static const memoryLabel = 'Memory updates';
  static const memoryHelp = 'A quiet note when sparky remembers something.';
  static const usageLabel = 'Usage limit';
  static const usageHelp = 'When a daily limit is nearly reached.';
  static const githubLabel = 'GitHub connection';
  static const githubHelp = 'When GitHub needs to be connected again.';
  static const resumeLabel = 'Continue where you left off';
  static const resumeHelp = 'A reminder about an outline waiting for review.';
  static const reminderLabel = 'Reminders you ask for';
  static const reminderHelp =
      '"Remind me to…": the reminders you confirm in a chat.';
  static const reminderTitle = 'Reminder';

  // Settings page: sections and rows.
  static const masterLabel = 'Allow notifications';
  static const masterHelp = 'Turn all sparky notifications on or off.';
  static const secPermission = 'System permission';
  static const secKinds = 'What to tell me about';
  static const secQuiet = 'Quiet hours';
  static const permissionLabel = 'Android permission';
  static const permissionGranted = 'Allowed';
  static const permissionDenied = 'Not allowed';
  static const permissionUnavailable = 'Not available on this device';
  static const allow = 'Allow';
  static const quietLabel = 'Quiet hours';
  static const quietHelp = 'Notifications arrive without sound or vibration.';
  static const quietFrom = 'From';
  static const quietTo = 'Until';
  static const quietKicker = 'QUIET HOURS';
  static const quietSet = 'Set time';
  static const testLabel = 'Send a test notification';
  static const testHelp = 'Check how a notification looks and sounds.';
  static const testSent = 'Test notification sent.';
  static const testBlocked =
      'Notifications are off for this app. Allow them first.';
  static const testTitle = 'sparky';
  static const testBody = 'Notifications work. Tap to open the app.';
  static const keywords =
      'notify notification alert push sound vibrate quiet hours do not '
      'disturb permission test';

  // Actions.
  static const actionOpen = 'Open';
  static const actionUndo = 'Undo';

  // Notification text.
  static const groupTitle = 'sparky';
  static String groupSummary(int n) => '$n updates';

  static const replyTitle = 'Reply ready';
  static const replyProgressTitle = 'Writing a reply';
  static const replyProgressBody = 'Still writing. You can leave the app.';
  static const replyFailedTitle = 'Reply stopped';

  static const fileReadyTitle = 'File ready';
  static const fileFailedTitle = 'File could not be processed';
  static String fileReadyBody(String name) => '$name is ready to use.';
  static const fileProgressTitle = 'Processing files';
  static String fileProgressBody(int n) =>
      n == 1 ? 'Working on 1 item.' : 'Working on $n items.';

  static const sourceReadyTitle = 'Source indexed';
  static const sourceFailedTitle = 'Source failed';
  static String sourceReadyBody(String name, int docs) => docs > 0
      ? '$name: $docs ${docs == 1 ? 'page' : 'pages'} added.'
      : '$name is ready.';

  static const reviewProgressTitle = 'Reviewing pull request';
  static const reviewReadyTitle = 'Pull request review ready';
  static const reviewFailedTitle = 'Pull request review failed';
  static String reviewBody(String spec, String verdict) =>
      verdict.isEmpty ? spec : '$spec: $verdict';

  static const memoryTitle = 'sparky remembered';

  static const usageTitle = 'Daily limit nearly reached';
  static String usageBody(String provider, int percent) =>
      "$provider is at $percent% of today's limit.";

  static const githubTitle = 'GitHub needs to be connected';
  static const githubBody = 'Access expired. Tap to connect GitHub again.';

  static const resumeTitle = 'Continue where you left off';
  static String resumeBody(String title) =>
      'The outline for "$title" is waiting for your review.';
}

/// Ids, prefs keys and timings of the notification center.
abstract final class NotifyConfig {
  /// Android drawable for the status bar (res/drawable/ic_stat_table.xml).
  static const icon = 'ic_stat_table';

  /// First notification id; each kind owns [idSpan] ids from its base.
  static const idStart = 10000;
  static const idSpan = 1000;

  /// Group summaries, one per group.
  static const summaryBase = 8900;

  /// A group with more live notifications than this gets a summary.
  static const summaryAfter = 2;

  /// The test notification (outside every kind's range).
  static const testId = 8999;

  /// Characters of a notification body.
  static const bodyMax = 160;

  // Prefs.
  static const masterKey = 'notify_master';
  static const quietOnKey = 'notify_quiet_on';
  static const quietStartKey = 'notify_quiet_start';
  static const quietEndKey = 'notify_quiet_end';
  static const askedKey = 'notify_asked';
  static String kindKey(String key) => 'notify_kind_$key';
  static String lastKey(String key) => 'notify_last_$key';

  /// Default quiet window: 22:00 to 07:00 (minutes from midnight).
  static const defaultQuietStart = 22 * 60;
  static const defaultQuietEnd = 7 * 60;

  /// How long a streaming reply runs before a foreground service keeps it
  /// alive for a possible trip to the background.
  static const replyKeepAliveAfter = Duration(seconds: 6);

  /// A document outline waiting for review reminds after this long.
  static const resumeDelay = Duration(hours: 3);

  /// Background watch of file and source processing.
  static const watchInterval = Duration(seconds: 5);
  static const watchMaxAge = Duration(minutes: 45);
  static const watchServiceAfter = Duration(seconds: 8);

  /// Notifications for memories saved by one reply.
  static const memoryMax = 3;

  /// This much of a daily quota raises the usage notification.
  static const usageThreshold = 0.9;

  /// A permission request faster than this did not show a system dialog.
  static const dialogMin = Duration(milliseconds: 300);
}

abstract final class NotifySizes {
  /// Height of the time wheel in the quiet-hours sheet.
  static const timeWheel = 180.0;
}
