import 'package:hugeicons/hugeicons.dart';

import 'app_icons.dart';

/// In-app file previews (chat attachments, composer, Storage, knowledge).

abstract final class PreviewStrings {
  // Top-bar actions.
  static const ask = 'ASK SPARKY';
  static const share = 'SHARE';
  static const download = 'DOWNLOAD';
  static const openWith = 'OPEN WITH…';
  static const info = 'FILE INFO';
  static const addToKb = 'ADD TO KNOWLEDGE';
  static const delete = 'DELETE';
  static const more = 'MORE';

  // Notices.
  static const saved = 'SAVED TO DOWNLOADS';
  static const actionFailed = 'COULD NOT GET THE FILE';
  static const noApp = 'NO APP CAN OPEN THIS FILE';
  static const deleteFailed = 'COULD NOT DELETE';

  // Delete sheet.
  static const deleteTitle = 'Delete this file?';
  static const deleteBody =
      'The file is removed from storage for good. Chats keep a '
      '“FILE DELETED” placeholder where it was attached.';

  // Ask.
  static String askPrompt(String name) =>
      'Take a look at the attached file “$name” and tell me what is in it.';

  // Info sheet and card.
  static const infoName = 'NAME';
  static const infoType = 'TYPE';
  static const infoSize = 'SIZE';
  static const infoDate = 'ADDED';
  static const infoPages = 'PAGES';
  static const infoDuration = 'DURATION';
  static const infoDimensions = 'DIMENSIONS';
  static const infoChat = 'CHAT';
  static const unknownTitle = 'NO PREVIEW FOR THIS TYPE';
  static const unknownHint =
      'Open it with another app, share it or save a copy.';
  static const textTitle = 'EXTRACTED TEXT';
  static const textHint =
      'sparky read this text from the file. Layout and images are not shown.';
  static const tooBig = 'THIS FILE IS TOO BIG TO PREVIEW';

  // Text-like previews.
  static const loadMore = 'LOAD MORE';
  static String rows(int shown, int total) => '$shown / $total ROWS';
  static const emptyFile = 'THIS FILE IS EMPTY';
  static const rawView = 'SOURCE';
  static const renderedView = 'RENDERED';
  static const viewToggle = 'SWITCH VIEW';

  // The two views of a file.
  static const viewOriginal = 'ORIGINAL';
  static const viewSparky = 'SPARKY';
  static const viewSemantics = 'File view';
  static const originalOfficeTitle = 'THIS FILE CAN’T BE SHOWN HERE';
  static const originalOfficeHint =
      'Office files open best in another app. Switch to the sparky view to '
      'read what sparky found in it.';

  // The sparky view.
  static const sparkyLoading = 'sparky is reading…';
  static const sparkySummary = 'SUMMARY';
  static const sparkyKeyPoints = 'KEY POINTS';
  static const sparkyText = 'TEXT';
  static const sparkyCaption = 'WHAT’S IN THE PICTURE';
  static const sparkyOcr = 'TEXT IN THE PICTURE';
  static const sparkyTranscript = 'WHAT IS SAID';
  static const sparkyTimeline = 'TIMELINE';
  static const sparkyNotReadTitle = 'sparky hasn’t read this file yet';
  static const sparkyNotReadHint =
      'Let sparky take a look and it’ll keep a short reading of it here.';
  static const sparkyReadNow = 'READ IT NOW';
  static const sparkyReading = 'READING…';
  static const sparkyNoSummaryTitle = 'No summary yet';
  static const sparkyNoSummaryHint =
      'sparky has the text. Ask for a short summary and key points.';
  static const sparkySummarize = 'SUMMARIZE';
  static const sparkyBusyTitle = 'sparky is still reading this file';
  static const sparkyBusyHint = 'Give it a moment, then check again.';
  static const sparkyCheckAgain = 'CHECK AGAIN';
  static const sparkyNoTextTitle = 'sparky found no text in this file';
  static const sparkyNoTextHint =
      'It may be a scan or an empty file. The original view still works.';
  static const sparkyErrorTitle = 'Couldn’t get sparky’s reading';
  static const sparkyErrorHint = 'Check your connection and try again.';
  static const sparkyReadFailed = 'sparky couldn’t read this just now';
  static const sparkySilentVideo = 'Nothing was said in this video.';
  static const sparkyNoAudio = 'This video has no sound.';
  static const sparkyNoFrames = 'sparky couldn’t pick out frames.';
  static const sparkyDescribeHint =
      'Frames get described the first time sparky reads the video.';
  static String sparkyMore(int left) => 'LOAD MORE · $left LEFT';

  // Pdf and loading.
  static const pdfPlaceholder = 'PDF';
  static const loadingFile = 'LOADING';
}

abstract final class PreviewIcons {
  static const ask = HugeIcons.strokeRoundedSparkles;
  static const share = HugeIcons.strokeRoundedShare08;
  static const download = HugeIcons.strokeRoundedDownload04;
  static const openWith = AppIcons.openExternal;
  static const info = HugeIcons.strokeRoundedInformationCircle;
  static const delete = AppIcons.delete;
  static const more = AppIcons.more;
  static const rawView = AppIcons.code;
  static const unknown = HugeIcons.strokeRoundedFileView;
  static const viewOriginal = HugeIcons.strokeRoundedFile01;
  static const viewSparky = HugeIcons.strokeRoundedAiMagic;
  static const timeline = HugeIcons.strokeRoundedTimeQuarter;
}

abstract final class PreviewSizes {
  static const infoCardIcon = 56.0;
  static const infoCardCircle = 90.0;
  static const infoCardMaxWidth = 420.0;
  static const csvCellMinWidth = 96.0;
  static const csvCellMaxWidth = 240.0;
  static const csvRowHeight = 36.0;
  static const csvCharWidth = 7.5;
  static const compactButton = 36.0;
  static const csvGutterWidth = 44.0;
  static const infoLabelWidth = 96.0;
  static const progressHeight = 2.0;
  static const immersiveScrimAlpha = 0.55;
  static const toggleHeight = 36.0;
  static const toggleMaxWidth = 280.0;
  static const toggleBarHeight = 44.0;
  static const toggleIcon = 16.0;
  static const timeColumn = 52.0;
  static const timelineDot = 8.0;
  static const timelineLine = 1.5;
  static const sparkyMaxWidth = 640.0;
}

abstract final class PreviewConfig {
  /// Characters of extracted text fetched per page in the sparky view.
  static const sparkyPage = 20000;

  /// Preferences key prefix: the last view picked for each type of file.
  static const viewPrefsKey = 'preview.view.';

  /// Folder inside the app cache directory.
  static const cacheFolder = 'previews';

  /// Oldest cached files go once the folder passes this size.
  static const cacheMaxBytes = 200 * 1024 * 1024;

  /// Raw text files up to this size are read from the cached bytes; bigger
  /// ones fall back to the server's extracted text.
  static const maxTextBytes = 2 * 1024 * 1024;

  /// Lines per rendered block, and blocks shown first / per LOAD MORE.
  static const blockLines = 40;
  static const firstBlocks = 25;
  static const moreBlocks = 50;

  /// CSV tables: rows shown first and per LOAD MORE, and the byte limit
  /// above which the file shows as plain text instead.
  static const csvFirstRows = 200;
  static const csvMoreRows = 400;
  static const csvMaxBytes = 512 * 1024;
  static const csvMaxColumns = 40;

  /// JSON is pretty-printed up to this size.
  static const jsonPrettyBytes = 512 * 1024;

  /// Server text preview limit for non-raw files (characters).
  static const extractedTextLimit = 200000;

  static const markdownExtensions = {'md', 'markdown'};
  static const csvExtensions = {'csv', 'tsv'};
  static const jsonExtensions = {'json'};
  static const plainTextExtensions = {'txt', 'log', 'text'};
  static const officeExtensions = {
    'docx',
    'doc',
    'xlsx',
    'xls',
    'pptx',
    'ppt',
    'odt',
    'ods',
    'odp',
    'rtf',
  };

  /// File extension -> highlight.js language.
  static const codeLanguages = <String, String>{
    'ts': 'typescript',
    'tsx': 'typescript',
    'js': 'javascript',
    'jsx': 'javascript',
    'mjs': 'javascript',
    'py': 'python',
    'dart': 'dart',
    'java': 'java',
    'kt': 'kotlin',
    'go': 'go',
    'rs': 'rust',
    'sql': 'sql',
    'xml': 'xml',
    'html': 'xml',
    'htm': 'xml',
    'css': 'css',
    'yaml': 'yaml',
    'yml': 'yaml',
    'sh': 'bash',
    'bash': 'bash',
    'c': 'c',
    'h': 'c',
    'cpp': 'cpp',
    'cs': 'cs',
    'rb': 'ruby',
    'php': 'php',
    'swift': 'swift',
    'toml': 'ini',
    'ini': 'ini',
    'json': 'json',
  };
}
