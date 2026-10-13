import 'package:flutter/material.dart';

import '../../../../core/constants/error_copy.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/widget_github.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../data/chat_api.dart';
import '../../../../data/github_api.dart';
import '../rich/diff_block.dart';
import '../rich/playful_common.dart';
import '../rich/rich_frame.dart';
import 'github_common.dart';

/// `owner/repo#123` or a github.com pull request URL.
final _prRef = RegExp(r'(?:github\.com/)?([\w-]+)/([\w.-]+?)(?:/pull/|#)(\d+)');

/// Parses a review block into (owner, repo, number).
(String, String, int)? parsePrRef(String source) {
  final lines = ghLines(source);
  final m = _prRef.firstMatch(lines.isEmpty ? source : lines.first);
  if (m == null) return null;
  return (m[1]!, m[2]!, int.parse(m[3]!));
}

/// ```github-review block: an AI review of a pull request's diff with a
/// verdict, risk meter and comments grouped by file; a comment opens the
/// diff hunk it is about.
class GithubReviewCard extends StatefulWidget {
  const GithubReviewCard({super.key, required this.source});

  final String source;

  @override
  State<GithubReviewCard> createState() => _GithubReviewCardState();
}

class _GithubReviewCardState extends State<GithubReviewCard> {
  late (String, String, int)? _ref = parsePrRef(widget.source);
  Future<GhReview>? _future;

  @override
  void initState() {
    super.initState();
    _future = _start();
  }

  @override
  void didUpdateWidget(GithubReviewCard old) {
    super.didUpdateWidget(old);
    if (old.source != widget.source) {
      _ref = parsePrRef(widget.source);
      _future = _start();
    }
  }

  Future<GhReview>? _start({bool fresh = false}) {
    final ref = _ref;
    if (ref == null) return null;
    return GithubApi.instance.review(ref.$1, ref.$2, ref.$3, fresh: fresh);
  }

  void _load({bool fresh = false}) =>
      setState(() => _future = _start(fresh: fresh));

  @override
  Widget build(BuildContext context) {
    final ref = _ref;
    if (ref == null) {
      return GhBadBlock(
        title: GithubReviewStrings.title,
        source: widget.source,
        hint: GithubReviewStrings.badSpec,
      );
    }
    final spec = GithubReviewStrings.spec(ref.$1, ref.$2, ref.$3);
    final url = 'https://github.com/${ref.$1}/${ref.$2}/pull/${ref.$3}';
    return RichCard(
      title: GithubStrings.titled(
        GithubReviewStrings.title,
        spec.toUpperCase(),
      ),
      leading: const Octicon(GithubOcticons.pr),
      actions: [
        ghVisitAction(context, url),
        RichAction(
          icon: GithubIcons.copy,
          label: GithubReviewStrings.copyAll,
          onTap: () async {
            try {
              final r = await _future!;
              if (!context.mounted) return false;
              await ghCopy(context, reviewMarkdown(r));
              return true;
            } catch (_) {
              return false;
            }
          },
        ),
        RichAction(
          icon: GithubIcons.retry,
          label: GithubReviewStrings.rerun,
          onTap: () async {
            _load(fresh: true);
            return true;
          },
        ),
      ],
      child: GithubReviewView(
        future: _future!,
        onRetry: () => _load(fresh: true),
      ),
    );
  }
}

/// A review without the card frame; also expands inline under a PR row.
class GithubReviewInline extends StatefulWidget {
  const GithubReviewInline({
    super.key,
    required this.owner,
    required this.repo,
    required this.number,
  });

  final String owner, repo;
  final int number;

  @override
  State<GithubReviewInline> createState() => _GithubReviewInlineState();
}

class _GithubReviewInlineState extends State<GithubReviewInline> {
  late Future<GhReview> _future = _start();

  Future<GhReview> _start({bool fresh = false}) => GithubApi.instance.review(
    widget.owner,
    widget.repo,
    widget.number,
    fresh: fresh,
  );

  @override
  Widget build(BuildContext context) => GithubReviewView(
    future: _future,
    padded: false,
    onRetry: () => setState(() => _future = _start(fresh: true)),
    onCopy: true,
  );
}

/// Loading state, error with RETRY, or the review.
class GithubReviewView extends StatelessWidget {
  const GithubReviewView({
    super.key,
    required this.future,
    required this.onRetry,
    this.padded = true,
    this.onCopy = false,
  });

  final Future<GhReview> future;
  final VoidCallback onRetry;
  final bool padded;

  /// Shows a COPY button under the review (inline use has no card actions).
  final bool onCopy;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<GhReview>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const _Reviewing();
        }
        if (snap.hasError) {
          final e = snap.error;
          return GhError(
            message: e is ApiException
                ? friendlyException(e)
                : GithubStrings.loadFailed,
            onRetry: onRetry,
          );
        }
        return Padding(
          padding: padded
              ? const EdgeInsets.all(GithubSizes.pad)
              : const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: _Review(review: snap.data!, copyButton: onCopy),
        );
      },
    );
  }
}

class _Reviewing extends StatelessWidget {
  const _Reviewing();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    return Padding(
      padding: const EdgeInsets.all(GithubSizes.pad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Octicon(GithubReviewOcticons.shield, color: p.textSecondary),
              const SizedBox(width: AppSpacing.sm),
              Text(
                GithubReviewStrings.reviewing,
                style: t.caption.copyWith(color: p.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              minHeight: GithubReviewSizes.progressHeight,
              color: p.textPrimary,
              backgroundColor: p.border,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(GithubReviewStrings.reviewingHint, style: t.caption),
        ],
      ),
    );
  }
}

Color _severityColor(BuildContext context, String s) {
  final p = context.palette;
  return switch (s) {
    'blocker' || 'major' => p.accent,
    'nit' => p.textTertiary,
    _ => p.textSecondary,
  };
}

class _Review extends StatelessWidget {
  const _Review({required this.review, required this.copyButton});

  final GhReview review;
  final bool copyButton;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final r = review;
    final byFile = <String, List<GhReviewComment>>{};
    for (final c in r.comments) {
      (byFile[c.file] ??= []).add(c);
    }
    final sub = [
      GithubStrings.issueNumber(r.number),
      if (r.author != null) GithubReviewStrings.byAuthor(r.author!.login),
      if (r.head.isNotEmpty) '${r.head} ${GithubStrings.into} ${r.base}',
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          r.title,
          style: t.bodySmall.copyWith(
            color: p.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          sub,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: t.caption,
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _VerdictBadge(verdict: r.verdict),
            _RiskMeter(risk: r.risk),
            GhDelta(add: r.additions, del: r.deletions),
            GhStat(
              GithubOcticons.fileCode,
              '${r.changedFiles} ${GithubStrings.changed}',
            ),
            if (r.cached) GhChip(GithubReviewStrings.cached),
          ],
        ),
        if (r.summary.isNotEmpty) ...[
          GhSection(GithubReviewStrings.summary),
          Text(r.summary, style: t.bodySmall),
        ],
        GhSection('${GithubReviewStrings.comments} ${r.comments.length}'),
        if (r.comments.isEmpty)
          Text(GithubReviewStrings.noComments, style: t.bodySmall)
        else
          for (final e in byFile.entries) ...[
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Row(
                children: [
                  Octicon(
                    GithubOcticons.fileCode,
                    size: GithubSizes.octiconSmall,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      e.key,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: TextDirection.ltr,
                      style: t.code.copyWith(color: p.textPrimary),
                    ),
                  ),
                  Text('${e.value.length}', style: t.caption),
                ],
              ),
            ),
            for (final c in e.value)
              _CommentRow(comment: c, file: r.fileFor(c.file)),
          ],
        if (r.tests.isNotEmpty) ...[
          GhSection(GithubReviewStrings.tests),
          for (final test in r.tests)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xxs),
                    child: Octicon(
                      GithubReviewOcticons.beaker,
                      size: GithubSizes.octiconSmall,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(test, style: t.bodySmall)),
                ],
              ),
            ),
        ],
        if (r.skippedFiles.isNotEmpty) ...[
          GhSection('${GithubReviewStrings.skipped} ${r.skippedFiles.length}'),
          Text(
            r.skippedFiles.join(', '),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: t.caption,
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        Text(r.model, style: t.caption),
        if (copyButton) ...[
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: PlayfulButton(
              label: GithubReviewStrings.copyAll,
              icon: GithubIcons.copy,
              onTap: () => ghCopy(context, reviewMarkdown(r)),
            ),
          ),
        ],
      ],
    );
  }
}

class _VerdictBadge extends StatelessWidget {
  const _VerdictBadge({required this.verdict});

  final String verdict;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final changes = verdict == 'request_changes';
    final approve = verdict == 'approve';
    final fg = changes
        ? p.accent
        : approve
        ? p.textInverse
        : p.textPrimary;
    return Container(
      height: GithubSizes.chipHeight,
      padding: const EdgeInsets.symmetric(horizontal: GithubSizes.chipPadH),
      decoration: BoxDecoration(
        color: approve ? p.textPrimary : null,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(
          color: changes ? p.accent : p.textPrimary,
          width: AppBorder.thin,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Octicon(
            GithubReviewOcticons.verdict(verdict),
            size: GithubSizes.octiconSmall,
            color: fg,
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            GithubReviewStrings.verdict(verdict),
            style: context.text.caption.copyWith(color: fg),
          ),
        ],
      ),
    );
  }
}

/// Three segments: low lights one, high lights all three in accent.
class _RiskMeter extends StatelessWidget {
  const _RiskMeter({required this.risk});

  final String risk;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final lit = switch (risk) {
      'high' => 3,
      'low' => 1,
      _ => 2,
    };
    final color = risk == 'high' ? p.accent : p.textPrimary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(GithubReviewStrings.risk, style: context.text.caption),
        const SizedBox(width: AppSpacing.xs),
        for (var i = 0; i < GithubReviewSizes.riskSegments; i++) ...[
          if (i > 0) const SizedBox(width: GithubReviewSizes.riskGap),
          Container(
            width: GithubReviewSizes.riskSegmentWidth,
            height: GithubReviewSizes.riskSegmentHeight,
            decoration: BoxDecoration(
              color: i < lit ? color : null,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(
                color: i < lit ? color : p.border,
                width: AppBorder.thin,
              ),
            ),
          ),
        ],
        const SizedBox(width: AppSpacing.xs),
        Text(
          GithubReviewStrings.riskLabel(risk),
          style: context.text.caption.copyWith(color: color),
        ),
      ],
    );
  }
}

class _CommentRow extends StatefulWidget {
  const _CommentRow({required this.comment, required this.file});

  final GhReviewComment comment;
  final GhFile? file;

  @override
  State<_CommentRow> createState() => _CommentRowState();
}

class _CommentRowState extends State<_CommentRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final c = widget.comment;
    final color = _severityColor(context, c.severity);
    final hunk = hunkFor(widget.file?.patch, c.line);
    return Padding(
      padding: const EdgeInsets.only(
        left: GithubReviewSizes.commentIndent,
        top: AppSpacing.xs,
        bottom: AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GhTap(
            onTap: () => setState(() => _open = !_open),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xxs),
                  child: Octicon(
                    GithubReviewOcticons.severity(c.severity),
                    size: GithubSizes.octiconSmall,
                    color: color,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${GithubReviewStrings.severity(c.severity)} ',
                          style: t.caption.copyWith(color: color),
                        ),
                        TextSpan(
                          text: c.title,
                          style: t.bodySmall.copyWith(color: p.textPrimary),
                        ),
                      ],
                    ),
                  ),
                ),
                if (c.line != null) ...[
                  const SizedBox(width: AppSpacing.xs),
                  Text(GithubReviewStrings.lineOf(c.line!), style: t.caption),
                ],
                const SizedBox(width: AppSpacing.xs),
                AppIcon(
                  _open ? GithubIcons.collapse : GithubIcons.expand,
                  size: AppIconSize.sm,
                  color: p.textTertiary,
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: GithubDurations.expand,
            alignment: Alignment.topCenter,
            child: !_open
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (c.body.isNotEmpty) Text(c.body, style: t.bodySmall),
                        const SizedBox(height: AppSpacing.sm),
                        if (hunk == null)
                          Text(
                            GithubReviewStrings.hunkMissing,
                            style: t.caption,
                          )
                        else
                          _Box(child: DiffLines(code: hunk)),
                        if (c.suggestion != null) ...[
                          GhSection(GithubReviewStrings.suggestion),
                          _Box(
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.sm),
                              child: SelectableText(
                                c.suggestion!,
                                style: t.code,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: p.background,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: p.border, width: AppBorder.thin),
      ),
      clipBehavior: Clip.antiAlias,
      constraints: const BoxConstraints(
        maxHeight: GithubReviewSizes.hunkMaxHeight,
      ),
      child: SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: child,
        ),
      ),
    );
  }
}

// ---- helpers -------------------------------------------------------------------

final _hunkHeader = RegExp(r'^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@');

/// Context kept around the commented line, in new-side lines.
const _hunkContext = 6;

/// The diff hunk of [patch] around new-side [line] (the first hunk when the
/// line is unknown), trimmed to a few lines of context; null without a patch.
String? hunkFor(String? patch, int? line) {
  if (patch == null || patch.trim().isEmpty) return null;
  final hunks = <(int, int, List<String>)>[];
  for (final l in patch.split('\n')) {
    final m = _hunkHeader.firstMatch(l);
    if (m != null) {
      hunks.add((int.parse(m[1]!), int.tryParse(m[2] ?? '') ?? 1, [l]));
    } else if (hunks.isNotEmpty) {
      hunks.last.$3.add(l);
    }
  }
  if (hunks.isEmpty) return null;
  if (line == null) return hunks.first.$3.join('\n');
  final hunk =
      hunks.where((h) => line >= h.$1 && line < h.$1 + h.$2).firstOrNull ??
      hunks.first;
  if (line < hunk.$1 || line >= hunk.$1 + hunk.$2) return hunk.$3.join('\n');
  final out = [hunk.$3.first];
  var n = hunk.$1;
  for (final l in hunk.$3.skip(1)) {
    final removed = l.startsWith('-');
    if ((n - line).abs() <= _hunkContext) out.add(l);
    if (!removed) n++;
  }
  return out.join('\n');
}

/// The review as markdown (COPY).
String reviewMarkdown(GhReview r) {
  final b = StringBuffer()
    ..writeln(
      GithubReviewStrings.markdownHeader(
        r.title,
        GithubReviewStrings.spec(r.owner, r.repo, r.number),
        GithubReviewStrings.verdict(r.verdict),
      ),
    )
    ..writeln(
      '**${GithubReviewStrings.risk}:** ${GithubReviewStrings.riskLabel(r.risk)}',
    )
    ..writeln();
  if (r.summary.isNotEmpty) b.writeln('${r.summary}\n');
  final byFile = <String, List<GhReviewComment>>{};
  for (final c in r.comments) {
    (byFile[c.file] ??= []).add(c);
  }
  for (final e in byFile.entries) {
    b.writeln('### `${e.key}`');
    for (final c in e.value) {
      final at = c.line == null
          ? ''
          : ' (${GithubReviewStrings.lineOf(c.line!)})';
      b.writeln(
        '- **[${GithubReviewStrings.severity(c.severity)}] ${c.title}**$at: ${c.body}',
      );
      if (c.suggestion != null) {
        b
          ..writeln('  ```')
          ..writeln(c.suggestion!.split('\n').map((l) => '  $l').join('\n'))
          ..writeln('  ```');
      }
    }
    b.writeln();
  }
  if (r.tests.isNotEmpty) {
    b.writeln('### ${GithubReviewStrings.tests}');
    for (final t in r.tests) {
      b.writeln('- $t');
    }
  }
  b.writeln('\n${r.url}');
  return b.toString().trim();
}
