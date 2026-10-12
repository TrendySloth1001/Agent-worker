import 'package:hugeicons/hugeicons.dart';

import 'app_icons.dart';

/// Long-term memory (Settings → MEMORY): what the assistant remembers about
/// the user across chats, editable, with an on/off switch.

abstract final class MemoryStrings {
  static const section = 'MEMORY';
  static const title = 'Memory';
  static const toggle = 'Remember things about me';
  static const toggleHint =
      'Sparky saves lasting facts and preferences from your chats and uses '
      'them in new ones. You can also say “remember …” or “forget …”.';
  static const recallToggle = 'Recall past chats';
  static const recallHint =
      'Lets Sparky look through your other chats when you ask “did we talk '
      'about this before?” or when one is clearly related. Only your own '
      'chats are searched. Turning it off removes the search index.';
  static const entry = 'WHAT SPARKY REMEMBERS';
  static const searchHint = 'Search memories';
  static const addHint = 'Something to remember';
  static const add = 'Add';
  static const addTitle = 'Add a memory';
  static const editTitle = 'Edit memory';
  static const pinned = 'Pinned';
  static const pin = 'Pin';
  static const unpin = 'Unpin';
  static const edit = 'Edit';
  static const delete = 'Delete';
  static const clearAll = 'Clear all';
  static const clearTitle = 'Clear all memory?';
  static const clearBody =
      'Everything Sparky remembers about you is deleted for good. '
      'Your chats are not affected.';
  static const empty = 'Nothing remembered yet';
  static const emptyHint =
      'Facts and preferences from your chats show up here. '
      'Try: “Remember that I use Neovim”.';
  static const emptyOff = 'Memory is off';
  static const emptyOffHint = 'Turn it on above to let Sparky remember.';
  static const noMatch = 'No matching memories';
  static const loadFailed = 'Could not load your memories.';
  static const saveFailed = 'Could not save. Try again.';
  static const deleteFailed = 'Could not delete. Try again.';
  static const deleted = 'Memory deleted.';
  static const cleared = 'Memory cleared.';
  static const updatedChip = 'MEMORY UPDATED';
  static const forgotChip = 'MEMORY FORGOTTEN';
  static const separator = ' · ';
  static String count(int n) => n == 1 ? '1 memory' : '$n memories';

  /// Label per kind id the backend uses.
  static String kind(String id) => switch (id) {
    'preference' => 'PREFERENCE',
    'project' => 'PROJECT',
    'instruction' => 'INSTRUCTION',
    _ => 'FACT',
  };
}

abstract final class MemoryIcons {
  static const section = HugeIcons.strokeRoundedBrain02;
  static const chip = HugeIcons.strokeRoundedBrain02;
  static const pin = AppIcons.pin;
  static const unpin = AppIcons.unpin;
  static const edit = AppIcons.edit;
  static const delete = AppIcons.delete;
  static const add = AppIcons.add;
  static const empty = HugeIcons.strokeRoundedBrain02;
}

abstract final class MemorySizes {
  static const maxTextLength = 300;
  static const textLines = 4;
}

abstract final class MemoryConfig {
  /// Wait after the last keystroke before searching.
  static const searchDebounce = Duration(milliseconds: 350);
  static const requestTimeout = Duration(seconds: 20);
}
