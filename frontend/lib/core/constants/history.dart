import 'app_icons.dart';

/// Sidebar (conversation drawer) copy.
abstract final class HistoryStrings {
  // Groups
  static const closeMenu = 'Close menu';
  static const pinned = 'PINNED';
  static const today = 'TODAY';
  static const yesterday = 'YESTERDAY';
  static const previous7 = 'PREVIOUS 7 DAYS';
  static const previous30 = 'PREVIOUS 30 DAYS';

  /// Full month names for the monthly groups, upper case.
  static const months = [
    'JANUARY',
    'FEBRUARY',
    'MARCH',
    'APRIL',
    'MAY',
    'JUNE',
    'JULY',
    'AUGUST',
    'SEPTEMBER',
    'OCTOBER',
    'NOVEMBER',
    'DECEMBER',
  ];

  // Header
  static const search = 'Search';
  static const searchHint = 'Search chats';
  static const closeSearch = 'Close search';
  static const clearSearch = 'Clear search';
  static const newChat = 'New chat';
  static const backToChats = 'Back to chats';
  static const archivedTitle = 'ARCHIVED';

  // Rows
  static const untitled = 'New chat';
  static const justNow = 'now';
  static const running = 'Replying';
  static const forked = 'Forked chat';
  static const merged = 'Merged chat';
  static const pinnedState = 'Pinned';
  static const currentState = 'Open chat';
  static const swipePin = 'PIN';
  static const swipeUnpin = 'UNPIN';
  static const swipeArchive = 'ARCHIVE';
  static const swipeUnarchive = 'RESTORE';
  static const renameHint = 'Chat name';
  static const renameSubmit = 'Save name';
  static const moreActions = 'More actions';

  // States
  static const loading = 'Loading chats';
  static const noChats = 'No chats yet. Start one and it appears here.';
  static const noMatchesFor = 'No chats match';
  static const loadMoreFailed = 'Could not load more.';

  // Footer
  static const knowledge = 'Knowledge';
  static const docs = 'Docs';
  static const storage = 'Storage';
  static const archived = 'Archived';
  static const settings = 'Settings';
  static const openSettings = 'Open settings';

  // Docs sheet
  static const docsTitle = 'DOCS';
  static const docsEmpty = 'No documents yet. Ask for one in a chat.';
  static const docsFailed = 'Could not load your documents.';
  static const docUntitled = 'Untitled document';
  static const docWriting = 'WRITING';
}

abstract final class HistorySizes {
  /// One chat row.
  static const rowHeight = 56.0;
  static const headerHeight = 56.0;
  static const groupHeight = 40.0;
  static const iconButton = 44.0;
  static const rowRadius = 28.0;
  static const rowInset = 12.0;
  static const runningDot = 7.0;

  // Footer
  static const quickHeight = 58.0;
  static const profileHeight = 56.0;
  static const avatar = 30.0;
  static const quickLabelMax = 12.0;

  // Skeleton
  static const skeletonRows = 9;
  static const dotSize = 2.4;
  static const dotGap = 5.0;
  static const skeletonRowHeight = 30.0;

  /// Load the next page this far from the end of the list.
  static const loadMoreExtent = 240.0;
  static const pageSize = 50;

  /// Swipe distance (fraction of the row) that commits an action.
  static const swipeThreshold = 0.35;
}

abstract final class HistoryIcons {
  static const search = AppIcons.search;
  static const newChat = AppIcons.newChat;
  static const close = AppIcons.close;
  static const back = AppIcons.back;
  static const fork = AppIcons.fork;
  static const merge = AppIcons.merge;
  static const archive = AppIcons.archive;
  static const docs = AppIcons.doc;
}

/// Sizes and timings of the sliding sidebar shell and its footer.
abstract final class DrawerMotion {
  /// Width of the left edge strip that starts an opening drag.
  static const edgeWidth = 24.0;

  /// Fling speed (dp/s) that decides the direction regardless of position.
  static const flingVelocity = 700.0;

  /// The chat shrinks to this scale and gains rounded corners as it is pushed.
  static const contentScale = 0.92;
  static const contentRadius = 28.0;
  static const scrimOpacity = 0.4;

  static const open = Duration(milliseconds: 400);
  static const close = Duration(milliseconds: 300);

  /// Fade-through of the chat content when another chat is shown.
  static const chatSwitch = Duration(milliseconds: 300);
  static const chatSwitchScale = 0.94;

  // Rows and footer, Material 3 navigation drawer.
  static const itemInset = 12.0;
  static const footerTileHeight = 48.0;
  static const footerGap = 8.0;
}

abstract final class HistoryDurations {
  static const pulse = Duration(milliseconds: 900);
  static const shimmer = Duration(milliseconds: 1500);
  static const swap = Duration(milliseconds: 180);
}
