/// System notification ids, channels and icon.
abstract final class NotifyConfig {
  /// Android drawable for the status bar (res/drawable/ic_stat_table.xml).
  static const icon = 'ic_stat_table';
  static const progressChannel = 'round_table_progress';
  static const doneChannel = 'round_table_done';

  /// The ongoing progress notification; the finished one replaces it.
  static const tableId = 7100;
}
