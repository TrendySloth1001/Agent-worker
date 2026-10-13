/// Friendly copy for the line shown while a reply is on its way. Never an
/// error and never a raw model id.
abstract final class WaitStrings {
  static const picking = 'Picking the best model…';
  static String goingWith(String name) => 'Going with $name';
  static String switchingTo(String name) => 'Switching to $name…';
  static const switching = 'Switching models…';

  static const searching = 'Searching the web…';
  static const readingFiles = 'Reading your files…';
  static const lookingAtImage = 'Looking at the image…';
  static const checkingNotes = 'Checking your notes…';
  static const roundTable = 'Gathering the round table…';
  static const queued = 'In line, one moment…';
  static const reconnecting = 'Reconnecting…';

  /// Server phase to copy. `generating` (and anything unknown) has no line
  /// of its own: the playful word shows instead.
  static const phases = <String, String>{
    'processing_files': readingFiles,
    'analyzing_image': lookingAtImage,
    'retrieving': checkingNotes,
    'searching': searching,
    'round_table': roundTable,
    'queued': queued,
  };

  /// Most candidate logos shown while picking.
  static const maxLogos = 3;
}

/// The sheet opened by tapping the model label of a reply.
abstract final class ModelInfoStrings {
  static const title = 'ABOUT THIS MODEL';
  static const madeBy = 'MADE BY';
  static const goodAt = 'GOOD AT';
  static const memory = 'MEMORY';
  static const feel = 'FEEL';
  static const thisReply = 'THIS REPLY';
  static const modelId = 'MODEL ID';
  static const tokens = 'TOKENS';
  static const time = 'TIME';
  static const noInfo = 'No details about this model yet.';
  static const openHint = 'About this model';

  static const speeds = <String, String>{
    'fast': 'Quick replies',
    'balanced': 'Balanced speed and depth',
    'deep': 'Slower, more thorough',
  };

  /// Plain words for a context window, e.g. "About 90 pages of text".
  static String memoryOf(int tokens) {
    // About 0.75 words per token, 300 words per page.
    final pages = (tokens * 0.75 / 300).round();
    final pageText = pages >= 1000
        ? '${(pages / 1000).toStringAsFixed(pages % 1000 == 0 ? 0 : 1)}k'
        : '$pages';
    return 'Remembers about $pageText pages of chat';
  }
}
