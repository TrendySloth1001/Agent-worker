import 'package:hugeicons/hugeicons.dart';

import 'app_icons.dart';
import 'app_sizes.dart';

/// DOC mode: long-form cited documents with a full-page reader.
abstract final class DocStrings {
  // Composer
  static const chip = 'DOC';
  static const suggest = 'WRITE AS DOCUMENT?';
  static const suggestAction = 'WRITE';
  static const lengthLabel = 'LENGTH';
  static const lengthShort = 'SHORT';
  static const lengthStandard = 'STANDARD';
  static const lengthLong = 'LONG';

  /// Composer length picks, server value to label.
  static const lengths = [
    (DocConfig.lengthShort, lengthShort),
    (DocConfig.lengthStandard, lengthStandard),
    (DocConfig.lengthLong, lengthLong),
  ];

  // Chat
  static const turnIntoDoc = 'TURN INTO DOC';
  static const turnIntoDocHint = 'WRITE A FULL DOCUMENT FROM THIS REPLY';
  static const replyActions = 'REPLY';

  /// The user turn added for TURN INTO DOC.
  static const turnIntoDocTurn = 'Turn the reply above into a document.';

  /// The brief sent to POST /docs for TURN INTO DOC.
  static String briefFromReply(String? question, String reply) => [
    if (question != null && question.trim().isNotEmpty)
      'Question: ${question.trim()}',
    'Write a complete, well-structured document based on this answer, '
        'expanding it with research and citations:',
    reply.trim(),
  ].join('\n\n');

  /// Saved as the reply text of a doc message (history and search).
  static String messageText(String title) =>
      title.trim().isEmpty ? 'Document' : 'Document: ${title.trim()}';

  // Card
  static const card = 'DOCUMENT';
  static const open = 'OPEN';
  static const untitled = 'Untitled document';
  static const startFailed = 'Could not start the document.';
  static const docRunning =
      'A document is already being written. Wait for it to finish, or stop it.';

  // Status labels
  static String status(String s) => switch (s) {
    'planning' => 'PLANNING',
    'outline_ready' => 'OUTLINE READY',
    'researching' => 'RESEARCHING',
    'writing' => 'WRITING',
    'done' => 'DONE',
    'partial' => 'PARTIAL',
    'failed' => 'FAILED',
    'interrupted' => 'INTERRUPTED',
    _ => s.toUpperCase(),
  };

  /// Progress phase (doc_status `phase`).
  static String phase(String p) => switch (p) {
    'context' => 'GATHERING CONTEXT',
    'outline' || 'planning' => 'PLANNING OUTLINE',
    'research' || 'researching' => 'RESEARCHING',
    'sections' || 'writing' => 'WRITING',
    'finish' || 'finishing' => 'FINISHING',
    '' => 'STARTING',
    _ => p.toUpperCase().replaceAll('_', ' '),
  };

  // Reader header
  static const minRead = 'MIN READ';
  static const wordsUnit = 'WORDS';
  static const sourcesUnit = 'SOURCES';
  static const sep = ' · ';
  static const abstractLabel = 'ABSTRACT';
  static const references = 'References';
  static const referencesLabel = 'REFERENCES';
  static const glossary = 'GLOSSARY';
  static const knowledgeBase = 'Knowledge base';
  static const accessed = 'Retrieved';

  /// "14 MIN READ · 3,420 WORDS · 18 SOURCES · DONE".
  static String meta({
    required int words,
    required int sources,
    required String status,
  }) {
    final minutes = (words / DocConfig.wordsPerMinute).ceil().clamp(1, 999);
    return [
      '$minutes $minRead',
      '${thousands(words)} $wordsUnit',
      '$sources $sourcesUnit',
      DocStrings.status(status),
    ].join(sep);
  }

  /// 3420 -> "3,420".
  static String thousands(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  static String words(int n) => '${thousands(n)} $wordsUnit';

  /// "§3".
  static String sectionNo(int n) => '§$n';

  /// "§3/8".
  static String sectionOf(int n, int total) => '§$n/$total';

  // Sections
  static const pending = 'QUEUED';
  static const writingNow = 'WRITING';
  static const sectionFailed = 'THIS SECTION COULD NOT BE WRITTEN';
  static const retrySection = 'RETRY';
  static const goal = 'GOAL';

  /// "~450 WORDS".
  static String target(int words) => '~${thousands(words)} $wordsUnit';

  // Progress bar
  static const stop = 'STOP';
  static const resume = 'RESUME';
  static const start = 'START WRITING';
  static const outlineReadyHint = 'REVIEW THE OUTLINE, THEN START';
  static const reconnecting = 'RECONNECTING';
  static const stopped = 'STOPPED';

  /// "3/8 SECTIONS".
  static String doneOf(int done, int total) => '$done/$total SECTIONS';

  /// "~2 MIN LEFT" / "~40 S LEFT".
  static String eta(int ms) {
    final s = (ms / 1000).ceil();
    if (s >= 90) return '~${(s / 60).round()} MIN LEFT';
    return '~$s S LEFT';
  }

  // TOC
  static const contents = 'CONTENTS';
  static const tocOpen = 'Contents';

  // Section menu
  static const menuTitle = 'SECTION';
  static const regenerate = 'REGENERATE';
  static const expand = 'EXPAND';
  static const shorten = 'SHORTEN';
  static const simplify = 'SIMPLIFY';
  static const instruct = 'INSTRUCT…';
  static const edit = 'EDIT';
  static const versions = 'VERSIONS';
  static const instructTitle = 'INSTRUCT';
  static const instructHint = 'e.g. Add a worked example';
  static const apply = 'APPLY';
  static const cancel = 'CANCEL';
  static const save = 'SAVE';
  static const editTitle = 'EDIT SECTION';
  static const editHint = 'Markdown';
  static const restore = 'RESTORE';
  static const noVersions = 'No earlier versions yet.';
  static const busy = 'Wait for this section to finish.';
  static const actionFailed = 'Could not update the section.';
  static const saved = 'Section saved.';
  static const restored = 'Version restored.';

  /// "V3 · EXPAND · 2026-10-11 14:03".
  static String version(int v, String reason, DateTime? at) => [
    'V$v',
    reason.toUpperCase(),
    if (at != null) _stamp(at.toLocal()),
  ].join(sep);

  static String _stamp(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} '
        '${two(d.hour)}:${two(d.minute)}';
  }

  // Highlights
  static const highlight = 'HIGHLIGHT';
  static const note = 'NOTE';
  static const askAi = 'ASK AI';
  static const copyCite = 'COPY WITH CITATION';
  static const noteTitle = 'NOTE';
  static const noteHint = 'Your note';
  static const askTitle = 'ASK AI ABOUT THIS';
  static const askHint = 'e.g. Explain this more simply';
  static const highlights = 'HIGHLIGHTS';
  static const removeHighlight = 'REMOVE';
  static const copiedCite = 'Copied with citation.';
  static const highlightFailed = 'Could not save the highlight.';
  static const highlightsRemove = 'HIGHLIGHTS · TAP ONE TO REMOVE';

  /// "2 HIGHLIGHTS".
  static String highlightCount(int n) =>
      '$n ${n == 1 ? 'HIGHLIGHT' : highlights}';

  /// `“quote” — Title, §3 Heading (sparky)`.
  static String citeQuote({
    required String quote,
    required String title,
    required int section,
    required String heading,
    required String app,
  }) => '“${quote.trim()}”\n— $title, ${sectionNo(section)} $heading ($app)';

  // Ask AI (Q&A on a passage)
  static const askFailed = 'Could not get an answer. Try again.';
  static const thinking = 'THINKING';
  static const youAsked = 'YOU';
  static const answerLabel = 'ANSWER';
  static const followUpHint = 'Ask a follow-up';
  static const askSend = 'ASK';
  static const qaThread = 'Q&A';
  static const retry = 'RETRY';
  static const copyAnswer = 'COPY';
  static const copiedAnswer = 'Answer copied.';
  static const openThread = 'Open this Q&A';

  /// "2 QUESTIONS".
  static String qaCount(int n) => '$n ${n == 1 ? 'QUESTION' : 'QUESTIONS'}';

  // Notes panel: every highlight, note and Q&A in the document
  static const notesTitle = 'NOTES & Q&A';
  static const notesOpen = 'Notes and questions';
  static const notesEmpty =
      'Nothing yet. Select text to highlight it, add a note or ask AI.';
  static const notesQuestions = 'QUESTIONS';
  static const notesNotes = 'NOTES';
  static const notesHighlights = 'HIGHLIGHTS';
  static const delete = 'DELETE';

  // Selection edits
  static const editPassage = 'EDIT…';
  static const editPassageTitle = 'EDIT THIS PASSAGE';
  static const opExplain = 'EXPLAIN';
  static const opSimplify = 'SIMPLIFY';
  static const opExpand = 'EXPAND';
  static const opCite = 'ADD CITATIONS';
  static const opRewrite = 'REWRITE…';
  static const rewriteTitle = 'REWRITE THIS PASSAGE';
  static const rewriteHint = 'e.g. Make it more formal';
  static const previewTitle = 'PREVIEW';
  static const previewBefore = 'BEFORE';
  static const previewAfter = 'AFTER';
  static const previewAdded = 'ADDED';
  static const accept = 'ACCEPT';
  static const discard = 'DISCARD';
  static const working = 'WORKING';
  static const undo = 'UNDO';
  static const applied = 'Section updated.';
  static const undone = 'Change undone.';
  static const previewFailed = 'Could not prepare that change. Try again.';

  static String opLabel(String op) => switch (op) {
    'explain' => opExplain,
    'simplify' => opSimplify,
    'expand' => opExpand,
    'cite' => opCite,
    _ => opRewrite,
  };

  // Regenerate / add / continue
  static const regenerateWith = 'REGENERATE WITH A NOTE…';
  static const regenerateTitle = 'REGENERATE THIS SECTION';
  static const regenerateHint = 'e.g. Focus more on security';
  static const addBelow = 'ADD SECTION BELOW';
  static const addSectionTitle = 'ADD A SECTION';
  static const addHeadingHint = 'Heading';
  static const addGoalHint = 'What should it cover? (optional)';
  static const addAction = 'ADD & WRITE';
  static const continueWriting = 'CONTINUE WRITING';
  static const continueTitle = 'CONTINUE WRITING';
  static const continueHint = 'Topic for the next section (optional)';
  static const continueAction = 'WRITE';
  static const addFailed = 'Could not add the section.';

  // System notifications
  static const notifyProgressChannel = 'Document progress';
  static const notifyProgressChannelInfo =
      'Ongoing progress while a document is being written.';
  static const notifyDoneChannel = 'Document finished';
  static const notifyDoneChannelInfo = 'Sent when a document is ready.';
  static const notifyProgressTitle = 'Writing document';
  static const notifyDoneTitle = 'Document ready';
  static const notifyPartialTitle = 'Document stopped early';
  static const notifyFailedTitle = 'Document failed';
  static const notifyOutlineTitle = 'Outline ready to review';

  /// Body of the ongoing progress notification.
  static String notifyProgress({
    required String title,
    required int done,
    required int total,
    required String phase,
  }) {
    final name = title.trim().isEmpty ? '' : '${title.trim()}\n';
    if (total > 0 && phase != 'context' && phase != 'outline') {
      final current = (done + 1).clamp(1, total);
      return '${name}Section $current/$total · $done done';
    }
    return '$name${DocStrings.phase(phase)}';
  }

  /// "Title · 3,420 words · 8 sections".
  static String notifyDoneBody({
    required String title,
    required int words,
    required int sections,
  }) => [
    if (title.trim().isNotEmpty) title.trim(),
    '${thousands(words)} words',
    '$sections sections',
  ].join(sep);

  /// Chat/app-shell chip while a document is written elsewhere.
  static String backgroundRunning(int n) =>
      n == 1 ? '1 DOC WRITING' : '$n DOCS WRITING';
  static const backgroundOpen = 'Open the document being written';

  // Reader actions
  static const export = 'EXPORT';
  static const exportTitle = 'EXPORT DOCUMENT';
  static const pdf = 'PDF';
  static const markdown = 'MARKDOWN (.md)';
  static const docx = 'WORD (.docx)';
  static const exporting = 'EXPORTING';
  static const exportFailed = 'Could not export this document.';
  static const loadFailed = 'Could not load this document.';
  static const contentsPdf = 'Contents';
  static const abstractTitle = 'Abstract';
  static const glossaryTitle = 'Glossary';
  static const keyTakeaways = 'Key takeaways';
  static const fileFallback = 'document';
}

/// Behaviour and limits.
abstract final class DocConfig {
  static const lengthShort = 'short';
  static const lengthStandard = 'standard';
  static const lengthLong = 'long';
  static const defaultLength = lengthStandard;

  /// "write a report about …" while DOC is off suggests a document.
  static final intent = RegExp(
    r'\b(write|draft|create|make)\b.{0,40}\b(document|report|guide|whitepaper|article|handbook|brief|paper)\b',
    caseSensitive: false,
  );

  /// TURN INTO DOC shows on replies at least this long.
  static const turnIntoDocMinChars = 600;

  static const wordsPerMinute = 230;

  /// Waits before reconnecting a dropped event stream, then gives up.
  static const reconnectDelays = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
  ];

  /// Wait before re-attaching to a doc still being written, after the
  /// quick retries failed.
  static const slowReconnect = Duration(seconds: 20);

  /// No byte for this long on the event stream counts as dropped.
  static const streamIdle = Duration(seconds: 60);
  static const requestTimeout = Duration(seconds: 20);
  static const exportTimeout = Duration(seconds: 60);

  /// ASK AI and selection previews wait for one model call (with fallback).
  static const askTimeout = Duration(seconds: 150);

  /// Highlights longer than the inline mark syntax allows are split.
  static const markMaxChars = 150;

  /// Selection context kept on each side for re-anchoring.
  static const anchorContext = 32;
  static const highlightColor = 'accent';

  /// Highlights created by ASK AI (they carry a Q&A thread).
  static const askColor = 'ask';
}

/// Reader layout and typography.
abstract final class DocSizes {
  static const maxWidth = 720.0;

  /// From this width the TOC is a sticky rail beside the text.
  static const wideBreakpoint = 900.0;
  static const railWidth = 248.0;
  static const railGap = AppSpacing.xxl;

  // Reading type: comfortable body, generous leading.
  static const body = 17.0;
  static const bodyHeight = 1.7;
  static const bodySmall = 15.0;
  static const title = 34.0;
  static const titleHeight = 1.12;
  static const subtitle = 19.0;
  static const subtitleHeight = 1.4;
  static const sectionHeading = 25.0;
  static const sectionHeadingHeight = 1.22;
  static const abstractSize = 16.0;
  static const referenceSize = 14.0;
  static const referenceHeight = 1.5;
  static const referenceIdWidth = 40.0;

  static const sectionGap = 56.0;
  static const headingGap = AppSpacing.lg;
  static const headerTop = AppSpacing.xxl;
  static const bottomClear = 120.0;
  static const topBar = 48.0;

  // Progress bar and TOC pill
  static const progressHeight = 64.0;

  /// Pinned progress bar slot (bar plus its padding).
  static const progressExtent = progressHeight + AppSpacing.lg;
  static const pillHeight = 36.0;
  static const pillMaxWidth = 320.0;
  static const statusDot = 6.0;
  static const tocRow = 44.0;
  static const tocSheetFactor = 0.7;

  /// A section counts as current once its top passes this far down.
  static const currentLine = 0.25;

  // Skeleton cards
  static const skeletonBar = 10.0;
  static const skeletonLines = [1.0, 0.92, 0.84, 0.6];
  static const skeletonGap = AppSpacing.sm;
  static const pulse = Duration(milliseconds: 900);
  static const pulseMin = 0.35;

  /// Throttle for repainting the streaming section.
  static const streamThrottle = Duration(milliseconds: 60);

  // Chat card
  static const cardDot = 6.0;
  static const cardDotGap = 3.0;
  static const cardTitleLines = 2;
  static const cardButtonHeight = 30.0;

  // Editor
  static const editorMinLines = 12;
  static const instructMaxLines = 4;
  static const noteMarker = 18.0;
  static const notePreviewLines = 3;
  static const versionPreviewLines = 6;
  static const quotePreviewChars = 44;

  // Q&A cards, ask sheet, notes panel
  static const askSheetFactor = 0.88;
  static const qaQuoteLines = 2;
  static const qaBar = 3.0;
  static const askInputMaxLines = 4;
  static const earlierCollapsed = 1;
  static const noteRowQuoteLines = 2;
  static const noteRowAnswerLines = 3;

  // Passage edit preview
  static const previewSheetFactor = 0.85;
  static const previewTextLines = 40;

  // Background indicator
  static const chipHeight = 24.0;
  static const chipPadH = 10.0;
  static const chipDot = 6.0;
}

/// DOC mode icons (verified against hugeicons 1.2.0).
abstract final class DocIcons {
  static const doc = AppIcons.doc;
  static const toc = HugeIcons.strokeRoundedTableOfContents;
  static const more = HugeIcons.strokeRoundedMoreHorizontal;
  static const regenerate = HugeIcons.strokeRoundedRefresh;
  static const expand = HugeIcons.strokeRoundedArrowExpand02;
  static const shorten = HugeIcons.strokeRoundedArrowShrink02;
  static const simplify = HugeIcons.strokeRoundedMagicWand01;
  static const instruct = HugeIcons.strokeRoundedAiEditing;
  static const edit = HugeIcons.strokeRoundedFileEdit;
  static const versions = HugeIcons.strokeRoundedClock04;
  static const highlight = HugeIcons.strokeRoundedHighlighter;
  static const note = HugeIcons.strokeRoundedNote;
  static const ask = HugeIcons.strokeRoundedAiMagic;
  static const cite = HugeIcons.strokeRoundedQuoteDown;
  static const stop = HugeIcons.strokeRoundedStopCircle;
  static const resume = HugeIcons.strokeRoundedPlayCircle;
  static const export = HugeIcons.strokeRoundedFileExport;
  static const docx = HugeIcons.strokeRoundedDocumentAttachment;
  static const restore = HugeIcons.strokeRoundedUndo03;
  static const close = AppIcons.close;
  static const back = AppIcons.back;
  static const open = AppIcons.chevronRight;
  static const add = AppIcons.add;
  static const accept = AppIcons.check;
  static const notes = HugeIcons.strokeRoundedNote;
  static const explain = HugeIcons.strokeRoundedBulb;
  static const qa = HugeIcons.strokeRoundedBubbleChat;
  static const continueWriting = HugeIcons.strokeRoundedPencilEdit02;
}
