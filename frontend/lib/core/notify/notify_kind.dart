import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    show Importance;

import '../constants/notify_copy.dart';
import '../constants/update.dart';

/// One Android notification channel: what the system settings list.
class NotifyChannel {
  const NotifyChannel({
    required this.id,
    required this.name,
    required this.description,
    this.importance = Importance.defaultImportance,
    this.sound = true,
    this.vibrate = true,
  });

  final String id, name, description;
  final Importance importance;
  final bool sound, vibrate;
}

/// Notifications that stack together; more than two get a summary.
enum NotifyGroup {
  chat('sparky.chat'),
  docs('sparky.docs'),
  library('sparky.library'),
  account('sparky.account');

  const NotifyGroup(this.key);
  final String key;

  int get summaryId => NotifyConfig.summaryBase + index;
}

/// Buttons a notification can carry. [open] is also a plain tap.
enum NotifyAction {
  open('open', NotifyCopy.actionOpen),
  undo('undo', NotifyCopy.actionUndo);

  const NotifyAction(this.id, this.label);
  final String id, label;

  static NotifyAction? byId(String? id) =>
      values.where((a) => a.id == id).firstOrNull;
}

/// Everything sparky can notify about. Each kind has its own channel (and a
/// progress channel when it runs long), a user switch, an id range and a
/// group. Add a kind here and it appears in Settings automatically.
enum NotifyKind {
  reply(
    key: 'reply',
    label: NotifyCopy.replyLabel,
    help: NotifyCopy.replyHelp,
    group: NotifyGroup.chat,
    channel: NotifyChannel(
      id: 'chat_reply_done',
      name: NotifyCopy.replyChannel,
      description: NotifyCopy.replyChannelInfo,
      importance: Importance.high,
    ),
    progress: NotifyChannel(
      id: 'chat_reply_progress',
      name: NotifyCopy.replyProgressChannel,
      description: NotifyCopy.replyProgressChannelInfo,
      importance: Importance.low,
      sound: false,
      vibrate: false,
    ),
    backgroundOnly: true,
    actions: [NotifyAction.open],
  ),
  roundTable(
    key: 'round_table',
    label: NotifyCopy.tableLabel,
    help: NotifyCopy.tableHelp,
    group: NotifyGroup.chat,
    // Same ids as before the center existed, so existing installs keep
    // their channel settings.
    channel: NotifyChannel(
      id: 'round_table_done',
      name: NotifyCopy.tableChannel,
      description: NotifyCopy.tableChannelInfo,
      importance: Importance.high,
    ),
    progress: NotifyChannel(
      id: 'round_table_progress',
      name: NotifyCopy.tableProgressChannel,
      description: NotifyCopy.tableProgressChannelInfo,
      importance: Importance.low,
      sound: false,
      vibrate: false,
    ),
    prefKey: 'notify_round_table',
  ),
  doc(
    key: 'doc',
    label: NotifyCopy.docLabel,
    help: NotifyCopy.docHelp,
    group: NotifyGroup.docs,
    channel: NotifyChannel(
      id: 'doc_done',
      name: NotifyCopy.docChannel,
      description: NotifyCopy.docChannelInfo,
      importance: Importance.high,
    ),
    progress: NotifyChannel(
      id: 'doc_progress',
      name: NotifyCopy.docProgressChannel,
      description: NotifyCopy.docProgressChannelInfo,
      importance: Importance.low,
      sound: false,
      vibrate: false,
    ),
    actions: [NotifyAction.open],
  ),
  file(
    key: 'file',
    label: NotifyCopy.fileLabel,
    help: NotifyCopy.fileHelp,
    group: NotifyGroup.library,
    channel: NotifyChannel(
      id: 'file_done',
      name: NotifyCopy.fileChannel,
      description: NotifyCopy.fileChannelInfo,
    ),
    progress: NotifyChannel(
      id: 'file_progress',
      name: NotifyCopy.fileProgressChannel,
      description: NotifyCopy.fileProgressChannelInfo,
      importance: Importance.low,
      sound: false,
      vibrate: false,
    ),
    backgroundOnly: true,
    actions: [NotifyAction.open],
  ),
  source(
    key: 'source',
    label: NotifyCopy.sourceLabel,
    help: NotifyCopy.sourceHelp,
    group: NotifyGroup.library,
    channel: NotifyChannel(
      id: 'source_done',
      name: NotifyCopy.sourceChannel,
      description: NotifyCopy.sourceChannelInfo,
    ),
    backgroundOnly: true,
  ),
  prReview(
    key: 'pr_review',
    label: NotifyCopy.reviewLabel,
    help: NotifyCopy.reviewHelp,
    group: NotifyGroup.chat,
    channel: NotifyChannel(
      id: 'pr_review_done',
      name: NotifyCopy.reviewChannel,
      description: NotifyCopy.reviewChannelInfo,
      importance: Importance.high,
    ),
    progress: NotifyChannel(
      id: 'pr_review_progress',
      name: NotifyCopy.reviewProgressChannel,
      description: NotifyCopy.reviewProgressChannelInfo,
      importance: Importance.low,
      sound: false,
      vibrate: false,
    ),
    backgroundOnly: true,
    actions: [NotifyAction.open],
  ),
  memory(
    key: 'memory',
    label: NotifyCopy.memoryLabel,
    help: NotifyCopy.memoryHelp,
    group: NotifyGroup.account,
    channel: NotifyChannel(
      id: 'memory_saved',
      name: NotifyCopy.memoryChannel,
      description: NotifyCopy.memoryChannelInfo,
      importance: Importance.low,
      sound: false,
      vibrate: false,
    ),
    defaultOn: false,
    backgroundOnly: true,
    actions: [NotifyAction.undo],
  ),
  usage(
    key: 'usage',
    label: NotifyCopy.usageLabel,
    help: NotifyCopy.usageHelp,
    group: NotifyGroup.account,
    channel: NotifyChannel(
      id: 'usage_limit',
      name: NotifyCopy.usageChannel,
      description: NotifyCopy.usageChannelInfo,
    ),
    minGap: Duration(hours: 12),
  ),
  github(
    key: 'github',
    label: NotifyCopy.githubLabel,
    help: NotifyCopy.githubHelp,
    group: NotifyGroup.account,
    channel: NotifyChannel(
      id: 'github_reconnect',
      name: NotifyCopy.githubChannel,
      description: NotifyCopy.githubChannelInfo,
    ),
    minGap: Duration(hours: 24),
  ),
  resume(
    key: 'resume',
    label: NotifyCopy.resumeLabel,
    help: NotifyCopy.resumeHelp,
    group: NotifyGroup.docs,
    channel: NotifyChannel(
      id: 'resume_reminder',
      name: NotifyCopy.resumeChannel,
      description: NotifyCopy.resumeChannelInfo,
      importance: Importance.low,
      sound: false,
      vibrate: false,
    ),
    defaultOn: false,
  ),

  /// "Remind me to…" from a confirmed action card (chat or overlay).
  reminder(
    key: 'reminder',
    label: NotifyCopy.reminderLabel,
    help: NotifyCopy.reminderHelp,
    group: NotifyGroup.chat,
    channel: NotifyChannel(
      id: 'assistant_reminder',
      name: NotifyCopy.reminderChannel,
      description: NotifyCopy.reminderChannelInfo,
      importance: Importance.high,
    ),
  ),

  /// "A new sparky is ready": once per version, quietly.
  appUpdate(
    key: 'app_update',
    label: UpdateStrings.notifyLabel,
    help: UpdateStrings.notifyHelp,
    group: NotifyGroup.account,
    channel: NotifyChannel(
      id: 'app_update',
      name: UpdateStrings.channelName,
      description: UpdateStrings.channelInfo,
      importance: Importance.low,
      sound: false,
      vibrate: false,
    ),
  );

  const NotifyKind({
    required this.key,
    required this.label,
    required this.help,
    required this.group,
    required this.channel,
    this.progress,
    this.defaultOn = true,
    this.backgroundOnly = false,
    this.minGap = Duration.zero,
    this.actions = const [],
    String? prefKey,
  }) : _prefKey = prefKey;

  /// Short stable name (prefs, logs).
  final String key;

  /// Settings row title and description.
  final String label, help;

  final NotifyGroup group;
  final NotifyChannel channel;

  /// Channel of the ongoing progress notification, when the work runs long.
  final NotifyChannel? progress;

  final bool defaultOn;

  /// Nothing is posted while the user has the app open (they see it there).
  final bool backgroundOnly;

  /// Smallest time between two posts of this kind (for repeating alerts).
  final Duration minGap;

  /// Extra buttons besides the tap.
  final List<NotifyAction> actions;

  final String? _prefKey;

  /// SharedPreferences key of the user's switch. The round table keeps the
  /// key it always had.
  String get prefKey => _prefKey ?? NotifyConfig.kindKey(key);

  /// First id of this kind's range; the slot at the base is the progress
  /// notification, the rest are done / failed ones.
  int get idBase => NotifyConfig.idStart + index * NotifyConfig.idSpan;

  int get progressId => idBase;

  /// Id of the notification for [item] (a chat, doc or file id): the same
  /// item always maps to the same id, so a repeat replaces instead of
  /// stacking, and ids of different kinds never meet.
  int idFor(String item) =>
      idBase + 1 + stableHash(item) % (NotifyConfig.idSpan - 1);

  /// Every channel this kind uses.
  List<NotifyChannel> get channels => [channel, ?progress];

  /// FNV-1a: String.hashCode changes between runs, which would turn one
  /// document into a new notification after every restart.
  static int stableHash(String s) {
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0x7fffffff;
    }
    return h;
  }
}
