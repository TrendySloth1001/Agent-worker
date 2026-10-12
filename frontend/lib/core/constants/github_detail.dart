import 'package:flutter/painting.dart' show Color;
import 'package:hugeicons/hugeicons.dart';

import 'app_icons.dart';

// ---- in-app pull request / issue / commit screens ----------------------------

abstract final class GhDetailStrings {
  static const pullTitle = 'Pull request';
  static const issueTitle = 'Issue';
  static const commitTitle = 'Commit';

  static const tabConversation = 'Conversation';
  static const tabCommits = 'Commits';
  static const tabFiles = 'Files changed';
  static const tabChecks = 'Checks';
  static String tabCount(String tab, int n) => n > 0 ? '$tab  $n' : tab;

  static const askSparky = 'Ask Sparky';
  static const openOnGithub = 'Open on GitHub';
  static const copyLink = 'Copy link';
  static const copied = 'Link copied';
  static const more = 'More';
  static const refresh = 'Refresh';

  // States.
  static const open = 'Open';
  static const draft = 'Draft';
  static const merged = 'Merged';
  static const closed = 'Closed';
  static const notPlanned = 'Not planned';
  static const completed = 'Completed';

  // Header.
  static String opened(String who, String ago) => '$who opened $ago ago';
  static String mergedBy(String who, String ago) => '$who merged $ago ago';
  static const intoArrow = '←';
  static const labels = 'Labels';
  static const assignees = 'Assignees';
  static const reviewers = 'Reviewers';
  static const milestone = 'Milestone';
  static const none = 'None yet';
  static const noDescription = 'No description provided.';
  static String commits(int n) => n == 1 ? '1 commit' : '$n commits';
  static String files(int n) => n == 1 ? '1 file' : '$n files';
  static String comments(int n) => n == 1 ? '1 comment' : '$n comments';
  static const locked = 'Locked';

  // Conversation.
  static const commented = 'commented';
  static const reviewApproved = 'approved these changes';
  static const reviewChanges = 'requested changes';
  static const reviewCommented = 'reviewed';
  static const reviewDismissed = 'review dismissed';
  static const approvedBadge = 'APPROVED';
  static const changesBadge = 'CHANGES';
  static const commentBadge = 'REVIEW';
  static String line(String path, int? line) =>
      line == null ? path : '$path:$line';
  static const someone = 'Someone';

  /// One line for a timeline event, e.g. "added the bug label".
  static String event(String event, String detail) => switch (event) {
    'labeled' => 'added the $detail label',
    'unlabeled' => 'removed the $detail label',
    'assigned' => 'assigned $detail',
    'unassigned' => 'unassigned $detail',
    'review_requested' => 'requested a review from $detail',
    'review_request_removed' => 'removed the review request for $detail',
    'renamed' => 'changed the title $detail',
    'milestoned' => 'added this to $detail',
    'demilestoned' => 'removed this from $detail',
    'merged' => detail.isEmpty ? 'merged this' : 'merged commit $detail',
    'closed' => switch (detail) {
      'not_planned' => 'closed this as not planned',
      'completed' => 'closed this as completed',
      _ => 'closed this',
    },
    'reopened' => 'reopened this',
    'referenced' => 'referenced this in commit $detail',
    'cross-referenced' => 'mentioned this in $detail',
    'head_ref_force_pushed' => 'force-pushed the branch',
    'head_ref_deleted' => 'deleted the branch',
    'head_ref_restored' => 'restored the branch',
    'ready_for_review' => 'marked this ready for review',
    'convert_to_draft' => 'converted this to a draft',
    'locked' => 'locked the conversation',
    'unlocked' => 'unlocked the conversation',
    'review_dismissed' => 'dismissed a review',
    'base_ref_changed' => 'changed the base branch',
    'auto_merge_enabled' => 'enabled auto-merge',
    'auto_merge_disabled' => 'disabled auto-merge',
    'connected' => 'linked a pull request',
    'disconnected' => 'unlinked a pull request',
    'marked_as_duplicate' => 'marked this as a duplicate',
    'deployed' => 'deployed this',
    _ => event.replaceAll('_', ' '),
  };
  static String ago(String a) => a.isEmpty ? '' : '$a ago';
  static const noTimeline = 'No comments yet';
  static const noTimelineHint = 'Start the conversation below.';

  // Composer.
  static const commentHint = 'Leave a comment';
  static const send = 'Comment';
  static const sending = 'Posting…';
  static const commentPosted = 'Comment posted';

  // Actions.
  static const review = 'Review';
  static const reviewTitle = 'Review changes';
  static const reviewComment = 'Comment';
  static const reviewApprove = 'Approve';
  static const reviewRequestChanges = 'Request changes';
  static const reviewHint = 'Leave a review comment';
  static const reviewNeedsBody = 'Add a comment to request changes.';
  static const submitReview = 'Submit review';
  static const reviewSubmitted = 'Review submitted';
  static const sparkyReview = 'Sparky review';
  static const sparkyReviewHint =
      'An AI review of the diff with risks and fixes';
  static const merge = 'Merge';
  static const mergeTitle = 'Merge pull request';
  static const mergeSquash = 'Squash and merge';
  static const mergeMerge = 'Create a merge commit';
  static const mergeRebase = 'Rebase and merge';
  static const mergeCommitTitle = 'Commit title';
  static const mergeConfirm = 'Confirm merge';
  static const mergedToast = 'Pull request merged';
  static String mergeState(String? s, bool? mergeable) => switch (s) {
    _ when mergeable == false =>
      'This branch has conflicts that must be resolved',
    'clean' => 'No conflicts with the base branch',
    'dirty' => 'This branch has conflicts that must be resolved',
    'blocked' => 'Merging is blocked by required reviews or checks',
    'behind' => 'This branch is behind the base branch',
    'unstable' => 'Mergeable, but some checks are not passing',
    'has_hooks' => 'Mergeable (the repository has merge hooks)',
    'draft' => 'Drafts cannot be merged',
    _ => 'GitHub is still checking mergeability',
  };
  static String mergeDefaultTitle(String title, int n) => '$title (#$n)';
  static const close = 'Close';
  static const closePr = 'Close pull request';
  static const closeIssue = 'Close issue';
  static const closeCompleted = 'Close as completed';
  static const closeCompletedHint = 'Done, fixed or resolved';
  static const closeNotPlanned = 'Close as not planned';
  static const closeNotPlannedHint = "Won't fix, duplicate or stale";
  static const closePrBody =
      'The pull request stays on GitHub and can be reopened later.';
  static const cancel = 'Cancel';
  static const reopen = 'Reopen';
  static const closedToast = 'Closed';
  static const reopenedToast = 'Reopened';
  static const markReady = 'Ready for review';
  static const markedReady = 'Marked ready for review';
  static const editLabels = 'Edit labels';
  static const editAssignees = 'Edit assignees';
  static const labelsSaved = 'Labels updated';
  static const assigneesSaved = 'Assignees updated';
  static const noLabels = 'This repository has no labels';
  static const noAssignees = 'Nobody can be assigned here';
  static const save = 'Save';
  static const edit = 'Edit title and description';
  static const editTitle = 'Title';
  static const editBody = 'Description';
  static const saved = 'Saved';
  static const react = 'Add reaction';
  static const reacted = 'Reaction added';

  // Permission and network states.
  static const reconnect = 'Reconnect';
  static const readOnlyTitle = 'Read-only';
  static const readOnlyBody =
      "Your GitHub connection can read this but can't make changes. "
      'Reconnect GitHub with repo access to comment, review and merge.';
  static const notConnectedBody =
      'Connect your own GitHub account to comment, review and merge here.';
  static const staleTitle = "Couldn't refresh";
  static String staleBody(String why) => 'Showing saved data. $why';
  static const rateLimited = 'GitHub rate limit reached. Try again shortly.';
  static const retry = 'Try again';
  static const loadFailed = 'Could not load from GitHub';
  static const actionFailed = 'GitHub did not accept that';

  // Commits / files / checks.
  static const noCommits = 'No commits';
  static const noFiles = 'No changed files';
  static const filesTruncated = 'GitHub lists at most 300 files here.';
  static const binary = 'Binary file, no text diff.';
  static const noPatch = 'Diff too large to show here.';
  static const patchTruncated = 'Diff truncated.';
  static String renamedFrom(String from) => 'renamed from $from';
  static const askFile = 'Ask Sparky about this file';
  static const copyPath = 'Copy path';
  static const pathCopied = 'Path copied';
  static const expandAll = 'Expand all';
  static const collapseAll = 'Collapse all';
  static const checksPassed = 'All checks have passed';
  static const checksFailing = 'Some checks were not successful';
  static const checksPending = 'Some checks haven’t completed yet';
  static const noChecks = 'No checks on the latest commit';
  static const noChecksHint = 'CI results for this pull request show here.';
  static const checksUnavailable = "Can't read checks";
  static String checkCounts(int fail, int pending, int pass, int skipped) => [
    if (fail > 0) '$fail failing',
    if (pending > 0) '$pending pending',
    if (pass > 0) '$pass passed',
    if (skipped > 0) '$skipped skipped',
  ].join(' · ');
  static const checkPass = 'Passed';
  static const checkFail = 'Failed';
  static const checkPending = 'In progress';
  static const checkSkipped = 'Skipped';
  static const checkNeutral = 'Neutral';
  static const viewLog = 'View the full log on GitHub';
  static const verified = 'VERIFIED';
  static const commitFiles = 'Files';
  static const commitMessage = 'Message';
  static String parents(int n) => n > 1 ? 'Merge commit' : '';
}

/// First messages of the chats started with "Ask Sparky". The `owner/repo#n`
/// form lets the chat load the pull request itself.
abstract final class GhPrompts {
  static String pull(String repo, int n, String title) =>
      'Summarize pull request $repo#$n ("$title"): what it changes, how risky '
      'it is and what I should look at closely. Flag anything that looks wrong.';
  static String issue(String repo, int n, String title) =>
      'Help me with issue #$n ("$title") in $repo: summarize the problem and '
      'the discussion so far, then suggest next steps or a fix.';
  static String commit(String repo, String sha, String message) =>
      'Explain commit ${sha.length > 7 ? sha.substring(0, 7) : sha} '
      '("$message") in $repo: what changed, why, and any risks.';
  static String pullFile(String repo, int n, String path) =>
      'In pull request $repo#$n, explain the changes to $path and flag any '
      'bugs or risks in them.';
  static String commitFile(String repo, String sha, String path) =>
      'In commit ${sha.length > 7 ? sha.substring(0, 7) : sha} of $repo, '
      'explain the changes to $path and flag any risks.';
  static String release(String repo, String tag) =>
      'What is new in release $tag of $repo? Summarize the notable changes.';
  static String push(String repo, String ref) =>
      'Summarize my latest commits on $ref in $repo and flag anything risky.';
  static String repo(String repo) =>
      'Tell me about my GitHub repository $repo: what it does and what has '
      'changed recently.';
}

abstract final class GhDetailIcons {
  static const ask = HugeIcons.strokeRoundedBubbleChat;
  static const more = HugeIcons.strokeRoundedMoreVertical;
  static const open = AppIcons.openExternal;
  static const copy = AppIcons.copy;
  static const refresh = HugeIcons.strokeRoundedRefresh;
  static const edit = HugeIcons.strokeRoundedEdit02;
  static const comment = HugeIcons.strokeRoundedComment01;
  static const review = HugeIcons.strokeRoundedMessageEdit01;
  static const send = HugeIcons.strokeRoundedSent;
  static const merge = HugeIcons.strokeRoundedGitMerge;
  static const close = HugeIcons.strokeRoundedCancelCircle;
  static const reopen = HugeIcons.strokeRoundedRefresh;
  static const ready = HugeIcons.strokeRoundedTick02;
  static const label = HugeIcons.strokeRoundedTag01;
  static const assignee = HugeIcons.strokeRoundedUserAdd01;
  static const reviewer = HugeIcons.strokeRoundedUserCheck01;
  static const milestone = HugeIcons.strokeRoundedFlag02;
  static const lock = HugeIcons.strokeRoundedSquareLock02;
  static const pass = HugeIcons.strokeRoundedCheckmarkCircle02;
  static const fail = HugeIcons.strokeRoundedCancelCircle;
  static const pending = HugeIcons.strokeRoundedClock01;
  static const skipped = HugeIcons.strokeRoundedMinusSignCircle;
  static const warning = HugeIcons.strokeRoundedAlert02;
  static const react = HugeIcons.strokeRoundedSmile;
  static const sparky = HugeIcons.strokeRoundedStarAward01;
  static const expand = HugeIcons.strokeRoundedArrowDown01;
  static const collapse = HugeIcons.strokeRoundedArrowUp01;
  static const commit = HugeIcons.strokeRoundedGitCommit;
  static const branch = HugeIcons.strokeRoundedGitBranch;
  static const release = HugeIcons.strokeRoundedPackage;
  static const star = HugeIcons.strokeRoundedStar;
  static const user = HugeIcons.strokeRoundedUserCircle;
  static const reconnect = HugeIcons.strokeRoundedRefresh;
}

/// GitHub's own state colors (the app palette has no green or purple).
abstract final class GhDetailColors {
  static const openLight = Color(0xFF1A7F37);
  static const openDark = Color(0xFF3FB950);
  static const mergedLight = Color(0xFF8250DF);
  static const mergedDark = Color(0xFFA371F7);
  static const pendingLight = Color(0xFF9A6700);
  static const pendingDark = Color(0xFFD29922);
  static const tintAlpha = 0.14;
}

abstract final class GhDetailSizes {
  static const avatar = 28.0;
  static const avatarSmall = 20.0;
  static const stateChipHeight = 28.0;
  static const eventIcon = 28.0;
  static const eventGlyph = 14.0;
  static const statusGlyph = 18.0;
  static const rail = 2.0;
  static const railInset = 13.0;
  static const composerMaxLines = 8;
  static const editBodyLines = 10;
  static const hunkLines = 6;
  static const diffMaxHeight = 560.0;
  static const autoExpandFiles = 6;
  static const autoExpandLines = 400;
  static const memoMax = 24;
  static const pickerMaxHeight = 0.7;
  static const reactionChipHeight = 28.0;
  static const disabledAlpha = 0.45;
  static const sendHeight = 44.0;
  static const spinnerStroke = 2.0;
}

/// GitHub's reaction ids and their emoji.
abstract final class GhReactions {
  static const all = <(String, String)>[
    ('+1', '👍'),
    ('-1', '👎'),
    ('laugh', '😄'),
    ('hooray', '🎉'),
    ('confused', '😕'),
    ('heart', '❤️'),
    ('rocket', '🚀'),
    ('eyes', '👀'),
  ];
  static String emoji(String id) =>
      all.where((r) => r.$1 == id).firstOrNull?.$2 ?? id;
}

// ---- activity feed ------------------------------------------------------------

abstract final class GhActivityStrings {
  static const today = 'Today';
  static const yesterday = 'Yesterday';
  static const empty = 'No recent activity';
  static const emptyHint =
      'Pushes, pull requests, issues and reviews show here.';
  static const fallbackNote = 'Showing your latest commits.';

  /// "pushed 3 commits to main", "opened pull request #12", …
  static String verb(
    String type,
    String action,
    int? n,
    bool isPr,
    String ref,
    int commits,
  ) {
    final what = isPr ? 'pull request' : 'issue';
    final num = n == null ? '' : ' #$n';
    return switch (type) {
      'push' =>
        commits > 1 ? 'pushed $commits commits to $ref' : 'pushed to $ref',
      'pr' => '$action pull request$num',
      'issue' => '$action issue$num',
      'review' => switch (action) {
        'approved' => 'approved pull request$num',
        'changes_requested' => 'requested changes on pull request$num',
        _ => 'reviewed pull request$num',
      },
      'comment' => 'commented on $what$num',
      'release' => 'published a release',
      'create' => 'created $action ${ref.isEmpty ? '' : ref}'.trim(),
      'delete' => 'deleted $action $ref'.trim(),
      'fork' => 'forked',
      'star' => 'starred',
      'public' => 'made public',
      'member' => '$action a collaborator',
      _ => action.isEmpty ? 'did something' : action,
    };
  }

  static const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  static String day(DateTime d) => '${months[d.month - 1]} ${d.day}';
  static const releaseTitle = 'Release';
  static const releaseNoNotes = 'No release notes.';
}
