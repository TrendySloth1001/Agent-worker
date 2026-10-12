/// All user-facing text. System labels are uppercase, Nothing-style.
abstract final class AppStrings {
  static const appName = 'sparky';

  // Chat
  static const newChat = 'NEW CHAT';
  static const chatPill = 'CHAT';
  static const inputHint = 'Ask anything';
  static const send = 'SEND';
  static const thinking = 'THINKING';
  static const you = 'YOU';
  static const assistant = 'AI';
  static const emptyTitle = 'HELLO';
  static const emptySubtitle = 'Start a conversation.';

  /// One-tap starter prompts on an empty chat; tapping one sends it.
  static const emptyPrompts = [
    'Explain a concept',
    'Review my code',
    'Plan my day',
  ];

  // Models
  static const providerOllama = 'OLLAMA';

  // Message actions
  static const copy = 'COPY';
  static const copied = 'COPIED';
  static const tableLabel = 'TABLE';
  static const calloutNote = 'NOTE';
  static const calloutTip = 'TIP';
  static const calloutImportant = 'IMPORTANT';
  static const calloutWarning = 'WARNING';
  static const calloutCaution = 'CAUTION';
  static const calloutSummary = 'BOTTOM LINE';
  static const scrollToBottom = 'Scroll to bottom';

  // Errors
  static const errorGeneric = 'Something went wrong. Try again.';
  static const errorNetwork = 'No connection to server.';
  static const retry = 'RETRY';

  // Chat features
  static const web = 'WEB';
  static const kb = 'KB';
  static const sources = 'SOURCES';
  static const stop = 'STOP';
  static const regenerate = 'REGENERATE';
  static const searchingWeb = 'SEARCHING WEB';
  static const retrieving = 'RETRIEVING';
  static const expand = 'EXPAND';
  static const diagram = 'DIAGRAM';
  static const diagramSyntaxError = 'DIAGRAM SYNTAX ERROR';
  static const viewDiagram = 'VIEW DIAGRAM';
  static const tapToRender = 'TAP TO RENDER';

  // Knowledge
  static const knowledge = 'KNOWLEDGE';
  static const knowledgeBase = 'KNOWLEDGE BASE';
  static const addSource = 'ADD SOURCE';
  static const queued = 'QUEUED';
  static const running = 'RUNNING';
  static const ready = 'READY';
  static const failed = 'FAILED';
  static const empty = 'EMPTY';
  static const kindWeb = 'WEB';
  static const kindGithub = 'GITHUB';
  static const kindStack = 'STACK';
  static const kindReddit = 'REDDIT';
  static const kindHn = 'HN';
  static const kindNote = 'NOTE';
  static const kindFile = 'FILE';
  static const kindDoc = 'DOC';

  // Menu and settings
  static const settings = 'SETTINGS';
  static const back = 'Back';
  static const appearance = 'APPEARANCE';
  static const theme = 'THEME';
  static const themeSystem = 'SYSTEM';
  static const themeLight = 'LIGHT';
  static const themeDark = 'DARK';
  static const usage = 'USAGE';
  static const chat = 'CHAT';
  static const haptics = 'HAPTICS';
  static const webSearchDefault = 'WEB SEARCH BY DEFAULT';
  static const knowledgeDefault = 'KNOWLEDGE BY DEFAULT';
  static const mode = 'MODE';
  static const modeEngineer = 'ENGINEER';
  static const modeDebug = 'DEBUG';
  static const modeReview = 'REVIEW';
  static const modeArchitect = 'ARCHITECT';
  static const modeExplain = 'EXPLAIN';
  static const about = 'ABOUT';

  // Personalization
  static const personalization = 'PERSONALIZATION';
  static const profileName = 'NAME';
  static const profileRole = 'ROLE';
  static const profileAbout = 'ABOUT YOU';
  static const profileLanguage = 'LANGUAGE';
  static const profileTone = 'TONE';
  static const profileLength = 'RESPONSE LENGTH';
  static const profileInstructions = 'CUSTOM INSTRUCTIONS';
  static const profileSignature = 'EMAIL SIGNATURE';
  static const notSet = 'NOT SET';
  static const clear = 'CLEAR';
  static const toneFriendly = 'FRIENDLY';
  static const toneProfessional = 'PROFESSIONAL';
  static const toneCasual = 'CASUAL';
  static const toneDirect = 'DIRECT';
  static const toneEnthusiastic = 'ENTHUSIASTIC';
  static const lengthConcise = 'CONCISE';
  static const lengthBalanced = 'BALANCED';
  static const lengthDetailed = 'DETAILED';
  static const nameHint = 'What should the AI call you?';
  static const roleHint = 'e.g. Backend engineer';
  static const aboutHint = 'Background, interests, what you work on';
  static const languageHint = 'e.g. English, Hindi, Spanish';
  static const instructionsHint = 'How should the AI respond to you?';
  static const signatureHint = 'Added to the end of email drafts';
  static const backend = 'BACKEND';
  static const status = 'STATUS';
  static const online = 'ONLINE';
  static const degraded = 'DEGRADED';
  static const offline = 'OFFLINE';
  static const dash = '—';
  static const separator = ' · ';
  static const usageOffline = 'USAGE UNAVAILABLE · SERVER OFFLINE';
  static const today = 'TODAY';
  static const thisMonth = 'THIS MONTH';
  static const used = 'USED';
  static const remaining = 'REMAINING';
  static const resets = 'RESETS';
  static const requests = 'REQUESTS';
  static const embeddings = 'EMBEDDINGS';
  static const search = 'SEARCH';
  static const texts = 'TEXTS';
  static const tokens = 'TOKENS';
  static const sourcesCount = 'SOURCES';
  static const chunks = 'CHUNKS';

  // Chat features, additions
  static const saveToKnowledge = 'SAVE';
  static const saved = 'SAVED';
  static const saving = 'SAVING';
  static const saveFailed = 'COULD NOT SAVE';
  static const copyLink = 'LINK COPIED';
  static const copySource = 'COPY SOURCE';
  static const mermaidLabel = 'MERMAID';
  static const noticeFallback = 'Switched to another model.';
  static const stoppedByUser = 'STOPPED';
  static const errorTimeout = 'The server stopped responding.';
  static const errorInterrupted = 'The reply was interrupted.';
  static const cantOpenLink = 'Could not open link.';

  // Knowledge screen
  static const knowledgeEmpty = 'No sources yet. Add docs, a repo or a thread.';
  static const knowledgeLoadFailed = 'Could not load sources.';
  static const addSourceHint = 'URL, owner/repo, tag or search';
  static const addSourceKind = 'TYPE';
  static const addSourceLimit = 'LIMIT';
  static const kindAuto = 'AUTO';
  static const add = 'ADD';
  static const adding = 'ADDING';
  static const deleteSource = 'DELETE';
  static const deleteSourceTitle = 'DELETE SOURCE';
  static const deleteSourceBody =
      'This removes the source and all of its chunks from the knowledge base.';
  static const cancel = 'CANCEL';

  // Images and sources
  static const images = 'IMAGES';
  static const openSource = 'OPEN SOURCE';
  static const copyLinkAction = 'COPY LINK';
  static const savedToKnowledge = 'Saved to knowledge.';
  static const imageFailed = 'Image unavailable';

  // History
  static const history = 'HISTORY';
  static const conversations = 'CONVERSATIONS';
  static const openMenu = 'MENU';
  static const searchChats = 'Search chats';
  static const historyEmpty = 'No chats yet. Start one and it appears here.';
  static const historyNoMatches = 'No chats match.';
  static const historyLoadFailed = 'Could not load chats.';
  static const untitled = 'NEW CHAT';
  static const yesterday = 'YESTERDAY';
  static const thisWeek = 'THIS WEEK';
  static const earlier = 'EARLIER';
  static const rename = 'RENAME';
  static const renameHint = 'Chat name';
  static const save = 'SAVE';
  static const deleteChat = 'DELETE';
  static const pinChat = 'PIN';
  static const unpinChat = 'UNPIN';
  static const archiveChat = 'ARCHIVE';
  static const unarchiveChat = 'UNARCHIVE';
  static const pinned = 'PINNED';
  static const archived = 'ARCHIVED';
  static const archivedEmpty = 'No archived chats.';
  static const chatArchived = 'Chat archived';
  static const chatUnarchived = 'Chat restored';
  static const undo = 'UNDO';
  static const deleteChatTitle = 'DELETE CHAT';
  static const deleteChatBody = 'This chat and its messages will be removed.';
  static const chatLoadFailed = 'Could not open this chat.';

  /// Source chip of an earlier chat the assistant recalled.
  static const chatSourcePrefix = 'Chat · ';
  static const chatSourceUntitled = 'Untitled';
  static const months = [
    'JAN',
    'FEB',
    'MAR',
    'APR',
    'MAY',
    'JUN',
    'JUL',
    'AUG',
    'SEP',
    'OCT',
    'NOV',
    'DEC',
  ];
  static const refresh = 'REFRESH';
  static const documents = 'DOCS';
  static const chunksShort = 'CHUNKS';
  static const never = 'NEVER';

  // Settings, redesigned
  static const modelsSection = 'MODELS';
  static const dataToolsSection = 'DATA & TOOLS';
  static const allSystems = 'ALL SYSTEMS';
  static const providersActive = 'PROVIDERS';
  static const requestsToday = 'REQUESTS TODAY';
  static const tokensToday = 'TOKENS TODAY';
  static const staleData = 'SHOWING LAST KNOWN DATA';
  static const serverOffline = 'SERVER OFFLINE';
  static const serverOfflineHint =
      'Cannot reach the backend. Check the URL and your network.';
  static const keyLabel = 'KEY';
  static const keyNotSet = 'NOT SET';
  static const keyNotSetHint =
      'Add this key to the server environment, then restart it.';
  static const statusOk = 'OK';
  static const statusLimited = 'LIMITED';
  static const statusExhausted = 'EXHAUSTED';
  static const statusMissing = 'NO KEY';
  static const statusUnknown = 'UNKNOWN';
  static const periodDay = 'TODAY';
  static const periodRolling = 'ROLLING 24H';
  static const periodMonth = 'THIS MONTH';
  static const periodMinute = 'PER MINUTE';
  static const perModel = 'PER MODEL';
  static const official = 'OFFICIAL';
  static const tracked = 'TRACKED BY SERVER';
  static const noLimitKnown = 'NO PUBLISHED LIMIT';
  static const resetsIn = 'RESETS IN';
  static const resetsNow = 'RESETS NOW';
  static const ago = 'AGO';
  static const reqShort = 'REQ';
  static const tokShort = 'TOK';
  static const failShort = 'FAIL';
  static const planLabel = 'PLAN';
  static const modelsLabel = 'MODELS';
  static const coolingLabel = 'COOLING DOWN';
  static const lastLimitHit = 'LAST LIMIT HIT';
  static const monthLabel = 'THIS MONTH';
  static const noModels = 'NONE';
  static const githubToken = 'GITHUB TOKEN';
  static const account = 'ACCOUNT';
  static const rateLimit = 'RATE LIMIT';
  static const perHour = 'PER HOUR';
  static const purpose = 'PURPOSE';
  static const provider = 'PROVIDER';
  static const model = 'MODEL';
  static const dimensions = 'DIMENSIONS';
  static const database = 'DATABASE';
  static const server = 'SERVER';
  static const connected = 'CONNECTED';
  static const handle = '@';
  static const slash = ' / ';
  static const thousandSuffix = 'K';
  static const millionSuffix = 'M';
  static const unitMinute = 'M';
  static const unitHour = 'H';
  static const unitDay = 'D';
  static const openKnowledge = 'OPEN KNOWLEDGE';
  static const providerAtLimit = 'PROVIDER AT LIMIT';
  static const providersAtLimit = 'PROVIDERS AT LIMIT';
  static const expectedCapacity = 'EXPECTED DAILY CAPACITY';
  static const approx = '≈';
  static const noDailyCapSuffix = '(NO DAILY CAP)';
  static const expectedPerDay = 'EXPECTED / DAY';
  static const noDailyCapPublished = 'NO DAILY CAP PUBLISHED';
  static const notPublished = 'NOT PUBLISHED';
  static const perModelSuffix = '/ MODEL';
  static const tokensThisMinute = 'TOKENS THIS MINUTE';
  static const left = 'LEFT';
  static const limitLabel = 'LIMIT';
  static const groupSeparator = ',';
  static const plus = '+';

  // Evidence sheet
  static const evidenceClaim = 'CLAIM';
  static const evidencePassage = 'SUPPORTING PASSAGE';
  static const evidenceMatch = 'MATCH';
  static const evidenceStrong = 'STRONG';
  static const evidencePartial = 'PARTIAL';
  static const evidenceWeak = 'WEAK';
  static const copyQuote = 'COPY QUOTE';
  static const quoteCopied = 'QUOTE COPIED';

  // Attachments
  static const attachTitle = 'ATTACH';
  static const attachPhotos = 'PHOTOS';
  static const attachCamera = 'CAMERA';
  static const attachVideo = 'VIDEO';
  static const attachDocument = 'DOCUMENT';
  static const attachRemove = 'REMOVE';
  static const attachRetry = 'TAP TO RETRY';
  static const attachProcessing = 'PROCESSING';
  static const attachFailed = 'FAILED';
  static const attachMax = 'MAX 10 FILES';
  static const attachTooBig = 'FILE TOO LARGE';
  static const attachUnsupported = 'UNSUPPORTED FILE TYPE';
  static const attachFixFailed = 'REMOVE OR RETRY FAILED FILES';
  static const attachPages = 'PAGES';
  static const attachPage = 'PAGE';
  static const attachFile = 'FILE';
  static const attachOpenFailed = 'CANT OPEN FILE';
  static const attachDeleted = 'FILE DELETED';
  static const attachMedia = 'PHOTOS & VIDEOS';
  static const attachTakePhoto = 'TAKE PHOTO';
  static const attachRecordVideo = 'RECORD VIDEO';
  static String attachSkipped(int n, int max) =>
      '$n SKIPPED, MAX $max PER MESSAGE';

  // File preview
  static const previewOpen = 'OPEN';
  static const previewCopyLink = 'COPY LINK';
  static const previewLinkCopied = 'LINK COPIED';
  static const previewNoLink = 'NO LINK YET';
  static const previewProcessing = 'STILL PROCESSING';
  static const previewProcessingHint = 'The text is not ready yet.';
  static const previewLoadFailed = 'COULD NOT LOAD FILE';
  static const previewTruncated = 'SHOWING THE FIRST PART ONLY';
  static const previewSearchHint = 'SEARCH IN TEXT';
  static const previewTranscript = 'TRANSCRIPT';
  static const previewNoTranscript = 'NO TRANSCRIPT';
  static const previewSearch = 'SEARCH';
  static String previewMatches(int n) => n == 1 ? '1 MATCH' : '$n MATCHES';
  static String previewPage(int n, int total) => '$n / $total';
}

abstract final class BrowserStrings {
  static const title = 'OPEN WITH';
  static const rowLabel = 'BROWSER';
  static const section = 'DEFAULT BROWSER';
  static const defaultTag = 'DEFAULT';
  static const always = 'ALWAYS USE THIS BROWSER';
  static const systemDefault = 'SYSTEM DEFAULT';
  static const none = 'NO BROWSER FOUND';
  static const openWith = 'OPEN WITH...';
  static const channel = 'app/browsers';
}

/// Expanded source card under a reply.
abstract final class SourceStrings {
  static const visit = 'VISIT';
  static const cited = 'CITED IN THIS ANSWER';
  static const fromKnowledge = 'FROM YOUR KNOWLEDGE BASE';
  static const document = 'ATTACHED DOCUMENT';
  static const opensIn = 'OPENS IN';
  static const asksBrowser = 'ASKS WHICH BROWSER EACH TIME';
  static const change = 'CHANGE';
  static const setDefault = 'SET DEFAULT';
  static const noLink = 'Saved note: nothing to open.';
}

/// Forking and merging chats.
abstract final class LineageStrings {
  static const fork = 'FORK';
  static const merge = 'MERGE';
  static const forkFromHere = 'FORK FROM HERE';
  static const mergeWith = 'MERGE WITH…';
  static const forked = 'Forked.';
  static const forkFailed = 'Could not fork.';
  static const mergeFailed = 'Could not merge.';
  static const forkedFrom = 'FORKED FROM';
  static const forkedFromDeleted = 'FORKED FROM A DELETED CHAT';
  static const mergedFrom = 'MERGED FROM';
  static const mergeTitle = 'MERGE CHATS';
  static const mergeBody =
      'Creates a new chat that starts from a summary of both. '
      'The originals stay unchanged.';
  static const merging = 'MERGING';
  static const pickChat = 'MERGE WITH';
  static const noOtherChats = 'No other chats to merge with.';
  static const summaryNote = 'The model sees this summary, not the full chats.';
  static const showSummary = 'SHOW SUMMARY';
  static const hideSummary = 'HIDE SUMMARY';
  static const fallbackSummary = 'BASIC SUMMARY';
}

/// Round Table mode: several models draft, cross-review, a chair answers.
abstract final class TableStrings {
  static const chip = 'TABLE';
  static const byDefault = 'ROUND TABLE BY DEFAULT';
  static const title = 'ROUND TABLE';
  static const status = 'ROUND TABLE';
  static const seating = 'SEATING';
  static const drafting = 'DRAFTING';
  static const checking = 'CHECKING AGREEMENT';
  static const reviewing = 'CROSS-REVIEW';
  static const synthesizing = 'CHAIR WRITING';
  static const chair = 'CHAIR';
  static const models = 'MODELS';
  static const separator = ' · ';
  static const dash = ' — ';
  static const agreed = 'AGREED';
  static const resolved = 'RESOLVED';
  static const disputed = 'DISPUTED';
  static const couldNotAgree = 'THE TABLE COULD NOT AGREE ON';
  static const reviews = 'REVIEWS';
  static const allAgree = 'All reviewers agreed.';
  static const kindError = 'ERRORS';
  static const kindDisagree = 'DISAGREEMENTS';
  static const kindMissing = 'MISSING';
  static const failed = 'NO DRAFT';
  static const seatPrefix = 'SEAT ';
  static const onSeat = 'ON ';

  /// "3 MODELS" style count.
  static String modelCount(int n) => '$n $models';
}

/// AI tidy-up in the personalization editors.
abstract final class ProfileAiStrings {
  static const format = 'FORMAT WITH AI';
  static const formatting = 'FORMATTING';
  static const undo = 'UNDO';
  static const failed = 'Could not format right now.';
  static const fieldAbout = 'about';
  static const fieldInstructions = 'instructions';
}

/// Round Table waiting: progress meter, actions, per-seat research and
/// system notifications.
abstract final class TableWaitStrings {
  static const researching = 'RESEARCHING';
  static const stepResearch = 'RESEARCH';
  static const stepSeat = 'SEAT';
  static const stepDraft = 'DRAFT';
  static const stepCheck = 'CHECK';
  static const stepReview = 'REVIEW';
  static const stepChair = 'CHAIR';
  static const almostDone = 'ALMOST DONE';
  static const intro =
      'Several models research, draft and check each other, then a chair '
      'writes the answer. Wait, answer fast, or get notified.';
  static const answerFast = 'ANSWER FAST INSTEAD';
  static const notifyMe = 'NOTIFY ME';
  static const willNotify = 'WILL NOTIFY';
  static const notifyOn = "You can leave. We'll notify you when it's ready.";
  static const notifyBlocked =
      'Notifications are off for this app. Turn them on in system settings.';
  static const sources = 'SOURCES';
  static const showAll = 'SHOW ALL';
  static const showLess = 'SHOW LESS';
  static const notifySetting = 'NOTIFY WHEN ROUND TABLE FINISHES';

  // System notifications.
  static const progressChannel = 'Round table progress';
  static const progressChannelInfo =
      'Ongoing progress while a round table works in the background.';
  static const doneChannel = 'Round table finished';
  static const doneChannelInfo = 'Sent when a round table answer is ready.';
  static const progressTitle = 'Round table working';
  static const doneTitle = 'Round table finished';
  static const failedTitle = 'Round table stopped';
  static const untitled = 'New chat';

  /// Caption for a live Round Table phase.
  static String phase(String? phase) => switch (phase) {
    'researching' => researching,
    'seating' => TableStrings.seating,
    'drafting' => TableStrings.drafting,
    'checking' => TableStrings.checking,
    'reviewing' => TableStrings.reviewing,
    'synthesizing' => TableStrings.synthesizing,
    _ => TableStrings.status,
  };

  /// "≈ 40S LEFT".
  static String left(int seconds) => '≈ ${seconds}S LEFT';

  /// "≈ 40s left" for notification text.
  static String leftLower(int seconds) => '≈ ${seconds}s left';

  /// "Round table finished · Sodium limits".
  static String doneFor(String title) =>
      '$doneTitle${TableStrings.separator}$title';

  /// "00:23".
  static String clock(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

/// Round Table "WHO AGREED": which seats' drafts back each sentence.
abstract final class TableSupportStrings {
  static const toggle = 'WHO AGREED';
  static const title = 'WHO AGREED';
  static const hint =
      'Dots mark the seats whose own draft makes the same '
      'claim. Tap a dot to read that draft.';
  static const noSeat = 'No draft states this directly.';
  static const disputed = 'DISPUTED';
  static const all = 'ALL SEATS';
  static String seatOf(String seat, String name) => '$seat · $name';
}

/// A round table that keeps running after switching chats.
abstract final class BackgroundTableStrings {
  static String running(int n) =>
      n == 1 ? '1 ROUND TABLE RUNNING' : '$n ROUND TABLES RUNNING';
  static const open = 'Open the running round table';
}

/// Settings → GitHub token: who it is and what it may read.
abstract final class GithubSettingsStrings {
  static const connectedAs = 'CONNECTED AS';
  static const scopes = 'SCOPES';
  static const fineGrained = 'Fine-grained token';
  static const noScopes = 'None';
  static const privateRepos = 'PRIVATE REPOS';
}

/// Markdown table chrome: view toggle, expand, swipe hint, export labels.
abstract final class MdTableStrings {
  static const table = 'TABLE';
  static const cards = 'CARDS';
  static const expand = 'Expand table';
  static const swipe = 'SWIPE';
  static const copyMarkdown = 'COPY MD';
  static const copyTsv = 'COPY TSV';
  static const empty = '\u2013';
  static const sortedAscending = 'sorted ascending';
  static const sortedDescending = 'sorted descending';
  static const tabSeparator = '\t';
}
