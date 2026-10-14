import 'package:flutter/material.dart';

import '../../core/constants/app_icons.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/constants/update.dart';
import '../../core/haptics.dart';
import '../../core/theme/app_palette.dart';
import '../../core/time_ago.dart';
import '../../core/errors/errors_api.dart';
import '../../core/update/update_api.dart';
import '../../core/update/update_models.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/m3_kit_extras.dart';
import '../chat/widgets/attachment_views.dart';
import '../settings/widgets/settings_kit.dart';
import '../settings/widgets/usage_states.dart';
import '../errors/errors_screen.dart';
import '../../core/constants/errors.dart';
import 'release_form_sheet.dart';
import 'release_labels.dart';
import 'releases_controller.dart';
import '../../core/widgets/confirm_sheet.dart';
import '../../core/widgets/illustration.dart';
import '../../core/constants/confirm_copy.dart';

/// Owner-only control centre for app updates: every release with its status,
/// how many people run each build, and the actions to ship, pull, edit and
/// delete, plus "Upload APK".
class ReleasesScreen extends StatefulWidget {
  const ReleasesScreen({
    super.key,
    this.api,
    this.pickApk,
    this.now,
    this.errorsApi,
  });

  /// Test seams: the API, the file picker and the clock.
  final UpdateApi? api;
  final ApkPicker? pickApk;
  final DateTime Function()? now;
  final ErrorsApi? errorsApi;

  @override
  State<ReleasesScreen> createState() => _ReleasesScreenState();
}

class _ReleasesScreenState extends State<ReleasesScreen> {
  late final ReleasesController _c = ReleasesController(
    widget.api ?? UpdateApi(),
  )..load();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  DateTime get _now => (widget.now ?? DateTime.now)();

  void _say(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _run(Future<bool> Function() action, String done) async {
    Haptics.tap();
    final ok = await action();
    if (!mounted) return;
    if (!ok) Haptics.error();
    _say(ok ? done : UpdateStrings.actionFailed);
  }

  Future<bool> _confirm(
    String title,
    String body,
    String yes, {
    bool destructive = false,
  }) {
    Haptics.tap();
    return ConfirmSheet.show(
      context,
      illustration: IllustrationKind.homeCode,
      kicker: destructive
          ? ConfirmCopy.kickerDelete
          : ConfirmCopy.kickerConfirm,
      title: title,
      body: body,
      confirmLabel: yes,
      cancelLabel: UpdateStrings.cancel,
      destructive: destructive,
    );
  }

  Future<void> _edit(OwnerRelease r) async {
    Haptics.tap();
    final change = await ReleaseFormSheet.show<ReleaseEdit>(
      context,
      ReleaseFormSheet.edit(release: r),
    );
    if (change == null || !mounted) return;
    await _run(() => _c.edit(r, change), UpdateStrings.saved);
  }

  Future<void> _upload() async {
    Haptics.tap();
    await ReleaseFormSheet.show<bool>(
      context,
      ReleaseFormSheet.upload(
        controller: _c,
        pickApk: widget.pickApk ?? pickApkFile,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _c,
    builder: (context, _) => M3Page(
      title: UpdateStrings.releasesTitle,
      actions: [
        // The owner's way into crash reports.
        IconButton(
          tooltip: ErrorsStrings.entryTitle,
          icon: const AppIcon(ErrorsIcons.entry, size: AppIconSize.md),
          onPressed: () {
            Haptics.tap();
            ErrorsScreen.open(context, api: widget.errorsApi);
          },
        ),
      ],
      onRefresh: _c.load,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _upload,
        icon: const AppIcon(UpdateIcons.upload, size: AppIconSize.md),
        label: const Text(UpdateStrings.uploadApk),
      ),
      slivers: [M3Body(children: _children(context))],
    ),
  );

  List<Widget> _children(BuildContext context) => _releaseChildren(context);

  List<Widget> _releaseChildren(BuildContext context) {
    if (_c.data == null) {
      if (_c.failed && !_c.loading) {
        return [
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.lg),
            child: UsageError(onRetry: _c.load, loading: _c.loading),
          ),
        ];
      }
      return [
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xl),
          child: LinearProgressIndicator(
            minHeight: AppBorder.thin,
            color: context.palette.accent,
            backgroundColor: context.palette.border,
          ),
        ),
      ];
    }
    if (_c.releases.isEmpty) {
      return [
        const M3Empty(
          icon: UpdateIcons.releases,
          title: UpdateStrings.releasesEmptyTitle,
          hint: UpdateStrings.releasesEmptyHint,
        ),
      ];
    }
    final top = _c.adoption.fold<int>(0, (m, a) => a.users > m ? a.users : m);
    return [
      if (_c.adoption.isNotEmpty) ...[
        const SettingsGroupHeader(UpdateStrings.adoptionHeader),
        SettingsGroup(
          entries: [
            for (final a in _c.adoption)
              GroupEntry(_AdoptionRow(row: a, top: top)),
          ],
        ),
      ],
      const SettingsGroupHeader(UpdateStrings.releasesHeader),
      for (final r in _c.releases) ...[
        _ReleaseCard(
          release: r,
          installs: _c.installsFor(r.build),
          now: _now,
          onGoLive: () => _run(() => _c.goLive(r), UpdateStrings.goLiveDone),
          onPull: () async {
            if (!await _confirm(
              UpdateStrings.confirmPullTitle,
              UpdateStrings.confirmPullBody,
              UpdateStrings.pull,
            )) {
              return;
            }
            await _run(() => _c.pull(r), UpdateStrings.pullDone);
          },
          onEdit: () => _edit(r),
          onDelete: () async {
            if (!await _confirm(
              UpdateStrings.confirmDeleteTitle,
              UpdateStrings.confirmDeleteBody,
              UpdateStrings.delete,
              destructive: true,
            )) {
              return;
            }
            await _run(() => _c.delete(r), UpdateStrings.deleted);
          },
        ),
        const SizedBox(height: AppSpacing.md),
      ],
    ];
  }
}

class _AdoptionRow extends StatelessWidget {
  const _AdoptionRow({required this.row, required this.top});

  final AdoptionRow row;
  final int top;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  UpdateStrings.buildLine(row.version, row.build),
                  style: context.text.label,
                ),
              ),
              Text(
                UpdateStrings.users(row.users),
                style: context.text.caption.copyWith(color: p.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          M3DotBar(fraction: top == 0 ? 0 : row.users / top),
        ],
      ),
    );
  }
}

class _ReleaseCard extends StatelessWidget {
  const _ReleaseCard({
    required this.release,
    required this.installs,
    required this.now,
    required this.onGoLive,
    required this.onPull,
    required this.onEdit,
    required this.onDelete,
  });

  final OwnerRelease release;
  final InstallStats? installs;
  final DateTime now;
  final VoidCallback onGoLive, onPull, onEdit, onDelete;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final r = release;
    final title = r.title.isEmpty ? 'v${r.version}' : r.title;
    final when = r.publishedAt ?? r.createdAt;
    final meta = [
      if (r.size > 0) formatBytes(r.size),
      if (when != null) timeAgo(when, now),
      if (r.minSupportedBuild != null)
        UpdateStrings.minLine(r.minSupportedBuild!),
    ].join(' · ');
    return M3Card(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              M3Tag(
                statusLabel(r.status),
                accent: r.status == ReleaseStatus.live,
              ),
              M3Tag(kindLabel(r.kind), accent: r.kind == UpdateKind.critical),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(title, style: context.text.title),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            UpdateStrings.buildLine(r.version, r.build),
            style: context.text.label.copyWith(color: p.textSecondary),
          ),
          if (meta.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              meta,
              style: context.text.caption.copyWith(color: p.textTertiary),
            ),
          ],
          if (installs != null && !installs!.isEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            _InstallsPanel(stats: installs!),
          ],
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              if (r.status != ReleaseStatus.live)
                _Action(
                  icon: UpdateIcons.goLive,
                  label: UpdateStrings.goLive,
                  onTap: onGoLive,
                  primary: true,
                ),
              if (r.status == ReleaseStatus.live)
                _Action(
                  icon: UpdateIcons.pull,
                  label: UpdateStrings.pull,
                  onTap: onPull,
                ),
              _Action(
                icon: UpdateIcons.edit,
                label: UpdateStrings.edit,
                onTap: onEdit,
              ),
              if (r.canDelete)
                _Action(
                  icon: UpdateIcons.delete,
                  label: UpdateStrings.delete,
                  onTap: onDelete,
                  danger: true,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Install attempts for one release: success rate and counts by stage.
class _InstallsPanel extends StatelessWidget {
  const _InstallsPanel({required this.stats});

  final InstallStats stats;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final rate = stats.successRate;
    final line = UpdateStrings.installsLine(
      stats.count('install_ok'),
      stats.failures,
      rate == null ? null : (rate * 100).round(),
    );
    final stages = [
      for (final e in UpdateStrings.stageLabels.entries)
        if (stats.count(e.key) > 0)
          UpdateStrings.stageLine(e.value, stats.count(e.key)),
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          UpdateStrings.installsHeader,
          style: context.text.caption.copyWith(color: p.textTertiary),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(line, style: context.text.label),
        if (stages.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            stages,
            style: context.text.caption.copyWith(color: p.textSecondary),
          ),
        ],
      ],
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.danger = false,
  });

  final AppIconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary, danger;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = danger
        ? p.error
        : primary
        ? p.accent
        : p.textPrimary;
    return TextButton.icon(
      onPressed: onTap,
      icon: AppIcon(icon, size: AppIconSize.sm, color: color),
      label: Text(label, style: context.text.label.copyWith(color: color)),
    );
  }
}
