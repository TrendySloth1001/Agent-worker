import 'package:hugeicons/hugeicons.dart';

import 'app_icons.dart';

/// Long-term memory (Settings → MEMORY): what the assistant remembers about
/// the user across chats, editable, with an on/off switch.

abstract final class MemoryStrings {
  static const section = 'MEMORY';
  static const title = 'MEMORY';
  static const toggle = 'REMEMBER THINGS ABOUT ME';
  static const toggleHint =
      'Sparky saves lasting facts and preferences from your chats and uses '
      'them in new ones. You can also say "remember ..." or "forget ...".';
  static const entry = 'WHAT SPARKY REMEMBERS';
  static const searchHint = 'Search memories';
  static const addHint = 'Something to remember';
  static const add = 'ADD';
  static const addTitle = 'ADD A MEMORY';
  static const editTitle = 'EDIT MEMORY';
  static const pinned = 'PINNED';
  static const pin = 'PIN';
  static const unpin = 'UNPIN';
  static const edit = 'EDIT';
  static const delete = 'DELETE';
  static const clearAll = 'CLEAR ALL';
  static const clearTitle = 'CLEAR ALL MEMORY?';
  static const clearBody =
      'Everything Sparky remembers about you is deleted for good. '
      'Your chats are not affected.';
  static const empty = 'NOTHING REMEMBERED YET';
  static const emptyHint =
      'Facts and preferences from your chats show up here. '
      'Try: "Remember that I use Neovim".';
  static const emptyOff = 'MEMORY IS OFF';
  static const emptyOffHint = 'Turn it on above to let Sparky remember.';
  static const noMatch = 'NO MATCHING MEMORIES';
  static const loadFailed = 'Could not load your memories.';
  static const saveFailed = 'Could not save. Try again.';
  static const deleteFailed = 'Could not delete. Try again.';
  static const deleted = 'Memory deleted.';
  static const cleared = 'Memory cleared.';
  static const updatedChip = 'MEMORY UPDATED';
  static const forgotChip = 'MEMORY FORGOTTEN';
  static const separator = ' · ';
  static String count(int n) => n == 1 ? '1 MEMORY' : '$n MEMORIES';

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
