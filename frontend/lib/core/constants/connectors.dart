import 'package:hugeicons/hugeicons.dart';

import 'app_icons.dart';

/// Google Drive and Notion: the connector screens, the connect flow over
/// `sparky://auth/connect`, and the Save to Drive / Notion actions.

/// Provider ids as the backend names them.
abstract final class ConnectorIds {
  static const drive = 'google_drive';
  static const notion = 'notion';
}

/// Deep link `sparky://auth/connect?provider&ticket&state` (and the Drive
/// picker's `mode=picker&picked=N`).
abstract final class ConnectorLink {
  static const scheme = 'sparky';
  static const host = 'auth';
  static const path = '/connect';
  static const provider = 'provider';
  static const ticket = 'ticket';
  static const state = 'state';
  static const mode = 'mode';
  static const picked = 'picked';
  static const error = 'error';
  static const message = 'message';
  static const modePicker = 'picker';
  static const errDenied = 'access_denied';
}

/// Backend error codes the screens react to.
abstract final class ConnectorCodes {
  static const notConfigured = 'connector_not_configured';
  static const notConnected = 'connector_not_connected';
  static const reauth = 'connector_reauth';
  static const rateLimited = 'connector_rate_limited';
  static const rateLimitedApp = 'rate_limited';
}

abstract final class ConnectorStrings {
  static const notSetUp = 'Not set up on this server';
  static const notSetUpTag = 'UNAVAILABLE';
  static const notSetUpBody =
      'The server running sparky has not been set up for this app yet. '
      'Ask whoever runs it to add the app’s keys.';
  static const connected = 'CONNECTED';
  static const reconnectTag = 'RECONNECT';
  static const openingBrowser = 'Opening…';
  static const waiting = 'Waiting for approval…';
  static const finishing = 'Finishing…';
  static const openAgain = 'Open again';
  static const cancel = 'Cancel';
  static const reconnect = 'Reconnect';
  static const disconnect = 'Disconnect';
  static const reconnectHint = 'Sign in again or switch account';
  static const disconnectKeep = 'KEEP';
  static const disconnectAction = 'DISCONNECT';
  static const reconnectAction = 'RECONNECT';
  static const failed = 'Could not connect. Try again.';
  static const loadFailed = 'Could not load. Pull to retry.';
  static const offline = 'You’re offline. Showing what was loaded before.';
  static const rateLimited = 'Too many requests. Wait a minute and retry.';
  static const retry = 'Retry';
  static const askSparky = 'Ask Sparky';
  static const askSparkyHint = 'Start a chat about it';
  static const addToKb = 'Add to knowledge base';
  static const addToKbHint = 'Search it from any chat';
  static const addedToKb = 'Added to your knowledge base. Indexing…';
  static const read = 'Read';
  static const open = 'Open';
  static const truncated = 'Showing the beginning of a long file.';
  static const expiredTitle = 'Access expired';
  static const expiredBody =
      'The app stopped accepting sparky’s access (it was revoked or it '
      'expired). Reconnect to pick up where you left off.';
  static const saving = 'Saving…';
  static const saveFailed = 'Could not save. Try again.';
  static String connectedAs(String app) => '$app connected.';
  static String disconnected(String app) => '$app disconnected.';
  static String disconnectTitle(String app) => 'Disconnect $app?';
  static String disconnectBody(String app) =>
      'sparky will lose access to $app and the access will be revoked. '
      'Items already in your knowledge base stay there.';
  static String reconnectTitle(String app) => 'Reconnect $app?';
  static String reconnectBody(String app) =>
      'sparky will disconnect $app and ask for access again, for example '
      'to switch account.';
  static String continueTo(String vendor) => 'Continue to $vendor';
}

abstract final class DriveStrings {
  static const title = 'Google Drive';
  static const vendor = 'Google';
  static const permTitle = 'Let sparky see the files you pick?';
  static const permBody =
      'sparky only sees files you pick in Google Drive, plus the ones it '
      'saves there for you. It never browses the rest of your Drive. You '
      'can take access back any time in your Google account.';
  static const perks = <(AppIconData, String, String)>[
    (
      DriveIcons.pick,
      'Pick files',
      'Choose Docs, Sheets and PDFs for sparky to read.',
    ),
    (
      DriveIcons.ask,
      'Ask about them',
      'Start a chat about a file, or add it to your knowledge base.',
    ),
    (
      DriveIcons.save,
      'Save to Drive',
      'Send docs and chat exports straight to your Drive.',
    ),
  ];
  static const perksTitle = 'What you get';
  static const pick = 'Pick files from Drive';
  static const pickHint = 'Opens Google’s file picker';
  static const filesTitle = 'Files sparky can see';
  static const noFiles = 'No files yet';
  static const noFilesHint =
      'Pick files from Drive, or save a doc to Drive, and they show up here.';
  static const openInDrive = 'Open in Drive';
  static const filter = 'Filter your files';
  static const noMatches = 'No files match';
  static String picked(int n) => n == 0
      ? 'No new files picked.'
      : n == 1
      ? '1 file added.'
      : '$n files added.';
  static const pickerUnavailable =
      'The Drive picker is not set up on this server yet.';
  static const saveToDrive = 'Save to Drive';
  static const saved = 'Saved to Google Drive.';
  static const kindDoc = 'Google Doc';
  static const kindSheet = 'Google Sheet';
  static const kindSlides = 'Google Slides';
  static const kindPdf = 'PDF';
  static const kindText = 'Text';
  static const kindOther = 'File';
  static const unreadable = 'sparky can only show the details of this file.';

  /// The first message of a chat about a file (the file rides along).
  static String prompt(String name) =>
      'Read my Google Drive file “$name” and give me a short summary of what '
      'is in it. Then ask what I would like to do with it.';
}

abstract final class NotionStrings {
  static const title = 'Notion';
  static const vendor = 'Notion';
  static const permTitle = 'Let sparky read the pages you share?';
  static const permBody =
      'You choose which pages to share on Notion’s next screen. sparky can '
      'read those pages and, when you ask, add new pages under them. '
      'Nothing else in your workspace.';
  static const perks = <(AppIconData, String, String)>[
    (
      NotionIcons.page,
      'Read your pages',
      'Search the pages you shared and read them here.',
    ),
    (
      NotionIcons.ask,
      'Ask Sparky',
      'Chat about a page, or add it to your knowledge base.',
    ),
    (
      NotionIcons.save,
      'Save to Notion',
      'Put a sparky doc into Notion under a page you choose.',
    ),
  ];
  static const perksTitle = 'What you get';
  static const search = 'Search shared pages';
  static const pagesTitle = 'Shared with sparky';
  static const results = 'Results';
  static const noPages = 'No pages shared yet';
  static const noPagesHint =
      'In Notion, open a page → ••• → Connections → add sparky. Or '
      'reconnect and pick more pages.';
  static const noMatches = 'Nothing found';
  static String noMatchesHint(String q) =>
      'No shared page matches “$q”. Only pages you shared with sparky show up.';
  static const openInNotion = 'Open in Notion';
  static const database = 'DATABASE';
  static const empty = 'This page is empty.';
  static const saveToNotion = 'Save to Notion';
  static const pickParent = 'Save under which page?';
  static const noParents =
      'Share a page with sparky in Notion first; new pages go under it.';
  static const saved = 'Saved to Notion.';
  static const workspace = 'Workspace';
  static const untitled = 'Untitled';

  static String prompt(String title) =>
      'Read my Notion page “$title” and give me a short summary. Then ask '
      'what I would like to do with it.';
}

abstract final class DriveIcons {
  static const pick = HugeIcons.strokeRoundedFileAdd;
  static const ask = HugeIcons.strokeRoundedBubbleChat;
  static const save = HugeIcons.strokeRoundedCloudUpload;
  static const kb = AppIcons.knowledge;
  static const doc = HugeIcons.strokeRoundedDoc01;
  static const sheet = HugeIcons.strokeRoundedXls01;
  static const slides = HugeIcons.strokeRoundedPpt01;
  static const pdf = HugeIcons.strokeRoundedPdf01;
  static const text = HugeIcons.strokeRoundedTxt01;
  static const image = HugeIcons.strokeRoundedImage01;
  static const other = HugeIcons.strokeRoundedFile01;
  static const fallback = HugeIcons.strokeRoundedGoogleDrive;
}

abstract final class NotionIcons {
  static const page = HugeIcons.strokeRoundedFile02;
  static const database = HugeIcons.strokeRoundedTable01;
  static const ask = HugeIcons.strokeRoundedBubbleChat;
  static const save = HugeIcons.strokeRoundedFileUpload;
  static const kb = AppIcons.knowledge;
  static const fallback = HugeIcons.strokeRoundedNotebook;
}

abstract final class ConnectorUrls {
  static const drive = 'https://drive.google.com/drive/my-drive';
  static const notion = 'https://www.notion.so';
}

abstract final class ConnectorIcons {
  static const permission = HugeIcons.strokeRoundedShieldKey;
  static const reconnect = HugeIcons.strokeRoundedRefresh;
  static const disconnect = HugeIcons.strokeRoundedUnlink01;
  static const offline = HugeIcons.strokeRoundedWifiDisconnected01;
  static const warning = AppIcons.alert;
  static const unavailable = HugeIcons.strokeRoundedSettingsError01;
}

abstract final class ConnectorSizes {
  static const avatar = 64.0;
  static const rowIcon = 40.0;
  static const rowGlyph = 20.0;

  /// The brand mark inside an empty avatar, as a share of its diameter.
  static const avatarGlyphRatio = 0.42;
  static const brandOnButton = 18.0;
  static const emojiIcon = 20.0;
  static const workspaceEmoji = 30.0;
  static const readerMaxWidth = 720.0;
  static const skeletonRows = 5;
  static const searchPage = 30;
}

abstract final class ConnectorDurations {
  static const request = Duration(seconds: 25);

  /// A flow waiting for its deep link is dropped after this.
  static const pendingTtl = Duration(minutes: 15);
}
