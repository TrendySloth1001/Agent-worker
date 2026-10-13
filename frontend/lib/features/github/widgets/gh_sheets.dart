import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/github_detail.dart';
import '../../../core/haptics.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/m3_kit_extras.dart';
import '../../../data/github_api.dart';
import '../../chat/widgets/github/github_common.dart';
import '../../chat/widgets/github/github_review_card.dart';
import '../../settings/widgets/settings_kit.dart';
import '../gh_actions.dart';
import '../gh_item_controller.dart';
import '../../../core/widgets/confirm_sheet.dart';
import '../../../core/widgets/illustration.dart';
import '../../../core/constants/confirm_copy.dart';

/// Sheets of the pull request / issue actions. Each runs the action through
/// the controller and explains a refusal inline (with Reconnect when the
/// token lacks access).

Future<bool> _done(BuildContext context, Object? error, String ok) async {
  if (!context.mounted) return false;
  if (error != null) {
    showGhError(context, error);
    return false;
  }
  Haptics.send();
  ghToast(context, ok);
  return true;
}

/// A sheet body: title, then [children], padded and scrollable above the
/// keyboard.
class _SheetBody extends StatelessWidget {
  const _SheetBody({
    required this.title,
    this.subtitle,
    required this.children,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: SingleChildScrollView(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          M3SheetTitle(title, subtitle: subtitle),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    ),
  );
}

// ---- review ------------------------------------------------------------------

/// Comment / approve / request changes, plus the Sparky (AI) review.
Future<void> showReviewSheet(BuildContext context, GhItemController c) async {
  final d = c.detail;
  if (d == null) return;
  final result = await showM3Sheet<(String, String)>(
    context,
    builder: (_) => _ReviewSheet(detail: d),
  );
  if (result == null || !context.mounted) return;
  if (result.$1 == 'SPARKY') {
    openSparkyReview(context, c.owner, c.repo, c.number, d.title);
    return;
  }
  final err = await c.review(result.$1, result.$2);
  if (context.mounted) {
    await _done(context, err, GhDetailStrings.reviewSubmitted);
  }
}

class _ReviewSheet extends StatefulWidget {
  const _ReviewSheet({required this.detail});

  final GhItemDetail detail;

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  final _text = TextEditingController();
  late String _event = widget.detail.can.approve ? 'APPROVE' : 'COMMENT';

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final can = widget.detail.can;
    final scheme = Theme.of(context).colorScheme;
    final needsBody = _event != 'APPROVE' && _text.text.trim().isEmpty;
    return _SheetBody(
      title: GhDetailStrings.reviewTitle,
      children: [
        M3Group(
          children: [
            SettingsTile(
              icon: GhDetailIcons.sparky,
              title: GhDetailStrings.sparkyReview,
              summary: GhDetailStrings.sparkyReviewHint,
              onTap: () => Navigator.pop(context, ('SPARKY', '')),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        if (!can.review)
          Text(
            can.why('review') ?? GhDetailStrings.readOnlyBody,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium!.copyWith(color: scheme.onSurfaceVariant),
          )
        else ...[
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              const ButtonSegment(
                value: 'COMMENT',
                label: Text(GhDetailStrings.reviewComment),
              ),
              ButtonSegment(
                value: 'APPROVE',
                enabled: can.approve,
                label: const Text(GhDetailStrings.reviewApprove),
              ),
              ButtonSegment(
                value: 'REQUEST_CHANGES',
                enabled: can.approve,
                label: const Text(GhDetailStrings.reviewRequestChanges),
              ),
            ],
            selected: {_event},
            onSelectionChanged: (s) {
              Haptics.tap();
              setState(() => _event = s.first);
            },
          ),
          if (!can.approve && can.why('approve') != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              can.why('approve')!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall!.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _text,
            minLines: 3,
            maxLines: GhDetailSizes.composerMaxLines,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: GhDetailStrings.reviewHint,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            onPressed: needsBody
                ? null
                : () => Navigator.pop(context, (_event, _text.text)),
            child: const Text(GhDetailStrings.submitReview),
          ),
        ],
      ],
    );
  }
}

/// The existing AI review, full screen.
void openSparkyReview(
  BuildContext context,
  String owner,
  String repo,
  int number,
  String title,
) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => M3Page(
        title: GhDetailStrings.sparkyReview,
        slivers: [
          M3Body(
            children: [
              Text(
                '$owner/$repo #$number  $title',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.lg),
              GithubReviewInline(owner: owner, repo: repo, number: number),
            ],
          ),
        ],
      ),
    ),
  );
}

// ---- merge ---------------------------------------------------------------------

Future<void> showMergeSheet(BuildContext context, GhItemController c) async {
  final d = c.detail;
  if (d == null) return;
  final result = await showM3Sheet<(String, String)>(
    context,
    builder: (_) => _MergeSheet(detail: d),
  );
  if (result == null || !context.mounted) return;
  final err = await c.merge(result.$1, result.$2);
  if (context.mounted) await _done(context, err, GhDetailStrings.mergedToast);
}

class _MergeSheet extends StatefulWidget {
  const _MergeSheet({required this.detail});

  final GhItemDetail detail;

  @override
  State<_MergeSheet> createState() => _MergeSheetState();
}

class _MergeSheetState extends State<_MergeSheet> {
  late String _method = widget.detail.mergeMethods.firstOrNull ?? 'merge';
  late final _title = TextEditingController(
    text: GhDetailStrings.mergeDefaultTitle(
      widget.detail.title,
      widget.detail.number,
    ),
  );

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  static String _label(String m) => switch (m) {
    'squash' => GhDetailStrings.mergeSquash,
    'rebase' => GhDetailStrings.mergeRebase,
    _ => GhDetailStrings.mergeMerge,
  };

  @override
  Widget build(BuildContext context) {
    final d = widget.detail;
    final scheme = Theme.of(context).colorScheme;
    final ok = d.can.merge;
    final stateColor = d.mergeable == false || d.mergeableState == 'dirty'
        ? ghStateColor(context, 'closed')
        : d.mergeableState == 'clean'
        ? ghStateColor(context, 'open')
        : scheme.onSurfaceVariant;
    return _SheetBody(
      title: GhDetailStrings.mergeTitle,
      subtitle: '${d.head} → ${d.base}',
      children: [
        Row(
          children: [
            AppIcon(
              ok ? GhDetailIcons.pass : GhDetailIcons.warning,
              size: AppIconSize.md,
              color: stateColor,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                GhDetailStrings.mergeState(d.mergeableState, d.mergeable),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
        if (!ok && d.can.why('merge') != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            d.can.why('merge')!,
            style: Theme.of(
              context,
            ).textTheme.bodySmall!.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        RadioGroup<String>(
          groupValue: _method,
          onChanged: (v) {
            if (!ok || v == null) return;
            Haptics.tap();
            setState(() => _method = v);
          },
          child: M3Group(
            children: [
              for (final m in d.mergeMethods)
                RadioListTile<String>(
                  value: m,
                  enabled: ok,
                  title: Text(_label(m)),
                ),
            ],
          ),
        ),
        if (_method != 'rebase') ...[
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _title,
            enabled: ok,
            decoration: const InputDecoration(
              labelText: GhDetailStrings.mergeCommitTitle,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        FilledButton.icon(
          onPressed: ok
              ? () => Navigator.pop(context, (_method, _title.text))
              : null,
          icon: const AppIcon(GhDetailIcons.merge, size: AppIconSize.md),
          label: Text(ok ? _label(_method) : GhDetailStrings.merge),
        ),
      ],
    );
  }
}

// ---- close / reopen ----------------------------------------------------------------

/// Issues pick completed / not planned; pull requests confirm.
Future<void> showCloseSheet(BuildContext context, GhItemController c) async {
  final d = c.detail;
  if (d == null) return;
  String? reason;
  if (d.isPr) {
    final ok = await ConfirmSheet.show(
      context,
      illustration: IllustrationKind.githubBranches,
      kicker: ConfirmCopy.kickerClose,
      title: GhDetailStrings.closePr,
      body: GhDetailStrings.closePrBody,
      confirmLabel: GhDetailStrings.close,
      cancelLabel: GhDetailStrings.cancel,
    );
    if (!ok) return;
  } else {
    reason = await showM3Sheet<String>(
      context,
      builder: (ctx) => M3ActionSheet(
        title: GhDetailStrings.closeIssue,
        rows: [
          SettingsTile(
            icon: GhDetailIcons.pass,
            title: GhDetailStrings.closeCompleted,
            summary: GhDetailStrings.closeCompletedHint,
            onTap: () => Navigator.pop(ctx, 'completed'),
          ),
          SettingsTile(
            icon: GhDetailIcons.skipped,
            title: GhDetailStrings.closeNotPlanned,
            summary: GhDetailStrings.closeNotPlannedHint,
            onTap: () => Navigator.pop(ctx, 'not_planned'),
          ),
        ],
      ),
    );
    if (reason == null) return;
  }
  if (!context.mounted) return;
  final err = await c.changeState('closed', reason: reason);
  if (context.mounted) await _done(context, err, GhDetailStrings.closedToast);
}

Future<void> reopenItem(BuildContext context, GhItemController c) async {
  final err = await c.changeState('open', reason: c.isPr ? null : 'reopened');
  if (context.mounted) await _done(context, err, GhDetailStrings.reopenedToast);
}

// ---- labels / assignees ---------------------------------------------------------------

Future<void> showLabelsSheet(BuildContext context, GhItemController c) async {
  final d = c.detail;
  if (d == null) return;
  final picked = await showM3Sheet<List<String>>(
    context,
    builder: (_) => _PickSheet<GhLabelFull>(
      title: GhDetailStrings.editLabels,
      load: () => c.api.repoLabels(c.owner, c.repo),
      selected: {for (final l in d.labels) l.name},
      keyOf: (l) => l.name,
      empty: GhDetailStrings.noLabels,
      tile: (l) => (
        Container(
          width: GhDetailSizes.avatarSmall,
          height: GhDetailSizes.avatarSmall,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: ghLabelColor(l.color),
          ),
        ),
        l.name,
        l.description,
      ),
    ),
  );
  if (picked == null || !context.mounted) return;
  final err = await c.setLabels(picked);
  if (context.mounted) await _done(context, err, GhDetailStrings.labelsSaved);
}

Future<void> showAssigneesSheet(
  BuildContext context,
  GhItemController c,
) async {
  final d = c.detail;
  if (d == null) return;
  final picked = await showM3Sheet<List<String>>(
    context,
    builder: (_) => _PickSheet<GhUser>(
      title: GhDetailStrings.editAssignees,
      load: () => c.api.repoAssignees(c.owner, c.repo),
      selected: {for (final u in d.assignees) u.login},
      keyOf: (u) => u.login,
      empty: GhDetailStrings.noAssignees,
      tile: (u) =>
          (GhAvatar(u.avatar, size: GhDetailSizes.avatar), u.login, ''),
    ),
  );
  if (picked == null || !context.mounted) return;
  final err = await c.setAssignees(picked);
  if (context.mounted) {
    await _done(context, err, GhDetailStrings.assigneesSaved);
  }
}

/// A checklist loaded on open, saved as the list of chosen keys.
class _PickSheet<T> extends StatefulWidget {
  const _PickSheet({
    required this.title,
    required this.load,
    required this.selected,
    required this.keyOf,
    required this.tile,
    required this.empty,
  });

  final String title, empty;
  final Future<List<T>> Function() load;
  final Set<String> selected;
  final String Function(T) keyOf;
  final (Widget, String, String) Function(T) tile;

  @override
  State<_PickSheet<T>> createState() => _PickSheetState<T>();
}

class _PickSheetState<T> extends State<_PickSheet<T>> {
  late final Set<String> _on = {...widget.selected};
  late Future<List<T>> _future = widget.load();

  @override
  Widget build(BuildContext context) {
    final maxH =
        MediaQuery.sizeOf(context).height * GhDetailSizes.pickerMaxHeight;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          M3SheetTitle(widget.title),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: FutureBuilder<List<T>>(
              future: _future,
              builder: (context, snap) {
                if (snap.hasError) {
                  return M3Empty(
                    icon: GhDetailIcons.warning,
                    title: GhDetailStrings.loadFailed,
                    hint: ghErrorText(snap.error!),
                    action: FilledButton.tonal(
                      onPressed: () => setState(() => _future = widget.load()),
                      child: const Text(GhDetailStrings.retry),
                    ),
                  );
                }
                final items = snap.data;
                if (items == null) {
                  return const Padding(
                    padding: EdgeInsets.all(AppSpacing.xxl),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (items.isEmpty) {
                  return M3Empty(
                    icon: GhDetailIcons.label,
                    title: widget.empty,
                  );
                }
                return ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.screenPadding,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final k = widget.keyOf(items[i]);
                    final (lead, title, sub) = widget.tile(items[i]);
                    return M3Cell(
                      index: i,
                      count: items.length,
                      child: CheckboxListTile(
                        value: _on.contains(k),
                        secondary: lead,
                        title: Text(title),
                        subtitle: sub.isEmpty
                            ? null
                            : Text(
                                sub,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                        onChanged: (v) {
                          Haptics.tap();
                          setState(
                            () => v == true ? _on.add(k) : _on.remove(k),
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.lg,
              AppSpacing.xl,
              AppSpacing.lg,
            ),
            child: FilledButton(
              onPressed: () => Navigator.pop(context, _on.toList()),
              child: const Text(GhDetailStrings.save),
            ),
          ),
        ],
      ),
    );
  }
}

// ---- edit / react ------------------------------------------------------------------

Future<void> showEditSheet(BuildContext context, GhItemController c) async {
  final d = c.detail;
  if (d == null) return;
  final result = await showM3Sheet<(String, String)>(
    context,
    builder: (_) => _EditSheet(detail: d),
  );
  if (result == null || !context.mounted) return;
  final err = await c.edit(
    title: result.$1 == d.title ? null : result.$1,
    body: result.$2 == d.body ? null : result.$2,
  );
  if (context.mounted) await _done(context, err, GhDetailStrings.saved);
}

class _EditSheet extends StatefulWidget {
  const _EditSheet({required this.detail});

  final GhItemDetail detail;

  @override
  State<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<_EditSheet> {
  late final _title = TextEditingController(text: widget.detail.title);
  late final _body = TextEditingController(text: widget.detail.body);

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final changed =
        _title.text.trim().isNotEmpty &&
        (_title.text != widget.detail.title ||
            _body.text != widget.detail.body);
    return _SheetBody(
      title: GhDetailStrings.edit,
      children: [
        TextField(
          controller: _title,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: GhDetailStrings.editTitle,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _body,
          minLines: 4,
          maxLines: GhDetailSizes.editBodyLines,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: GhDetailStrings.editBody,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        FilledButton(
          onPressed: changed
              ? () => Navigator.pop(context, (_title.text.trim(), _body.text))
              : null,
          child: const Text(GhDetailStrings.save),
        ),
      ],
    );
  }
}

Future<void> showReactSheet(BuildContext context, GhItemController c) async {
  final picked = await showM3Sheet<String>(
    context,
    builder: (ctx) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          0,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              GhDetailStrings.react,
              style: Theme.of(ctx).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final (id, emoji) in GhReactions.all)
                  ActionChip(
                    label: Text(emoji),
                    onPressed: () => Navigator.pop(ctx, id),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  if (picked == null || !context.mounted) return;
  final err = await c.react(picked);
  if (context.mounted) await _done(context, err, GhDetailStrings.reacted);
}

// ---- composer ------------------------------------------------------------------------

/// The comment box at the end of the conversation; when commenting is off
/// it says why (with Reconnect when that would help).
class GhComposer extends StatefulWidget {
  const GhComposer({super.key, required this.controller});

  final GhItemController controller;

  @override
  State<GhComposer> createState() => _GhComposerState();
}

class _GhComposerState extends State<GhComposer> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty) return;
    FocusScope.of(context).unfocus();
    final err = await widget.controller.comment(body);
    if (!mounted) return;
    if (await _done(context, err, GhDetailStrings.commentPosted)) _text.clear();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final d = c.detail;
    final scheme = Theme.of(context).colorScheme;
    if (d == null) return const SizedBox.shrink();
    if (!d.can.comment) {
      final reconnect = d.viewer.needsReconnect || !d.viewer.canWrite;
      return M3Card(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            AppIcon(
              GhDetailIcons.lock,
              size: AppIconSize.md,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                d.can.why('comment') ?? GhDetailStrings.readOnlyBody,
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            if (reconnect)
              TextButton(
                onPressed: () => ghReconnect(context),
                child: const Text(GhDetailStrings.reconnect),
              ),
          ],
        ),
      );
    }
    final empty = _text.text.trim().isEmpty;
    return M3Card(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _text,
            minLines: 2,
            maxLines: GhDetailSizes.composerMaxLines,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: GhDetailStrings.commentHint,
              fillColor: scheme.surfaceContainerHigh,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, GhDetailSizes.sendHeight),
              ),
              onPressed: empty || c.busy ? null : _send,
              icon: c.busy
                  ? const SizedBox.square(
                      dimension: AppIconSize.sm,
                      child: CircularProgressIndicator(
                        strokeWidth: GhDetailSizes.spinnerStroke,
                      ),
                    )
                  : const AppIcon(GhDetailIcons.send, size: AppIconSize.sm),
              label: Text(
                c.busy ? GhDetailStrings.sending : GhDetailStrings.send,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
