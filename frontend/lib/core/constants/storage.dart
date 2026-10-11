import 'package:hugeicons/hugeicons.dart';

import 'app_icons.dart';

/// Storage manager (Settings → STORAGE, Profile → MANAGE STORAGE): the
/// user's uploaded files, usage against the limit, bulk delete.

abstract final class StorageStrings {
  static const section = 'STORAGE';
  static const title = 'STORAGE';
  static const manage = 'MANAGE STORAGE';
  static const open = 'OPEN';
  static const used = 'USED';
  static const of = 'OF';
  static const unlimited = 'UNLIMITED';
  static const full = 'STORAGE FULL';
  static const files = 'FILES';
  static const file = 'FILE';
  static const today = 'TODAY';
  static const uploadsToday = 'UPLOADS TODAY';

  // Filters and sort.
  static const all = 'ALL';
  static const images = 'IMAGES';
  static const videos = 'VIDEOS';
  static const audio = 'AUDIO';
  static const documents = 'DOCUMENTS';
  static const sort = 'SORT';
  static const newest = 'NEWEST';
  static const largest = 'LARGEST';
  static const name = 'NAME';
  static const searchHint = 'Search files';

  // States.
  static const empty = 'NO FILES YET';
  static const emptyHint = 'Files you attach in chats show up here.';
  static const noMatch = 'NO MATCHING FILES';
  static const loadFailed = 'Could not load your files.';
  static const loadMore = 'LOAD MORE';
  static const processing = 'PROCESSING';
  static const failed = 'FAILED';
  static const notInChat = 'NOT IN A CHAT';
  static const untitledChat = 'Untitled chat';

  // Selection.
  static const select = 'SELECT';
  static const selectAll = 'SELECT ALL';
  static const clearSelection = 'CLEAR';
  static String selected(int n) => '$n SELECTED';

  // Item actions.
  static const actionOpen = 'OPEN';
  static const share = 'SHARE';
  static const download = 'DOWNLOAD';
  static const openChat = 'OPEN CHAT';
  static const rename = 'RENAME';
  static const delete = 'DELETE';
  static const renameHint = 'File name';
  static const renamed = 'Renamed.';
  static const renameFailed = 'Could not rename the file.';
  static const saved = 'SAVED TO DOWNLOADS';
  static const shareFailed = 'Could not get the file.';

  // Delete.
  static String deleteTitle(int n) =>
      n == 1 ? 'DELETE THIS FILE?' : 'DELETE $n FILES?';
  static const deleteBody =
      'The files are removed from storage for good. Chats keep a '
      '"FILE DELETED" placeholder where they were attached.';
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
