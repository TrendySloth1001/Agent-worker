/// Shared copy and sizes for confirm sheets and the sheets that follow
/// their visual language (illustration, mono kicker, headline, body).
abstract final class ConfirmCopy {
  static const cancel = 'Cancel';
  static const keep = 'Keep it';
  static const notNow = 'Not now';
  static const delete = 'Delete';
  static const remove = 'Remove';
  static const choose = 'Choose one';

  // Kickers (mono, red).
  static const kickerDelete = 'DELETE';
  static const kickerRemove = 'REMOVE';
  static const kickerUnlink = 'UNLINK';
  static const kickerDisconnect = 'DISCONNECT';
  static const kickerReset = 'RESET';
  static const kickerMerge = 'MERGE';
  static const kickerClose = 'CLOSE';
  static const kickerMic = 'MICROPHONE';
  static const kickerConfirm = 'CONFIRM';
  static const kickerPassword = 'PASSWORD';
  static const kickerKey = 'API KEY';
  static const kickerAccount = 'DELETE ACCOUNT';
  static const kickerEdit = 'EDIT';
  static const kickerRename = 'RENAME';

  // Delete-all-chats sheet.
  static const wiping = 'Clearing your chats...';
}

abstract final class ConfirmSizes {
  /// Illustration height on confirm sheets.
  static const illustration = 150.0;

  /// Smaller illustration for sheets that also hold fields.
  static const formIllustration = 110.0;

  /// Spinner in a progress sheet.
  static const spinner = 22.0;
}
