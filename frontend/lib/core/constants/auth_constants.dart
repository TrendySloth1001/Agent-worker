import 'package:hugeicons/hugeicons.dart';

/// Accounts: sign-in, sign-up and the profile screen.
abstract final class AuthStrings {
  static const brand = 'sparky';
  static const tagline = 'Your engineering sidekick.';
  static const loginTitle = 'SIGN IN';
  static const loginSubtitle = 'Welcome back to sparky.';
  static const registerTitle = 'CREATE ACCOUNT';
  static const registerSubtitle = 'Make a sparky account. It takes a minute.';
  static const name = 'NAME';
  static const nameHint = 'Your name';
  static const email = 'EMAIL';
  static const emailHint = 'you@example.com';
  static const password = 'PASSWORD';
  static const passwordHint = 'At least 8 characters';
  static const confirm = 'CONFIRM PASSWORD';
  static const confirmHint = 'Type it again';
  static const show = 'Show password';
  static const hide = 'Hide password';
  static const signIn = 'SIGN IN';
  static const createAccount = 'CREATE ACCOUNT';
  static const noAccount = 'New to sparky?';
  static const toRegister = 'CREATE ACCOUNT';
  static const haveAccount = 'Already have an account?';
  static const toLogin = 'SIGN IN';
  static const restoring = 'SIGNING IN';

  static const errEmail = 'Enter a valid email.';
  static const errPassword = 'Enter your password.';
  static const errPasswordShort = 'Use at least 8 characters.';
  static const errConfirm = 'Passwords do not match.';
  static const errName = 'Enter your name.';
  static const errNetwork = 'Cannot reach the server. Check your connection.';
  static const sessionExpired = 'Your session expired. Sign in again.';

  static const strengthWeak = 'WEAK';
  static const strengthOk = 'OK';
  static const strengthStrong = 'STRONG';
  static const strengthHint =
      'Longer is stronger: mix words, numbers, symbols.';
}

abstract final class ProfileStrings {
  static const title = 'PROFILE';
  static const openProfile = 'Open profile';
  static const owner = 'OWNER';
  static const account = 'ACCOUNT';
  static const name = 'NAME';
  static const save = 'SAVE';
  static const saved = 'Saved';
  static const changePhoto = 'CHANGE PHOTO';
  static const removePhoto = 'REMOVE PHOTO';
  static const photoFailed = 'Could not update the photo.';
  static const usage = 'TODAY';
  static const unlimited = 'UNLIMITED';
  static const chats = 'Chat requests';
  static const tables = 'Round Table runs';
  static const uploads = 'Uploads';
  static const storage = 'Storage';
  static const resets = 'Resets at';
  static const security = 'SECURITY';
  static const changePassword = 'CHANGE PASSWORD';
  static const currentPassword = 'CURRENT PASSWORD';
  static const newPassword = 'NEW PASSWORD';
  static const passwordChanged =
      'Password changed. Other devices were signed out.';
  static const sessions = 'DEVICES';
  static const thisDevice = 'THIS DEVICE';
  static const signOutDevice = 'SIGN OUT';
  static const unknownDevice = 'Unknown device';
  static const lastActive = 'Active';
  static const logOut = 'LOG OUT';
  static const logOutConfirm = 'Log out of sparky on this device?';
  static const deleteAccount = 'DELETE ACCOUNT';
  static const deleteWarning =
      'This permanently deletes your account, chats, knowledge base and files. '
      'It cannot be undone.';
  static const deleteTypeHint = 'Type DELETE to confirm';
  static const deleteWord = 'DELETE';
  static const deletePassword = 'Your password';
  static const ownerCannotDelete = 'The owner account cannot be deleted.';
  static const cancel = 'CANCEL';
  static const confirm = 'CONFIRM';
  static const loadFailed = 'Could not load your profile.';
  static const retry = 'RETRY';
}

abstract final class AuthSizes {
  static const formMaxWidth = 420.0;
  static const fieldHeight = 52.0;
  static const avatarDrawer = 40.0;
  static const avatarProfile = 72.0;
  static const avatarUploadPx = 256;
  static const avatarQuality = 80;
  static const strengthSegments = 3;
  static const strengthBar = 3.0;
  static const minPassword = 8;
  static const nameMax = 60;
  static const splashProgress = 120.0;
}

abstract final class AuthDurations {
  static const request = Duration(seconds: 20);

  /// Refresh the access token when it has less than this left.
  static const refreshSkew = Duration(seconds: 60);
}

/// Secure-storage keys.
abstract final class AuthKeys {
  static const refreshToken = 'auth_refresh_token';
  static const user = 'auth_user';
}

abstract final class AuthIcons {
  static const email = HugeIcons.strokeRoundedMail01;
  static const password = HugeIcons.strokeRoundedSquareLock02;
  static const name = HugeIcons.strokeRoundedUser;
  static const show = HugeIcons.strokeRoundedView;
  static const hide = HugeIcons.strokeRoundedViewOffSlash;
  static const device = HugeIcons.strokeRoundedSmartPhone01;
  static const logOut = HugeIcons.strokeRoundedLogout03;
  static const delete = HugeIcons.strokeRoundedDelete02;
  static const security = HugeIcons.strokeRoundedLockPassword;
  static const account = HugeIcons.strokeRoundedUserCircle;
  static const usage = HugeIcons.strokeRoundedActivity01;
  static const photo = HugeIcons.strokeRoundedCamera01;
}
