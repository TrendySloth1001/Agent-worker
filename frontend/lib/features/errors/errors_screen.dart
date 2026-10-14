import 'package:flutter/material.dart';

import '../../core/constants/app_sizes.dart';
import '../../core/constants/errors.dart';
import '../../core/errors/errors_api.dart';
import '../../core/errors/errors_models.dart';
import '../../core/haptics.dart';
import '../../core/theme/app_palette.dart';
import '../../core/time_ago.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/m3_kit_extras.dart';
import '../settings/settings_pages.dart' show isOwner;
import '../settings/widgets/settings_kit.dart';
import '../settings/widgets/usage_states.dart';
import 'error_detail_screen.dart';
import 'errors_controller.dart';

/// Owner-only: error groups for a build (most users affected first) and the
/// crash-free session rate of every build. Reached from the Releases screen.
class ErrorsScreen extends StatefulWidget {
  const ErrorsScreen({super.key, this.api, this.now, this.owner});

  /// Test seams: the API, the clock and the owner check.
  final ErrorsApi? api;
  final DateTime Function()? now;
  final bool Function()? owner;

  /// Opens the screen for the owner; does nothing for anyone else, whatever the route.
  static Future<void> open(
    BuildContext context, {
    ErrorsApi? api,
    bool Function()? owner,
  }) async {
    if (!(owner ?? isOwner)()) return;
    await Navigator.push(
      context,
      settingsRoute(ErrorsScreen(api: api, owner: owner)),
    );
  }

  @override
  State<ErrorsScreen> createState() => _ErrorsScreenState();
}

class _ErrorsScreenState extends State<ErrorsScreen> {
  late final ErrorsApi _api = widget.api ?? ErrorsApi();
  late final ErrorsController _c = ErrorsController(_api);
  bool get _allowed => (widget.owner ?? isOwner)();

  @override
  void initState() {
    super.initState();
    if (_allowed) _c.load();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  DateTime get _now => (widget.now ?? DateTime.now)();

  @override
  Widget build(BuildContext context) {
    if (!_allowed) {
      return const M3Page(
        title: ErrorsStrings.screenTitle,
        slivers: [
          M3Body(
            children: [
              M3Empty(icon: ErrorsIcons.entry, title: ErrorsStrings.emptyTitle),
            ],
          ),
        ],
      );
    }
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) => M3Page(
        title: ErrorsStrings.screenTitle,
        onRefresh: _c.load,
        slivers: [M3Body(children: _children(context))],
      ),
    );
  }

  List<Widget> _children(BuildContext context) {
    if (_c.groups == null) {
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
    return [
      const SettingsGroupHeader(ErrorsStrings.buildHeader),
      if (_c.health.isEmpty)
        const M3Card(child: Text(ErrorsStrings.noSessions))
      else
        SettingsGroup(
          entries: [
            for (final h in _c.health) GroupEntry(_HealthRow(health: h)),
          ],
        ),
      const SettingsGroupHeader(ErrorsStrings.groupsHeader),
      _Filters(controller: _c),
      const SizedBox(height: AppSpacing.md),
      if (_c.items.isEmpty)
        const M3Empty(
          icon: ErrorsIcons.resolved,
          title: ErrorsStrings.emptyTitle,
          hint: ErrorsStrings.emptyHint,
        )
      else
        for (final g in _c.items) ...[
          _GroupCard(
            group: g,
            now: _now,
            onTap: () {
              Haptics.tap();
              Navigator.push(
                context,
                settingsRoute(
                  ErrorDetailScreen(
                    fingerprint: g.fingerprint,
                    api: _api,
                    now: widget.now,
                  ),
                ),
              ).then((_) => _c.load());
            },
          ),
          const SizedBox(height: AppSpacing.md),
        ],
    ];
  }
}

class _HealthRow extends StatelessWidget {
  const _HealthRow({required this.health});

  final BuildHealth health;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final rate = health.crashFree;
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
                  ErrorsStrings.buildLabel(health.build),
                  style: context.text.label,
                ),
              ),
              Text(
                rate == null ? '-' : ErrorsStrings.crashFree(rate),
                style: context.text.label.copyWith(
                  color: rate != null && rate < 0.985 ? p.error : p.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            [
              ErrorsStrings.sessions(health.sessions),
              ErrorsStrings.users(health.users),
              if (health.crashed > 0) ErrorsStrings.crashed(health.crashed),
            ].join(' · '),
            style: context.text.caption.copyWith(color: p.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          M3DotBar(fraction: rate ?? 0),
        ],
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({required this.controller});

  final ErrorsController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Wrap(
      spacing: ErrorsSizes.chipGap,
      runSpacing: ErrorsSizes.chipGap,
      children: [
        ChoiceChip(
          label: const Text(ErrorsStrings.allBuilds),
          selected: c.build == null,
          onSelected: (_) {
            Haptics.tap();
            c.selectBuild(null);
          },
        ),
        for (final b in c.builds)
          ChoiceChip(
            label: Text(ErrorsStrings.buildLabel(b)),
            selected: c.build == b,
            onSelected: (_) {
              Haptics.tap();
              c.selectBuild(b);
            },
          ),
        for (final s in [...ErrorStatus.values, null])
          ChoiceChip(
            label: Text(s == null ? ErrorsStrings.filterAll : statusText(s)),
            selected: c.status == s,
            onSelected: (_) {
              Haptics.tap();
              c.selectStatus(s);
            },
          ),
      ],
    );
  }
}

String statusText(ErrorStatus s) => switch (s) {
  ErrorStatus.open => ErrorsStrings.statusOpen,
  ErrorStatus.resolved => ErrorsStrings.statusResolved,
  ErrorStatus.ignored => ErrorsStrings.statusIgnored,
};

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.group,
    required this.now,
    required this.onTap,
  });

  final ErrorGroup group;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final g = group;
    final seen = g.lastSeen;
    return M3Card(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              M3Tag(statusText(g.status), accent: g.status == ErrorStatus.open),
              M3Tag(g.kind),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            g.title.isEmpty ? g.fingerprint.substring(0, 8) : g.title,
            style: context.text.title,
            maxLines: ErrorsSizes.titleMaxLines,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              AppIcon(
                ErrorsIcons.users,
                size: AppIconSize.xs,
                color: p.textSecondary,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                '${ErrorsStrings.users(g.shownUsers)} · '
                '${ErrorsStrings.events(g.shownCount)}',
                style: context.text.label.copyWith(color: p.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            [
              ErrorsStrings.buildRange(g.firstBuild, g.lastBuild),
              ?(seen == null ? null : timeAgo(seen, now)),
            ].join(' · '),
            style: context.text.caption.copyWith(color: p.textTertiary),
          ),
        ],
      ),
    );
  }
}
