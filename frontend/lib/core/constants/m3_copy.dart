/// Sentence-case copy for the Material 3 grouped screens (Knowledge base,
/// Telemetry, About and the sheets). Tiny Space Mono metadata keeps its
/// uppercase strings elsewhere.
abstract final class KnowledgeCopy {
  static const title = 'Knowledge base';
  static const addSource = 'Add source';
  static const add = 'Add';
  static const adding = 'Adding';
  static const sources = 'Sources';
  static const refresh = 'Refresh';
  static const retry = 'Retry';
  static const kind = 'Type';
  static const limit = 'Limit';
  static const auto = 'Auto';
  static const deleteSource = 'Delete';
  static const deleteTitle = 'Delete source?';
  static const emptyTitle = 'No sources yet';
  static const emptyHint = 'Add docs, a repo or a thread for Sparky to read.';
  static const swipeHint = 'Swipe a source left to delete it.';

  // Status.
  static const queued = 'Queued';
  static const running = 'Running';
  static const ready = 'Ready';
  static const failed = 'Failed';
  static const empty = 'Empty';

  // Source kinds.
  static const kindWeb = 'Web';
  static const kindGithub = 'GitHub';
  static const kindStack = 'Stack Overflow';
  static const kindReddit = 'Reddit';
  static const kindHn = 'Hacker News';
  static const kindNote = 'Note';
  static const kindFile = 'File';
  static const kindDoc = 'Doc';
  static const kindDocument = 'Document';
  static const kindDrive = 'Google Drive';
  static const kindNotion = 'Notion';

  static const docs = 'docs';
  static const chunks = 'chunks';

  // Group headers.
  static const groupDocuments = 'Your documents';
  static const groupWeb = 'Web pages';
  static const groupGithub = 'GitHub';
  static const groupNotes = 'Notes';

  static const searchHint = 'Search sources';
  static const noMatches = 'No sources match';
  static const noMatchesHint = 'Try another word or clear the search.';
  static const clearSearch = 'Clear search';
  static const moreActions = 'More actions';
  static const indexing = 'Indexing';
  static const nothingIndexed = 'Nothing indexed';
  static const justUpdated = 'updated just now';

  /// "35 passages", "1 passage".
  static String passages(int n) => n == 1 ? '1 passage' : '$n passages';

  static String updated(String ago) => 'updated $ago';
}

abstract final class KnowledgeSizes {
  static const progressHeight = 2.0;
  static const statusDot = 6.0;
  static const searchHeight = 48.0;

  /// The leading icon tile of a source row.
  static const iconTile = 40.0;
  static const iconTileRadius = 12.0;
  static const iconGlyph = 22.0;

  /// Padding around a fetched site icon so logos do not touch the tile edge.
  static const iconInset = 6.0;
}

abstract final class TelemetryCopy {
  static const charts = 'Per minute';
  static const chartRequests = 'Requests and failures';
  static const chartTokens = 'Tokens';
  static const chartLatency = 'Latency p50 and TTFT';
  static const models = 'Models';
  static const providers = 'Providers';
  static const kinds = 'By kind';
  static const users = 'Users';
  static const topErrors = 'Top errors';
  static const log = 'Live log';
  static const recentEvents = 'Recent events';
  static const failedOnly = 'Failed only';
  static const pause = 'Pause';
  static const resume = 'Resume';
  static const loadMore = 'Load older';
  static const noMore = 'End of log';
  static const openDetail = 'Details';
  static const filterProvider = 'Provider';
  static const filterKind = 'Kind';
  static const filterAll = 'All';
  static const empty = 'No calls in this window';
  static const emptyLog = 'No events yet';
  static const bucketLabels = {'1m': '1 min', '5m': '5 min', '1h': '1 hour'};

  // Redesigned plain layout.
  static const activity = 'Activity';
  static const metricRequests = 'Requests';
  static const metricTokens = 'Tokens';
  static const metricLatency = 'Latency';
  static const summaryRequests = 'Requests';
  static const summaryFailed = 'Failed';
  static const summaryTokens = 'Tokens';
  static const summaryP50 = 'p50 latency';
  static const unknownNote = 'without a recorded outcome (older rows)';
  static const kindMenu = 'Kind';
  static const kindAll = 'All kinds';
  static const providerFiltered = 'Showing';
  static const clearFilter = 'Clear';
  static const colRequests = 'Calls';
  static const colFail = 'Failed';
  static const colP50 = 'p50';
  static const modelsUnused = 'Unused models hidden';
  static const webSearch = 'Web search';
  static const pageFetch = 'Page fetch';
  static const embeddings = 'Embeddings';
  static const transcription = 'Transcription';
  static const github = 'GitHub';
  static const other = 'Other';
  static const perTurn = 'Cost per message';
  static const budgets = 'Budgets';
  static const budgetsNote =
      'This minute and today, per model or account. Calls that would not fit are skipped before they hit a rate limit.';
  static const budgetSkips = 'Skipped';
  static const budgetWaits = 'Waited';
  static const budgetAuxDeferred = 'Deferred';
  static const budgetAuxCached = 'Cached';
  static const budgetUserCaps = 'User caps';
  static const budgetMinute = 'min';
  static const budgetToday = 'today';
  static const budgetReq = 'req';
  static const budgetTok = 'tok';
  static const turnMessages = 'Messages';
  static const turnExtraCalls = 'Extra calls';
  static const turnTtft = 'First token';
  static const turnExtraNote =
      'Extra calls: other models, embeddings, searches and page fetches.';
  static const errors = 'Errors';
  static const recentCalls = 'Recent calls';
  static const showMore = 'Show more';
  static const showLess = 'Show less';
  static const detailTtft = 'Time to first token';
  static const detailTokens = 'Tokens in / out';
  static const detailLastCall = 'Last call';
  static const detailLatency = 'Latency p50 / p95';
  static const detailErrors = 'Errors';
  static const detailLastError = 'Last error';
  static const detailCooldown = 'Cooling down';
  static const detailNever = 'Never';
  static const tokensLeft = 'tokens left';
  static const requestsLeft = 'requests left';
  static const resetsIn = 'resets in';
  static const ago = 'ago';
  static const calls = 'calls';
  static const today = 'Today';
  static const inWindow = 'In range';
  static const system = 'System and background';
  static const noStatus = 'no status';
}

abstract final class AboutCopy {
  static const title = 'About';
  static const whatItDoes = 'What it does';
  static const privacy = 'Privacy';
  static const backend = 'Backend';
  static const credits = 'Credits';
  static const licenses = 'Open-source licenses';
  static const feedback = 'Send feedback';
  static const status = 'Status';
  static const urlHint = 'Backend URL, tap to copy';
}

/// Sentence-case copy of the GitHub connect panels.
abstract final class ConnectCopy {
  static const enterCode = 'Enter this code on GitHub';
  static const openGithub = 'Open GitHub';
  static const waiting = 'Waiting for approval…';
  static const cancel = 'Cancel';
  static const webWaiting = 'Waiting for GitHub…';
  static const openAgain = 'Open again';
  static const useCode = 'Use a code instead';
}

abstract final class DocsCopy {
  static const title = 'Documents';
  static const searchHint = 'Search documents';
  static const noMatches = 'No documents match';
  static const noMatchesHint = 'Try another word or clear the search.';
  static const writing = 'Writing';
  static const planning = 'Planning';
  static const failed = 'Failed';
  static const stopped = 'Stopped';
  static const outline = 'Outline ready';
  static const untitled = 'Untitled document';
  static const empty = 'No documents yet. Ask for one in a chat.';
  static const loadFailed = 'Could not load your documents.';
  static const retry = 'Retry';

  static String sections(int n) => n == 1 ? '1 section' : '$n sections';
}

abstract final class DocsListSizes {
  static const progressHeight = 2.0;
  static const searchHeight = 48.0;
}
