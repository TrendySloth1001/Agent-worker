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

  static const docs = 'docs';
  static const chunks = 'chunks';
}

abstract final class KnowledgeSizes {
  static const progressHeight = 4.0;
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
}
