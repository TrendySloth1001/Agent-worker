import 'package:hugeicons/hugeicons.dart';

import 'app_icons.dart';

/// The Apps hub (connectors) and the GitHub screens.

abstract final class AppsStrings {
  static const title = 'Apps';
  static const sectionConnected = 'Connected';
  static const sectionAvailable = 'Available';
  static const sectionBuiltIn = 'Built in';
  static const sectionSoon = 'Coming soon';
  static const soonFooter =
      'More apps are on their way. They will appear here as soon as they '
      'are ready to connect.';

  static const github = 'GitHub';
  static const githubBlurb = 'Repositories, pull requests and issues';
  static const notConnected = 'Not connected';
  static const loading = 'Checking…';
  static const connected = 'CONNECTED';
  static const connect = 'CONNECT';
  static String account(String login) => '@$login';

  static const knowledge = 'Your knowledge base';
  static const knowledgeBlurb = 'Sources you\'ve added';
  static const memory = 'Memory';
  static const memoryBlurb = 'What Sparky remembers about you';
  static String sources(int n) => n == 1 ? '1 source' : '$n sources';
  static const noSources = 'No sources yet';

  static const soon = 'SOON';
  static const googleDrive = 'Google Drive';
  static const googleDriveBlurb = 'Files and folders';
  static const googlePhotos = 'Google Photos';
  static const googlePhotosBlurb = 'Your photo library';
  static const notion = 'Notion';
  static const notionBlurb = 'Pages and databases';
  static const gmail = 'Gmail';
  static const gmailBlurb = 'Your inbox';
  static const calendar = 'Calendar';
  static const calendarBlurb = 'Events and schedule';
  static const slack = 'Slack';
  static const slackBlurb = 'Channels and messages';
}

/// Registry ids.
abstract final class AppIds {
  static const github = 'github';
  static const knowledge = 'knowledge';
  static const memory = 'memory';
  static const googleDrive = 'google-drive';
  static const googlePhotos = 'google-photos';
  static const notion = 'notion';
  static const gmail = 'gmail';
  static const calendar = 'calendar';
  static const slack = 'slack';
}

abstract final class AppsIcons {
  /// Sidebar footer destination.
  static const hub = HugeIcons.strokeRoundedDashboardSquare01;

  /// Iconify set for brand marks (monochrome, tinted by the theme).
  static const brandSet = 'simple-icons';
  static const github = 'github';
  static const googleDrive = 'googledrive';
  static const googlePhotos = 'googlephotos';
  static const notion = 'notion';
  static const gmail = 'gmail';
  static const calendar = 'googlecalendar';
  static const slack = 'slack';

  /// Shown while a brand mark loads or when it is missing.
  static const googleDriveFallback = HugeIcons.strokeRoundedGoogleDrive;
  static const photosFallback = HugeIcons.strokeRoundedImage01;
  static const notionFallback = HugeIcons.strokeRoundedNotebook;
  static const mailFallback = HugeIcons.strokeRoundedMail01;
  static const calendarFallback = HugeIcons.strokeRoundedCalendar03;
  static const slackFallback = HugeIcons.strokeRoundedBubbleChat;
  static const githubFallback = AppIcons.github;
}

abstract final class AppsSizes {
  static const brandGlyph = 22.0;
  static const soonAlpha = 0.6;
  static const avatar = 40.0;
}

// ---- GitHub screens ------------------------------------------------------

abstract final class GithubHubStrings {
  static const title = 'GitHub';
  static const connectedStatus = 'CONNECTED';
  static const openOnGithub = 'Open on GitHub';
  static const reconnect = 'Reconnect';
  static const disconnect = 'Disconnect';
  static const reconnectTitle = 'Reconnect GitHub?';
  static const reconnectBody =
      'Sparky will sign you out of GitHub and start the connection again, '
      'for example to switch account or refresh access.';
  static const reconnectAction = 'RECONNECT';
  static const search = 'Search GitHub';
  static const private = 'Private';
  static const public = 'Public';

  static const tabRepos = 'Repositories';
  static const tabPulls = 'Pull requests';
  static const tabIssues = 'Issues';
  static const tabActivity = 'Activity';

  static const filterRepos = 'Search your repositories';
  static const sortLabel = 'Sort';
  static const sortPushed = 'Recently pushed';
  static const sortName = 'Name';
  static const sortStars = 'Stars';
  static const filterAll = 'All';
  static const filterPublic = 'Public';
  static const filterPrivate = 'Private';
  static const filterForks = 'Forks';
  static const noRepos = 'No repositories yet';
  static const noReposHint = 'Repositories you can access will show up here.';
  static const noMatches = 'No repositories match';
  static String noMatchesHint(String q) => 'Nothing found for “$q”.';
  static String repoCount(int shown, int total) =>
      shown == total ? '$total repositories' : '$shown of $total repositories';
  static const forkBadge = 'FORK';
  static const archivedBadge = 'ARCHIVED';
  static const privateBadge = 'PRIVATE';

  static const noPulls = 'No open pull requests';
  static const noPullsHint = 'Pull requests you are involved in appear here.';
  static const noIssues = 'No open issues';
  static const noIssuesHint = 'Issues assigned to you or opened by you.';
  static const noActivity = 'No recent commits';
  static const noActivityHint = 'Your latest commits across GitHub.';
  static const loadFailed = 'Could not load from GitHub';
  static const retry = 'Try again';
  static const loadingMore = 'Loading more…';

  static String repoStats(int repos) => '$repos repositories';
  static String publicPrivate(int pub, int? priv) =>
      priv == null ? '$pub public' : '$pub public · $priv private';

  static const searchTitle = 'Search GitHub';
  static const searchHint = 'Repositories and code';
  static const searchRepos = 'Repositories';
  static const searchCode = 'Code';
  static const searchStart = 'Search across GitHub';
  static const searchStartHint =
      'Find public repositories, or search code by keyword.';
  static const searchNone = 'Nothing found';
}

abstract final class GithubRepoStrings {
  static const tabOverview = 'Overview';
  static const tabFiles = 'Files';
  static const tabCommits = 'Commits';
  static const tabGraph = 'Graph';
  static const tabPulls = 'Pull requests';
  static const tabIssues = 'Issues';
  static const askSparky = 'Ask Sparky about this repo';
  static const noReadme = 'This repository has no README.';
  static const readme = 'README';
  static const noPulls = 'No open pull requests';
  static const noIssues = 'No open issues';
  static const noPullsHint = 'Nothing is waiting for review.';
  static const noIssuesHint = 'Nothing is waiting to be fixed.';
  static const defaultBranch = 'Default branch';
  static const updated = 'Updated';
  static const stars = 'Stars';
  static const forks = 'Forks';
  static const language = 'Language';
  static const branch = 'Branch';
  static const share = 'Open on GitHub';

  /// The first message of the chat started from a repository.
  static String prompt(String fullName) =>
      'Tell me about my GitHub repository $fullName: what it does, how it is '
      'laid out and what has changed recently. Then ask what I would like '
      'to do with it.';
}

abstract final class GithubHubIcons {
  static const repo = HugeIcons.strokeRoundedFolder01;
  static const pulls = HugeIcons.strokeRoundedGitPullRequest;
  static const issues = HugeIcons.strokeRoundedAlertCircle;
  static const activity = HugeIcons.strokeRoundedActivity01;
  static const star = HugeIcons.strokeRoundedStar;
  static const filter = HugeIcons.strokeRoundedFilterHorizontal;
  static const sort = HugeIcons.strokeRoundedSorting05;
  static const lock = HugeIcons.strokeRoundedLock;
  static const reconnect = HugeIcons.strokeRoundedRefresh;
  static const ask = HugeIcons.strokeRoundedBubbleChat;
}

abstract final class GithubHubSizes {
  static const avatar = 64.0;
  static const rowAvatar = 36.0;
  static const reposPage = 30;
  static const loadMoreExtent = 400.0;
  static const searchHeight = 52.0;
  static const rowIcon = 18.0;
  static const readmeMaxWidth = 720.0;
  static const treeHeight = 480.0;
  static const skeletonRows = 6;
  static const skeletonBar = 12.0;
}

abstract final class GithubHubDurations {
  static const debounce = Duration(milliseconds: 180);
}
