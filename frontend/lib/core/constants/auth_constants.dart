import 'package:hugeicons/hugeicons.dart';

/// Accounts: sign-in, sign-up and the profile screen.
abstract final class AuthStrings {
  static const brand = 'sparky';
  static const tagline = 'Your engineering sidekick.';
  static const loginTitle = 'Welcome back';
  static const loginSubtitle = 'Sign in to pick up where you left off.';
  static const registerTitle = 'Create your account';
  static const registerSubtitle = 'Your chats, docs and code in one place.';
  static const name = 'Name';
  static const nameHint = 'Your name';
  static const email = 'Email';
  static const emailHint = 'you@example.com';
  static const password = 'Password';
  static const passwordHint = 'At least 8 characters';
  static const newPasswordHint = 'Password (8+ characters)';
  static const confirm = 'Confirm password';
  static const confirmHint = 'Type it again';
  static const show = 'Show password';
  static const hide = 'Hide password';
  static const signIn = 'Sign in';
  static const createAccount = 'Create account';
  static const noAccount = 'New to sparky?';
  static const toRegister = 'Create account';
  static const haveAccount = 'Already have an account?';
  static const toLogin = 'Sign in';
  static const restoring = 'Signing in';
  static const signingIn = 'Signing in…';
  static const creatingAccount = 'Creating account…';
  static const back = 'Back';
  static const capsLock = 'Caps Lock is on.';

  // "Trouble signing in?" (there is no email password reset).
  static const trouble = 'Trouble signing in?';
  static const troubleSubtitle = 'sparky can\'t reset passwords by email yet.';
  static const troubleSso = 'Use GitHub or Google';
  static const troubleSsoDetail =
      'If it uses the same verified email as your account, you go '
      'straight in.';
  static const troubleSupport = 'Email support';
  static const troubleSubject = 'sparky sign-in help';

  static const errEmail = 'Enter a valid email.';
  static const errPassword = 'Enter your password.';
  static const errPasswordShort = 'Use at least 8 characters.';
  static const errConfirm = 'Passwords do not match.';
  static const errName = 'Enter your name.';
  static const errNetwork = 'Cannot reach the server. Check your connection.';
  static const sessionExpired = 'Your session expired. Sign in again.';

  static const strengthWeak = 'Weak';
  static const strengthOk = 'OK';
  static const strengthStrong = 'Strong';
  static const strengthHint =
      'Longer is stronger: mix words, numbers, symbols.';
}

abstract final class ProfileStrings {
  static const title = 'Profile';
  static const openProfile = 'Open profile';
  static const owner = 'Owner';
  static const account = 'Account';
  static const name = 'Name';
  static const save = 'Save';
  static const saved = 'Saved';
  static const changePhoto = 'Change photo';
  static const removePhoto = 'Remove photo';
  static const photoFailed = 'Could not update the photo.';
  static const usage = 'Today';
  static const unlimited = 'Unlimited';
  static const chats = 'Chat requests';
  static const tables = 'Round Table runs';
  static const uploads = 'Uploads';
  static const storage = 'Storage';
  static const resets = 'Resets at';
  static const security = 'Security';
  static const changePassword = 'Change password';
  static const currentPassword = 'Current password';
  static const newPassword = 'New password';
  static const passwordChanged =
      'Password changed. Other devices were signed out.';
  static const sessions = 'Devices';
  static const thisDevice = 'This device';
  static const signOutDevice = 'Sign out';
  static const unknownDevice = 'Unknown device';
  static const lastActive = 'Active';
  static const logOut = 'Log out';
  static const logOutConfirm = 'Log out of sparky on this device?';
  static const deleteAccount = 'Delete account';
  static const deleteWarning =
      'This permanently deletes your account, chats, knowledge base and files. '
      'It cannot be undone.';
  static const deleteTypeHint = 'Type DELETE to confirm';
  static const deleteWord = 'DELETE';
  static const deletePassword = 'Your password';
  static const ownerCannotDelete = 'The owner account cannot be deleted.';
  static const cancel = 'Cancel';
  static const confirm = 'Confirm';
  static const loadFailed = 'Could not load your profile.';
  static const retry = 'Retry';
}

abstract final class AuthSizes {
  static const formMaxWidth = 420.0;
  static const fieldHeight = 52.0;

  /// Sign-in / create-account headline.
  static const headline = 34.0;

  /// Primary and "Continue with" buttons.
  static const buttonHeight = 52.0;

  /// Vertical padding inside a field (with the 16dp body text: ~56dp).
  static const fieldPadV = 16.0;

  /// Spinner inside a loading button.
  static const spinner = 18.0;

  /// Width reserved on each side of a "Continue with" label, so the brand
  /// marks line up and the label stays centered.
  static const ssoSide = 44.0;

  /// Error banner tint over the page.
  static const errorTint = 0.12;
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
  static const capsLock = HugeIcons.strokeRoundedArrowUp02;
  static const help = HugeIcons.strokeRoundedHelpCircle;
  static const sso = HugeIcons.strokeRoundedKey01;
  static const support = HugeIcons.strokeRoundedMail01;
}
