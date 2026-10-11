import 'package:hugeicons/hugeicons.dart';

import 'app_icons.dart';

/// "Continue with GitHub / Google": sign-in buttons, the GitHub device-code
/// sheet and the linked sign-in methods on Profile.

/// Provider ids as the backend names them.
abstract final class SsoProviderIds {
  static const github = 'github';
  static const google = 'google';
}

/// Backend error codes the UI reacts to.
abstract final class SsoCodes {
  static const emailInUse = 'email_in_use_link_from_profile';
  static const passwordNotSet = 'password_not_set';
  static const lastMethod = 'last_sign_in_method';
  static const identityInUse = 'identity_in_use';
}

/// Poll states of `POST /auth/github/device/:id/poll`.
abstract final class SsoFlowStatus {
  static const pending = 'pending';
  static const slowDown = 'slow_down';
  static const ok = 'ok';
  static const expired = 'expired';
  static const denied = 'denied';
  static const error = 'error';
}

abstract final class SsoStrings {
  static const or = 'OR';
  static const github = 'CONTINUE WITH GITHUB';
  static const google = 'CONTINUE WITH GOOGLE';

  // GitHub device-code sheet.
  static const sheetTitle = 'Continue with GitHub';
  static const linkTitle = 'Link GitHub';
  static const starting = 'GETTING A CODE…';
  static const signingIn = 'SIGNING IN…';
  static const expired = 'The code expired before it was approved.';
  static const denied = 'Access was denied on GitHub.';
  static const failed = 'Could not sign in with GitHub.';
  static const retry = 'TRY AGAIN';
  static const close = 'CLOSE';

  // Google.
  static const googleFailed = 'Could not sign in with Google.';
  static const googleNoToken = 'Google did not return an ID token.';
  static const googleMisconfigured =
      'Google sign-in is not set up correctly for this app build '
      '(Android OAuth client: package name and SHA-1).';
  static const googleUnavailable =
      'Google sign-in is not available on this device.';
  static const googleNoAccount =
      'No Google account is available. Add one in Android settings, '
      'or check the app\'s Google Cloud setup (package name and SHA-1).';

  // Profile.
  static const methods = 'SIGN-IN METHODS';
  static const emailPassword = 'Email & password';
  static const githubLabel = 'GitHub';
  static const googleLabel = 'Google';
  static const passwordOn = 'ON';
  static const passwordOff = 'NOT SET';
  static const link = 'LINK';
  static const unlink = 'UNLINK';
  static const onlyMethod = 'ONLY WAY IN';
  static const linked = 'Linked.';
  static const unlinked = 'Unlinked.';
  static String unlinkTitle(String provider) => 'Unlink $provider?';
  static String unlinkBody(String provider) =>
      'You will no longer be able to sign in with $provider. '
      'Your other sign-in methods stay.';
  static const keep = 'KEEP';
  static const setPassword = 'SET PASSWORD';
  static const passwordSet = 'Password set. You can now sign in with email.';
  static const setPasswordHint =
      'Add a password to also sign in with your email.';
  static const methodsFailed = 'Could not load your sign-in methods.';
  static String account(String login) => '@$login';
}

/// Native "Sign in with Google" (MainActivity, Credential Manager).
abstract final class GoogleAuthChannel {
  static const name = 'app/auth';
  static const idToken = 'googleIdToken';
  static const signOut = 'googleSignOut';
  static const modeButton = 'button';
  static const modeAuto = 'auto';

  // Error codes from the platform side.
  static const cancelled = 'cancelled';
  static const noAccount = 'no_account';
}

/// One-tap GitHub (OAuth web flow): the app opens GitHub's authorize page
/// (in the GitHub app when it handles it, else the browser), the backend's
/// callback sends the browser to `sparky://auth/github?ticket&mode&state`,
/// and the app redeems the ticket.
abstract final class GithubWeb {
  static const signin = 'signin';
  static const connect = 'connect';
  static const link = 'link';

  // Deep link sparky://auth/github (AndroidManifest intent-filter).
  static const scheme = 'sparky';
  static const host = 'auth';
  static const path = '/github';
  static const ticket = 'ticket';
  static const mode = 'mode';
  static const state = 'state';
  static const error = 'error';
  static const message = 'message';

  /// Backend error codes in the deep link.
  static const errDenied = 'access_denied';

  /// Opened here when it can handle the authorize URL.
  static const githubAppPackage = 'com.github.android';
}

/// MainActivity's deep-link bridge.
abstract final class DeepLinkChannel {
  static const name = 'app/links';
  static const initialLink = 'initialLink';
  static const onLink = 'onLink';
}

abstract final class GithubWebStrings {
  static const opening = 'OPENING GITHUB…';
  static const waiting = 'WAITING FOR GITHUB…';
  static const finishing = 'FINISHING…';
  static const inApp =
      'Opened in the GitHub app. Approve there and you '
      'will come right back.';
  static const inBrowser =
      'Opened in your browser. Approve on GitHub and '
      'you will come right back.';
  static const openAgain = 'OPEN AGAIN';
  static const useCode = 'USE A CODE INSTEAD';
  static const cancel = 'CANCEL';
  static const openFailed = 'Could not open GitHub. Use a code instead.';
  static const failed = 'Could not finish with GitHub.';
  static const denied = 'Access was denied on GitHub.';
  static const signedIn = 'Signed in with GitHub.';
  static const connected = 'GitHub connected.';
  static const linked = 'GitHub linked.';
}

abstract final class GithubWebDurations {
  /// A pending flow older than this is forgotten (the server's is 10 min).
  static const pendingTtl = Duration(minutes: 15);
}

abstract final class SsoAssets {
  static const githubMark = 'assets/brand/sso/github_mark.svg';
  static const googleG = 'assets/brand/sso/google_g.svg';
}

abstract final class SsoIcons {
  static const password = HugeIcons.strokeRoundedSquareLock02;
  static const unlink = HugeIcons.strokeRoundedUnlink01;
  static const link = AppIcons.link;
  static const methods = HugeIcons.strokeRoundedKey01;
}

abstract final class SsoSizes {
  /// Brand mark inside a sign-in button.
  static const mark = 18.0;

  /// Brand mark on a Profile row.
  static const rowMark = 20.0;
  static const dividerGap = 12.0;

  /// Opacity of a sign-in button's contents while disabled.
  static const disabledAlpha = 0.4;
}

abstract final class SsoDurations {
  static const request = Duration(seconds: 20);
}
