import 'package:hugeicons/hugeicons.dart';

import 'app_icons.dart';

/// App updates (OTA): copy, icons, sizes, timings and preference keys for the
/// update sheet, the blocking screen, Settings → About and the owner's
/// Releases screen.

abstract final class UpdateConfig {
  /// First check after a cold start, so it never competes with the first frame.
  static const startDelay = Duration(seconds: 3);

  /// A resume checks again when the last check is older than this.
  static const resumeAfter = Duration(hours: 6);

  /// A status older than this is re-checked when About opens.
  static const freshFor = Duration(minutes: 2);

  /// The app is open this long before a sheet may appear.
  static const calmAfter = Duration(seconds: 20);
  static const calmPoll = Duration(seconds: 5);

  /// "Later" on the sheet: first reminder after, second after, then never.
  static const firstReminder = Duration(days: 3);
  static const secondReminder = Duration(days: 7);

  /// The sheet shows at most this many times for one version.
  static const maxPrompts = 3;

  /// Flutter's `--split-per-abi` adds this to the version code (arm64).
  static const abiOffset = 2000;

  static const requestTimeout = Duration(seconds: 20);

  /// A running download gives up when the connection stalls this long.
  static const downloadStall = Duration(seconds: 30);

  static const dirName = 'updates';
  static const channel = 'sparky/updater';

  /// Progress is reported at this granularity (1%).
  static const progressStep = 0.01;

  static const maxNotes = 6;
  static const apkMime = 'application/vnd.android.package-archive';

  // ---- resumable download ------------------------------------------------

  /// A presigned link older than this is replaced before it can expire (1 h).
  static const urlMaxAge = Duration(minutes: 50);

  /// Waits between retries after a network error; the list length is the
  /// number of retries.
  static const retryBackoff = [
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 16),
    Duration(seconds: 32),
  ];

  // ---- install health events -----------------------------------------------

  /// Offline queue bound; the oldest events are dropped first.
  static const eventQueueMax = 100;

  /// Events per request (the server accepts 50).
  static const eventBatch = 50;

  /// Queued events older than this are dropped.
  static const eventMaxAge = Duration(days: 7);

  /// `x-app-build` request header.
  static const buildHeader = 'x-app-build';
}

abstract final class UpdatePrefs {
  static const lastCheckAt = 'ota.lastCheckAt';
  static const promptedBuild = 'ota.promptedBuild';
  static const promptCount = 'ota.promptCount';
  static const nextPromptAt = 'ota.nextPromptAt';
  static const notifiedBuild = 'ota.notifiedBuild';
  static const wifiOnly = 'ota.wifiOnly';
  static const downloaded = 'ota.downloaded';

  /// JSON of the partial download in progress (build, etag, url, urlAt).
  static const partial = 'ota.partial';

  /// JSON list of install events waiting to be sent.
  static const events = 'ota.events';

  /// Random per-install id sent with events (not a hardware id).
  static const deviceId = 'ota.deviceId';

  /// The build that was running at the last launch.
  static const lastBuild = 'ota.lastBuild';

  /// `<from>|<to>` of an install handed to the system and not yet confirmed.
  static const pending = 'ota.pending';
}

abstract final class UpdateIcons {
  static const update = HugeIcons.strokeRoundedDownload04;
  static const rocket = HugeIcons.strokeRoundedRocket01;
  static const shield = HugeIcons.strokeRoundedShield01;
  static const wifi = HugeIcons.strokeRoundedWifi01;
  static const check = AppIcons.check;
  static const refresh = AppIcons.retry;
  static const alert = HugeIcons.strokeRoundedAlert02;
  static const upload = HugeIcons.strokeRoundedCloudUpload;
  static const releases = HugeIcons.strokeRoundedPackage;
  static const edit = AppIcons.edit;
  static const delete = AppIcons.delete;
  static const goLive = HugeIcons.strokeRoundedPlayCircle;
  static const pull = HugeIcons.strokeRoundedPauseCircle;
  static const chevron = AppIcons.chevronRight;
}

abstract final class UpdateSizes {
  static const dot = 8.0;
  static const progressHeight = 6.0;
  static const bulletIcon = 16.0;
  static const bulletGap = 10.0;
  static const heroCircle = 72.0;
  static const heroIcon = 32.0;
  static const maxWidth = 480.0;
  static const spinner = 18.0;
  static const spinnerStroke = 2.0;
  static const noteLines = 3;
  static const notesFieldLines = 6;
  static const titleMax = 80;
  static const noteMax = 120;
  static const adoptionBar = 6.0;
  static const highlightAlpha = 0.10;
}

abstract final class UpdateStrings {
  // ---- sheet -----------------------------------------------------------
  static const kickerFeature = 'UPDATE READY';
  static const kickerMajor = 'BIG UPDATE';
  static const later = 'Later';
  static const update = 'Update';
  static const hide = 'Hide';
  static const tryAgain = 'Try again';
  static const fallbackTitle = 'A new version of sparky is ready';
  static String versionLine(String version, String size) =>
      size.isEmpty ? 'Version $version' : 'Version $version · $size';

  // ---- progress --------------------------------------------------------
  static String downloading(int percent) => 'Getting the update… $percent%';
  static const installing = 'Installing… sparky will restart in a moment.';

  // ---- permission step ---------------------------------------------------
  static const permissionTitle = 'One quick permission';
  static const permissionBody =
      'Android needs your OK before sparky can install its own updates. '
      'On the next screen, switch on "Allow from this source", then come '
      'back and we will finish up.';
  static const permissionOpen = 'Open settings';
  static const notNow = 'Not now';

  // ---- failures --------------------------------------------------------
  static const failNetwork =
      "Couldn't download the update. Check your connection and try again.";
  static const failVerify =
      "The download didn't come through cleanly. Let's try again.";
  static const failSignature =
      "This update didn't pass the safety check, so it was not installed.";
  static const failInstall =
      "The update couldn't be installed. Please try again.";

  // ---- blocking screen -----------------------------------------------------
  static const requiredTitle = 'Time to update';
  static const requiredBody =
      'This version of sparky is out of date and can no longer connect. '
      'A quick update gets you back to your chats.';
  static const requiredCritical =
      'We fixed something important in this version. '
      'Please update to keep using sparky.';

  // ---- notification --------------------------------------------------------
  static const notifyTitle = 'A new sparky is ready';
  static String notifyBody(String title) =>
      title.isEmpty ? 'Open the app to update.' : title;
  static const channelName = 'App updates';
  static const channelInfo =
      'A quiet note when a new version of sparky is ready to install.';
  static const notifyLabel = 'App updates';
  static const notifyHelp = 'Tell me once when a new version of sparky is out.';

  // ---- Settings → About --------------------------------------------------------
  static const section = 'Updates';
  static const rowTitle = 'Status';
  static const statusUnknown = 'Not checked yet';
  static const statusUpToDate = "You're up to date";
  static const statusChecking = 'Checking…';
  static String statusAvailable(String v) => 'Version $v is available';
  static String statusReady(String v) => 'Version $v is ready to install';
  static String statusDownloading(int percent) => 'Downloading… $percent%';
  static const statusInstalling = 'Installing…';
  static const check = 'Check for updates';
  static const checkHint = 'Look for a newer version of sparky';
  static const checkFailed = "Couldn't check right now. Try again later.";
  static const wifiOnly = 'Download on Wi-Fi only';
  static const wifiOnlyHint = 'Small updates download in the background';

  // ---- owner: Releases -----------------------------------------------------------
  static const releasesTitle = 'Releases';
  static const releasesSummary = 'Ship and manage app updates';
  static const releasesEmptyTitle = 'No releases yet';
  static const releasesEmptyHint = 'Upload an APK to publish the first one.';
  static const releasesError = "Couldn't load releases.";
  static const retry = 'Retry';
  static const uploadApk = 'Upload APK';
  static const adoptionHeader = 'In use';
  static const releasesHeader = 'Releases';
  static String users(int n) => n == 1 ? '1 user' : '$n users';
  static String buildLine(String version, int build) =>
      'v$version · build $build';
  static const noMin = 'No minimum';
  static String minLine(int build) => 'Min build $build';
  static const goLive = 'Go live';
  static const pull = 'Pull';
  static const edit = 'Edit';
  static const delete = 'Delete';
  static const goLiveDone = 'Release is live';
  static const pullDone = 'Release pulled';
  static const saved = 'Saved';
  static const deleted = 'Release deleted';
  static const actionFailed = 'That did not work. Try again.';
  static const confirmPullTitle = 'Pull this release?';
  static const confirmPullBody =
      'It disappears from update checks right away. People who already '
      'installed it keep it.';
  static const confirmDeleteTitle = 'Delete this release?';
  static const confirmDeleteBody =
      'The APK is removed from storage. This cannot be undone.';
  static const cancel = 'Cancel';
  static const save = 'Save';

  // ---- owner: install outcomes ---------------------------------------------------
  static const installsHeader = 'INSTALLS';
  static const installsNone = 'No install attempts reported yet';
  static String installsLine(int ok, int failed, int? percent) =>
      '$ok installed · $failed failed${percent == null ? '' : ' · $percent% success'}';
  static String stageLine(String label, int n) => '$label $n';
  static const stageLabels = {
    'download_start': 'started',
    'download_ok': 'downloaded',
    'download_fail': 'download failed',
    'verify_fail': 'bad checksum',
    'signature_mismatch': 'wrong signature',
    'install_start': 'install tapped',
    'install_ok': 'installed',
    'install_fail': 'install failed',
    'cancelled': 'cancelled',
    'first_launch_ok': 'opened after update',
  };

  static const statusDraft = 'DRAFT';
  static const statusLive = 'LIVE';
  static const statusPulled = 'PULLED';

  static const kindPatch = 'PATCH';
  static const kindFeature = 'FEATURE';
  static const kindMajor = 'MAJOR';
  static const kindCritical = 'CRITICAL';

  // edit / upload form
  static const editTitle = 'Edit release';
  static const uploadTitle = 'New release';
  static const fieldVersion = 'Version';
  static const fieldVersionHint = '1.7.0';
  static const fieldBuild = 'Build';
  static const fieldBuildHint = '23';
  static const fieldKind = 'Kind';
  static const fieldTitle = 'Title';
  static const fieldNotes = 'Highlights (one per line, up to 6)';
  static const fieldMin = 'Minimum supported build (optional)';
  static const goLiveNow = 'Publish right away';
  static const pickApk = 'Choose APK';
  static const noFile = 'No file chosen';
  static const uploading = 'Uploading…';
  static String uploadingPercent(int p) => 'Uploading… $p%';
  static const needFile = 'Choose an APK first.';
  static const needVersion = 'Add a version and a build number.';
  static const buildExists = 'A release with that build already exists.';
  static const uploadFailed = "Couldn't upload. Check the file and try again.";
}
