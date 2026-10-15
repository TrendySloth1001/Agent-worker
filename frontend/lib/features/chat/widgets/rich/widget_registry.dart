import 'package:flutter/widgets.dart';

import '../../../../core/constants/connections.dart';
import '../../../../core/constants/device_actions.dart';
import '../../../../core/constants/playlist.dart';
import '../../../../core/constants/widget_github.dart';
import '../../../../core/constants/widget_kit.dart';
import '../../../../core/constants/widget_structure.dart';
import '../../../actions/action_card.dart';
import '../github/github_commits_card.dart';
import '../github/github_compare_card.dart';
import '../github/github_connect_card.dart';
import '../github/github_graph_card.dart';
import '../github/github_issues_card.dart';
import '../github/github_my_repos_card.dart';
import '../github/github_repo_card.dart';
import '../github/github_review_card.dart';
import '../github/github_search_card.dart';
import '../github/github_tree_card.dart';
import 'ask_card.dart' show RichPlaceholder;
import 'calc_card.dart';
import 'chart_card.dart';
import 'checklist_card.dart';
import 'compare_card.dart';
import 'flashcards_card.dart';
import 'html_card.dart';
import 'playlist_card.dart';
import 'progress_card.dart';
import 'quiz_card.dart';
import 'stats_card.dart';
import 'timeline_card.dart';
import 'tree_card.dart';

typedef RichWidgetFactory = Widget Function(String source);

class _Entry {
  const _Entry(this.label, this.build);
  final String label;
  final RichWidgetFactory build;
}

final Map<String, _Entry> _entries = {
  WidgetLang.chart: _Entry(WidgetKitStrings.chart, (s) => ChartCard(source: s)),
  WidgetLang.html: _Entry(WidgetKitStrings.html, (s) => HtmlCard(source: s)),
  WidgetLang.quiz: _Entry(WidgetKitStrings.quiz, (s) => QuizCard(source: s)),
  WidgetLang.flashcards: _Entry(
    WidgetKitStrings.flashcards,
    (s) => FlashcardsCard(source: s),
  ),
  WidgetLang.calc: _Entry(WidgetKitStrings.calc, (s) => CalcCard(source: s)),
  WidgetLang.timeline: _Entry(
    WidgetKitStrings.timeline,
    (s) => TimelineCard(source: s),
  ),
  WidgetLang.stats: _Entry(WidgetKitStrings.stats, (s) => StatsCard(source: s)),
  WidgetLang.checklist: _Entry(
    WidgetKitStrings.checklist,
    (s) => ChecklistCard(source: s),
  ),
  // Structure widgets.
  StructLang.compare: _Entry(
    StructStrings.compare,
    (s) => CompareCard(source: s),
  ),
  StructLang.progress: _Entry(
    StructStrings.progress,
    (s) => ProgressCard(source: s),
  ),
  StructLang.tree: _Entry(StructStrings.tree, (s) => TreeCard(source: s)),
  // Live GitHub cards (fetch through /github).
  GithubLang.repo: _Entry(GithubStrings.repo, (s) => GithubRepoCard(source: s)),
  GithubLang.search: _Entry(
    GithubStrings.search,
    (s) => GithubSearchCard(source: s),
  ),
  GithubLang.commits: _Entry(
    GithubStrings.commits,
    (s) => GithubCommitsCard(source: s),
  ),
  GithubLang.tree: _Entry(GithubStrings.tree, (s) => GithubTreeCard(source: s)),
  GithubLang.compare: _Entry(
    GithubStrings.compare,
    (s) => GithubCompareCard(source: s),
  ),
  GithubLang.prs: _Entry(
    GithubStrings.prs,
    (s) => GithubIssuesCard(source: s, prs: true),
  ),
  GithubLang.issues: _Entry(
    GithubStrings.issues,
    (s) => GithubIssuesCard(source: s, prs: false),
  ),
  GithubGraphLang.graph: _Entry(
    GithubGraphStrings.title,
    (s) => GithubGraphCard(source: s),
  ),
  GithubLangExtra.review: _Entry(
    GithubReviewStrings.title,
    (s) => GithubReviewCard(source: s),
  ),
  GithubLangExtra.myRepos: _Entry(
    GithubReviewStrings.myRepos,
    (s) => GithubMyReposCard(source: s),
  ),
  ConnectLang.githubConnect: _Entry(
    ConnectStrings.cardTitle,
    (s) => GithubConnectCard(source: s),
  ),
  // Several suggested songs: covers, previews, open in app, Play all.
  PlaylistWire.fence: _Entry(
    PlaylistStrings.label,
    (s) => PlaylistCard(source: s),
  ),
  // A device action the model proposed: runs only after Confirm.
  DeviceActionWire.fence: _Entry(
    DeviceActionStrings.cardLabel,
    (s) => ActionCard(source: s),
  ),
};

/// Maps a fenced language to its rich widget, or null when [language] is not
/// a registry widget (caller falls back to the code block). While [streaming]
/// a lightweight placeholder is returned so partial sources never get parsed.
Widget? buildRichWidget(
  String language,
  String source, {
  required bool streaming,
}) {
  final entry = _entries[language];
  if (entry == null) return null;
  if (streaming) {
    return RichPlaceholder(label: WidgetKitStrings.preparing(entry.label));
  }
  return entry.build(source);
}
