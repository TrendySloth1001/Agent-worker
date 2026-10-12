import 'package:flutter/material.dart';

import '../../core/constants/github_detail.dart';
import '../../core/constants/widget_github.dart';
import '../../core/haptics.dart';
import '../../core/theme/app_palette.dart';
import '../../data/chat_api.dart';
import '../../data/github_api.dart';
import '../chat/chat_launch.dart';
import '../chat/widgets/github/github_common.dart';
import '../connections/connections_controller.dart';
import 'commit_screen.dart';
import 'issue_screen.dart';
import 'pr_screen.dart';

/// Shared actions of the GitHub screens: Ask Sparky, opening items in-app,
/// and explaining GitHub's refusals (with Reconnect when the token lacks
/// access).

/// Starts a new chat with [prompt] and returns to it. The same hook as
/// "Ask Sparky about this repo": the chat screen listens to [ChatLaunch].
void askSparky(BuildContext context, String prompt) {
  Haptics.tap();
  ChatLaunch.instance.ask(prompt);
  Navigator.of(context).popUntil((r) => r.isFirst);
}

/// `owner/repo` split; null when [full] is not one.
(String, String)? splitRepo(String full) {
  final parts = full.split('/');
  if (parts.length != 2 || parts.any((p) => p.isEmpty)) return null;
  return (parts[0], parts[1]);
}

/// Opens a pull request or issue in-app (the browser only when the
/// repository is unknown).
void openGhItem(
  BuildContext context, {
  required String repo,
  required int number,
  required bool isPr,
  String title = '',
  String url = '',
}) {
  Haptics.tap();
  final r = splitRepo(repo);
  if (r == null || number <= 0) {
    if (url.isNotEmpty) ghVisit(context, url);
    return;
  }
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => isPr
          ? GithubPullScreen(
              owner: r.$1,
              repo: r.$2,
              number: number,
              seedTitle: title,
            )
          : GithubIssueScreen(
              owner: r.$1,
              repo: r.$2,
              number: number,
              seedTitle: title,
            ),
    ),
  );
}

/// Opens one commit in-app.
void openGhCommit(
  BuildContext context, {
  required String repo,
  required String sha,
  String message = '',
  String url = '',
}) {
  Haptics.tap();
  final r = splitRepo(repo);
  if (r == null || sha.isEmpty) {
    if (url.isNotEmpty) ghVisit(context, url);
    return;
  }
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => GithubCommitScreen(
        owner: r.$1,
        repo: r.$2,
        sha: sha,
        seedMessage: message,
      ),
    ),
  );
}

/// The user-facing text of a failed GitHub call.
String ghErrorText(Object e) {
  if (e is GhApiException && e.rateLimited) {
    return e.message.isNotEmpty ? e.message : GhDetailStrings.rateLimited;
  }
  if (e is ApiException && e.message.isNotEmpty) return e.message;
  return GhDetailStrings.actionFailed;
}

/// True when reconnecting GitHub could fix [e].
bool ghNeedsReconnect(Object? e) => e is GhApiException && e.needsReconnect;

/// Signs out of GitHub and starts the connection again (to grant access).
Future<void> ghReconnect(BuildContext context) async {
  Haptics.tap();
  final conn = ConnectionsController.instance;
  try {
    await conn.disconnectGithub();
    await conn.connectGithub();
  } catch (e) {
    if (context.mounted) ghToast(context, ghErrorText(e));
  }
}

void ghToast(BuildContext context, String text, {SnackBarAction? action}) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(content: Text(text), action: action));
}

/// Shows a failed action inline, with Reconnect when that would help.
void showGhError(BuildContext context, Object e) {
  ghToast(
    context,
    ghErrorText(e),
    action: ghNeedsReconnect(e)
        ? SnackBarAction(
            label: GhDetailStrings.reconnect,
            onPressed: () => ghReconnect(context),
          )
        : null,
  );
}

/// Explains why an action is off (instead of a dead button).
void explainDisabled(
  BuildContext context,
  String? reason, {
  bool reconnect = false,
}) {
  Haptics.tap();
  ghToast(
    context,
    reason ?? GhDetailStrings.readOnlyBody,
    action: reconnect
        ? SnackBarAction(
            label: GhDetailStrings.reconnect,
            onPressed: () => ghReconnect(context),
          )
        : null,
  );
}

/// GitHub's color for a pull request / issue state.
Color ghStateColor(
  BuildContext context,
  String state, {
  bool isPr = true,
  String? reason,
}) {
  final p = context.palette;
  // Closed issues: done is purple, not planned is grey (as on GitHub).
  if (!isPr && state == 'closed') {
    return reason == 'not_planned'
        ? p.textSecondary
        : (p.isDark ? GhDetailColors.mergedDark : GhDetailColors.mergedLight);
  }
  return switch (state) {
    'open' => p.isDark ? GhDetailColors.openDark : GhDetailColors.openLight,
    'merged' =>
      p.isDark ? GhDetailColors.mergedDark : GhDetailColors.mergedLight,
    'closed' => p.accent,
    _ => p.textSecondary,
  };
}

/// The octicon of a pull request / issue state.
String ghItemStateIcon(String state, {required bool isPr, String? reason}) {
  if (!isPr) {
    if (state == 'open') return GithubOcticons.issueOpen;
    return reason == 'not_planned'
        ? GithubOcticons.issueSkipped
        : GithubOcticons.issueClosed;
  }
  return switch (state) {
    'merged' => GithubOcticons.merged,
    'draft' => GithubOcticons.prDraft,
    'closed' => GithubOcticons.prClosed,
    _ => GithubOcticons.pr,
  };
}

String ghStateLabel(String state, {String? reason}) => switch (state) {
  'merged' => GhDetailStrings.merged,
  'draft' => GhDetailStrings.draft,
  'closed' when reason == 'not_planned' => GhDetailStrings.notPlanned,
  'closed' => GhDetailStrings.closed,
  _ => GhDetailStrings.open,
};
