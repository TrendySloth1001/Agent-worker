import 'package:hugeicons/hugeicons.dart';

import 'app_icons.dart';

/// Storage manager (Settings → STORAGE, Profile → MANAGE STORAGE): the
/// user's uploaded files, usage against the limit, bulk delete.

abstract final class StorageStrings {
  static const section = 'STORAGE';
  static const title = 'Storage';
  static const manage = 'MANAGE STORAGE';
  static const open = 'OPEN';
  static const used = 'Used';
  static const of = 'of';
  static const unlimited = 'UNLIMITED';
  static const full = 'Storage full';
  static const files = 'FILES';
  static const file = 'FILE';
  static const today = 'TODAY';
  static const uploadsToday = 'Uploads today';

  // Filters and sort.
  static const all = 'All';
  static const images = 'Images';
  static const videos = 'Videos';
  static const audio = 'Audio';
  static const documents = 'Documents';
  static const sort = 'Sort';
  static const newest = 'Newest';
  static const largest = 'Largest';
  static const name = 'Name';
  static const searchHint = 'Search files';

  // States.
  static const empty = 'No files yet';
  static const emptyHint = 'Files you attach in chats show up here.';
  static const noMatch = 'No matching files';
  static const loadFailed = 'Could not load your files.';
  static const loadMore = 'Load more';
  static const processing = 'Processing';
  static const failed = 'Failed';
  static const notInChat = 'Not in a chat';
  static const untitledChat = 'Untitled chat';

  // Selection.
  static const select = 'Select';
  static const selectAll = 'Select all';
  static const clearSelection = 'Clear selection';
  static String selected(int n) => '$n selected';

  // Item actions.
  static const actionOpen = 'Open';
  static const share = 'Share';
  static const download = 'Download';
  static const openChat = 'Open chat';
  static const rename = 'Rename';
  static const delete = 'Delete';
  static const renameHint = 'File name';
  static const renamed = 'Renamed.';
  static const renameFailed = 'Could not rename the file.';
  static const saved = 'Saved to downloads';
  static const shareFailed = 'Could not get the file.';

  // Delete.
  static String deleteTitle(int n) =>
      n == 1 ? 'Delete this file?' : 'Delete $n files?';
  static const deleteBody =
      'The files are removed from storage for good. Chats keep a '
      '“FILE DELETED” placeholder where they were attached.';
  static String deleted(int n) =>
      n == 1 ? 'File deleted.' : '$n files deleted.';
  static const deleteFailed = 'Could not delete. Try again.';

  static const separator = ' · ';
}

abstract final class StorageIcons {
  static const section = HugeIcons.strokeRoundedHardDrive;
  static const share = HugeIcons.strokeRoundedShare08;
  static const download = HugeIcons.strokeRoundedDownload04;
  static const openChat = HugeIcons.strokeRoundedBubbleChat;
  static const rename = AppIcons.edit;
  static const delete = AppIcons.delete;
  static const open = AppIcons.openExternal;
  static const sort = HugeIcons.strokeRoundedSorting01;
  static const select = HugeIcons.strokeRoundedCheckmarkSquare02;
  static const unselected = HugeIcons.strokeRoundedSquare;
  static const selectedMark = HugeIcons.strokeRoundedCheckmarkCircle02;
  static const more = HugeIcons.strokeRoundedMoreVertical;
  static const empty = HugeIcons.strokeRoundedFolder01;
}

abstract final class StorageSizes {
  static const gridColumns = 3;
  static const gridGap = 4.0;
  static const rowHeight = 64.0;
  static const rowThumb = 44.0;
  static const chipHeight = 32.0;
  static const badgeAlpha = 0.72;
  static const scrimAlpha = 0.45;
  static const selectMark = 22.0;

  /// Start loading the next page this far from the end of the list.
  static const loadMoreExtent = 600.0;
}

abstract final class StorageConfig {
  /// Wait after the last keystroke before searching.
  static const searchDebounce = Duration(milliseconds: 350);

  /// Folder inside the app's downloads directory.
  static const downloadFolder = 'Sparky';
}
