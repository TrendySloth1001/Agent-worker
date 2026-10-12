/// System notification ids, channels and icon.
abstract final class NotifyConfig {
  /// Android drawable for the status bar (res/drawable/ic_stat_table.xml).
  static const icon = 'ic_stat_table';
  static const progressChannel = 'round_table_progress';
  static const doneChannel = 'round_table_done';

  /// The ongoing progress notification; the finished one replaces it.
  static const tableId = 7100;

  // Documents (DOC mode). One document is written at a time, so one
  // progress id; each finished document gets its own id so several stay.
  static const docProgressChannel = 'doc_progress';
  static const docDoneChannel = 'doc_done';
  static const docProgressId = 7200;
  static const docDoneBase = 7300;
  static const docDoneMask = 0xff;

  /// Notification payload prefix that marks a document id.
  static const docPayload = 'doc:';
}
