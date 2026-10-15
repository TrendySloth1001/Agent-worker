import 'package:hugeicons/hugeicons.dart';

/// Owner-only Recovery vault: the server's master key (DATA_KEY), kept behind
/// the owner's password. Limits, copy, icons and sizes for Settings → Developer.

abstract final class VaultConfig {
  /// The revealed key hides itself after this long.
  static const autoHide = Duration(seconds: 30);

  /// The clipboard is cleared this long after a copy (if it still holds the key).
  static const clipboardClear = Duration(seconds: 60);

  static const requestTimeout = Duration(seconds: 30);

  /// Platform channel that toggles Android's FLAG_SECURE (no screenshots).
  static const secureChannel = 'sparky/secure_screen';

  static const fileName = 'sparky-data-key.txt';
  static const fileMime = 'text/plain';
}

abstract final class VaultStrings {
  static const entryTitle = 'Recovery vault';
  static const entrySummary = 'Owner only: the server key';
  static const screenTitle = 'Recovery vault';

  static const explain =
      'This key unlocks everyone’s encrypted data. Keep a copy in a '
      'password manager. If it’s lost, encrypted data can’t be recovered.';

  static const statusHeader = 'Status';
  static const sealed = 'Sealed';
  static const sealedHint = 'Stored encrypted. Needs your password to open.';
  static const notSetUp = 'Not set up';
  static const notSetUpHint =
      'Nothing is stored yet. Set it up to keep a backup copy.';
  static const needsReseal = 'Needs re-seal';
  static const needsResealHint =
      'Your password changed since the vault was sealed. Set it up again.';
  static const updated = 'Last sealed';

  static const setUp = 'Set up vault';
  static const reSeal = 'Seal again';
  static const reveal = 'Reveal key';

  static const noPasswordTitle = 'Set a password first';
  static const noPasswordHint =
      'The vault is locked with your sparky password. Your account signs in '
      'without one, so add one in Profile, then come back.';

  // Password sheet
  static const sheetKicker = 'Confirm it’s you';
  static const sheetSetUpTitle = 'Seal the key';
  static const sheetRevealTitle = 'Reveal the key';
  static const sheetBody = 'Enter your sparky password.';
  static const passwordLabel = 'Password';
  static const showPassword = 'Show password';
  static const hidePassword = 'Hide password';

  // Revealed key
  static const keyHeader = 'Server key';
  static const tapToShow = 'Tap to show';
  static const hidesIn = 'Hides in';
  static String seconds(int s) => '${s}s';
  static const copy = 'Copy';
  static const copied = 'Copied. Clears from the clipboard in 60 s.';
  static const saveFile = 'Save as file';
  static const hide = 'Hide';

  // Results and errors
  static const sealedDone = 'Vault sealed.';
  static const loadFailed = 'Couldn’t load the vault.';
  static const retry = 'Try again';
  static const wrongPassword = 'That password is wrong.';
  static const locked = 'Too many wrong passwords. Try again in 15 minutes.';
  static const needsResealError =
      'Set up the vault again with your new password.';
  static const generic = 'Something went wrong. Try again.';
  static const notOwner = 'Only the owner can open the vault.';
}

abstract final class VaultIcons {
  static const entry = HugeIcons.strokeRoundedLockKey;
  static const sealed = HugeIcons.strokeRoundedSquareLock02;
  static const notSetUp = HugeIcons.strokeRoundedSquareLock01;
  static const needsReseal = HugeIcons.strokeRoundedAlertDiamond;
  static const show = HugeIcons.strokeRoundedView;
  static const hide = HugeIcons.strokeRoundedViewOff;
  static const copy = HugeIcons.strokeRoundedCopy01;
  static const save = HugeIcons.strokeRoundedFileDownload;
  static const key = HugeIcons.strokeRoundedKey01;
}

abstract final class VaultSizes {
  /// Blur applied to the key until it is tapped.
  static const blurSigma = 8.0;
  static const keyBoxPadding = 16.0;
  static const keyBoxMinHeight = 72.0;
  static const buttonGap = 12.0;
}

/// Status of the vault as the server reports it.
enum VaultState { notSetUp, sealed, needsReseal }
