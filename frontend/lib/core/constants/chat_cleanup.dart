import 'package:hugeicons/hugeicons.dart';

import 'app_icons.dart';

/// Selecting chats in the sidebar and deleting them, one by one or all.
abstract final class ChatCleanupStrings {
  // Sidebar selection mode
  static const select = 'Select';
  static const exitSelection = 'Exit selection';
  static String selected(int n) => '$n selected';
  static const selectAll = 'Select all';
  static const selectNone = 'Select none';
  static const loadingAll = 'Loading all chats';
  static const archive = 'Archive';
  static const restore = 'Restore';
  static const pin = 'Pin';
  static const unpin = 'Unpin';
  static const delete = 'Delete';
  static const checked = 'Selected';
  static const unchecked = 'Not selected';

  // Confirm and result
  static String deleteTitle(int n) =>
      n == 1 ? 'Delete 1 chat?' : 'Delete $n chats?';
  static const deleteBody =
      "This also deletes files attached in them. This can't be undone.";
  static const cancel = 'Cancel';
  static String deleted(int n) =>
      n == 1 ? '1 chat deleted' : '$n chats deleted';
  static String archived(int n) =>
      n == 1 ? '1 chat archived' : '$n chats archived';
  static String restored(int n) =>
      n == 1 ? '1 chat restored' : '$n chats restored';
  static const deleteFailed = 'Could not delete the chats. Try again.';
  static const actionFailed = 'Some chats could not be updated.';

  // Settings: delete all chats
  static const section = 'Chats';
  static const deleteAll = 'Delete all chats';
  static const deleteAllHelp = 'Every chat and the files attached in them';
  static const deleteAllKeywords =
      'delete remove erase clear wipe all chats conversations history';
  static const deleteAllTitle = 'Delete all chats?';
  static const deleteAllBody =
      "Every chat, its messages and the files attached in it are deleted "
      "from the server. This can't be undone.";
  static const includeArchived = 'Also delete archived chats';
  static const keepPinned = 'Keep pinned chats';
  static const confirmWord = 'DELETE';
  static const typeToConfirm = 'Type DELETE to confirm';
  static const deleting = 'Deleting chats';
  static const deleteAllFailed = 'Could not delete your chats. Try again.';
  static String deletedAll(int n) => n == 0
      ? 'There were no chats to delete'
      : n == 1
      ? '1 chat deleted'
      : '$n chats deleted';
}

abstract final class ChatCleanupSizes {
  /// The round check on a row in selection mode.
  static const check = 22.0;
  static const checkIcon = 14.0;
  static const checkStroke = 1.5;

  /// Header in selection mode: the count row and the action row.
  static const barHeight = 56.0;
  static const actionHeight = 40.0;
  static const actionGap = 8.0;

  /// Confirm button in a dialog (hugs its label).
  static const dialogAction = 40.0;

  /// Progress ring in the delete-all dialog.
  static const progress = 20.0;
  static const progressStroke = 2.0;

  /// Concurrent requests for archiving or pinning a selection.
  static const parallel = 6;

  /// "Select all" loads remaining pages, at most this many.
  static const maxPages = 100;
}

abstract final class ChatCleanupIcons {
  static const select = HugeIcons.strokeRoundedCheckmarkCircle02;
  static const check = AppIcons.check;
  static const close = AppIcons.close;
  static const selectAll = HugeIcons.strokeRoundedCheckList;
  static const archive = AppIcons.archive;
  static const restore = AppIcons.unarchive;
  static const pin = AppIcons.pin;
  static const unpin = AppIcons.unpin;
  static const delete = AppIcons.delete;
}

abstract final class ChatCleanupDurations {
  static const check = Duration(milliseconds: 150);
}
