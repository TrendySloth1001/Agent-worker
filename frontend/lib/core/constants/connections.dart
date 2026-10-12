import 'package:hugeicons/hugeicons.dart';

import 'app_icons.dart';

/// Linked accounts ("Connect your GitHub"): chat widget, Settings section and
/// the device-flow sheet.

/// Fenced language of the connect card.
abstract final class ConnectLang {
  static const githubConnect = 'github-connect';
}

/// Provider ids as the backend names them.
abstract final class ConnectProviders {
  static const github = 'github';
}

/// Backend error codes the UI reacts to.
abstract final class ConnectCodes {
  static const notConfigured = 'github_oauth_not_configured';
  static const notConnected = 'github_not_connected';
}

/// Flow states returned by `GET /connections/github/device/:id`.
abstract final class ConnectFlowStatus {
  static const pending = 'pending';
  static const connected = 'connected';
  static const expired = 'expired';
  static const denied = 'denied';
}

abstract final class ConnectStrings {
  // Chat card.
  static const cardTitle = 'GITHUB';
  static const title = 'Connect GitHub';
  static const pitch =
      'Let Sparky read your repositories, pull requests and issues, '
      'private ones included.';
  static const connect = 'CONNECT';
  static const starting = 'STARTING…';
  static const enterCode = 'ENTER THIS CODE ON GITHUB';
  static const openGithub = 'OPEN GITHUB';
  static const codeCopied = 'Code copied. Paste it on GitHub.';
  static const waiting = 'WAITING FOR APPROVAL…';
  static const cancel = 'CANCEL';
  static const retry = 'TRY AGAIN';

  static const connectedTitle = 'GitHub connected';
  static const authOk = 'Authentication successful';
  static const showRepos = 'SHOW MY REPOSITORIES';
  static const showReposMessage = 'Show my repositories';
  static const disconnect = 'DISCONNECT';
  static const disconnectTitle = 'Disconnect GitHub?';
  static const disconnectBody =
      'Sparky will no longer see your repositories. '
      'You can connect again any time.';
  static const disconnectKeep = 'KEEP';
  static const disconnected = 'GitHub disconnected.';
  static const revokeHint =
      'To revoke access on GitHub too: Settings → Applications → '
      'Authorized OAuth Apps.';
  static const more = 'More';
  static const scopes = 'SCOPES';

  static const expired = 'The code expired before it was approved.';
  static const denied = 'Access was denied on GitHub.';
  static const failed = 'Could not connect GitHub.';
  static const loadFailed = 'Could not load your connections.';

  static const notAvailable = 'GitHub sign-in is not available yet.';
  static const setupTitle = 'Set up GitHub sign-in';
  static const setupIntro =
      'The server has no GitHub OAuth app yet. As the owner, create one once:';
  static const setupSteps = [
    'github.com → Settings → Developer settings → OAuth Apps → New OAuth App.',
    'Any name and homepage URL; the callback URL is not used (any https URL).',
    'Check “Enable Device Flow”, then Register application.',
    'Copy the Client ID into backend/.env as GITHUB_OAUTH_CLIENT_ID and '
        'restart the backend.',
  ];
  static const setupUrl = 'https://github.com/settings/applications/new';
  static const openSetup = 'OPEN GITHUB SETTINGS';

  static String account(String login) => '@$login';
  static String profileUrl(String login) => 'https://github.com/$login';
  static String countdown(int seconds) {
    final s = seconds < 0 ? 0 : seconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  // Settings.
  static const section = 'CONNECTIONS';
  static const github = 'GitHub';
  static const googleDrive = 'Google Drive';
  static const googlePhotos = 'Google Photos';
  static const soon = 'SOON';
  static const connectedAs = 'CONNECTED AS';
  static const notConnected = 'NOT CONNECTED';
  static const unavailable = 'NOT AVAILABLE';
}

abstract final class ConnectIcons {
  static const github = AppIcons.github;
  static const googleDrive = HugeIcons.strokeRoundedGoogleDrive;
  static const googlePhotos = HugeIcons.strokeRoundedImage01;
  static const connect = AppIcons.link;
  static const open = AppIcons.openExternal;
  static const copy = AppIcons.copy;
  static const check = HugeIcons.strokeRoundedCheckmarkCircle02;
  static const more = HugeIcons.strokeRoundedMoreVertical;
  static const disconnect = HugeIcons.strokeRoundedUnlink01;
  static const repos = HugeIcons.strokeRoundedFolderLibrary;
  static const retry = AppIcons.regenerate;
  static const warning = HugeIcons.strokeRoundedAlert02;
  static const chevron = AppIcons.chevronRight;
}

abstract final class ConnectSizes {
  static const pad = 16.0;
  static const markSize = 22.0;
  static const avatar = 40.0;
  static const illustration = 112.0;
  static const codeFont = 30.0;
  static const codeSpacing = 4.0;
  static const codePadV = 14.0;
  static const pulseDot = 6.0;
  static const stepIndex = 18.0;
  static const sheetHandleWidth = 36.0;
  static const sheetHandleHeight = 4.0;
  static const pulseMinAlpha = 0.25;
}

abstract final class ConnectDurations {
  static const request = Duration(seconds: 20);
  static const tick = Duration(seconds: 1);
  static const pulse = Duration(milliseconds: 900);

  /// Fallback poll interval when the server sends none.
  static const defaultInterval = 5;
}
