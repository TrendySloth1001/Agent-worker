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
