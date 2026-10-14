import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/app_icons.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/constants/errors.dart';
import '../../core/errors/errors_api.dart';
import '../../core/errors/errors_models.dart';
import '../../core/haptics.dart';
import '../../core/theme/app_palette.dart';
import '../../core/time_ago.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/m3_kit_extras.dart';
import '../settings/widgets/settings_kit.dart';
import '../settings/widgets/usage_states.dart';
import 'errors_controller.dart';
import 'errors_screen.dart' show statusText;

/// One error group: samples with stack, breadcrumbs and device, per-build counts,
/// resolve / ignore, and the `symbolize.sh` command for the stack.
class ErrorDetailScreen extends StatefulWidget {
  const ErrorDetailScreen({
    super.key,
    required this.fingerprint,
    this.api,
    this.now,
  });

  final String fingerprint;
  final ErrorsApi? api;
  final DateTime Function()? now;

  @override
  State<ErrorDetailScreen> createState() => _ErrorDetailScreenState();
}

class _ErrorDetailScreenState extends State<ErrorDetailScreen> {
  late final ErrorDetailController _c = ErrorDetailController(
    widget.api ?? ErrorsApi(),
    widget.fingerprint,
  )..load();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  DateTime get _now => (widget.now ?? DateTime.now)();

  void _say(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _set(ErrorStatus s) async {
    Haptics.tap();
    final ok = await _c.setStatus(s);
    if (!mounted) return;
    if (!ok) Haptics.error();
    _say(ok ? ErrorsStrings.updated : ErrorsStrings.actionFailed);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _c,
    builder: (context, _) => M3Page(
      title: ErrorsStrings.groupsHeader,
      onRefresh: _c.load,
      slivers: [M3Body(children: _children(context))],
    ),
  );

  List<Widget> _children(BuildContext context) {
    final d = _c.detail;
    if (d == null) {
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
    final p = context.palette;
    final g = d.group;
    final command = ErrorsStrings.symbolize(g.fingerprint);
    return [
      M3Card(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                M3Tag(
                  statusText(g.status),
                  accent: g.status == ErrorStatus.open,
                ),
                M3Tag(g.kind),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(g.title, style: context.text.title),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${ErrorsStrings.users(g.users)} · ${ErrorsStrings.events(g.count)} · '
              '${ErrorsStrings.buildRange(g.firstBuild, g.lastBuild)}',
              style: context.text.label.copyWith(color: p.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                if (g.status != ErrorStatus.resolved)
                  _Act(
                    icon: ErrorsIcons.resolved,
                    label: ErrorsStrings.resolve,
                    primary: true,
                    onTap: () => _set(ErrorStatus.resolved),
                  ),
                if (g.status != ErrorStatus.ignored)
                  _Act(
                    icon: ErrorsIcons.ignored,
                    label: ErrorsStrings.ignore,
                    onTap: () => _set(ErrorStatus.ignored),
                  ),
                if (g.status != ErrorStatus.open)
                  _Act(
                    icon: ErrorsIcons.open,
                    label: ErrorsStrings.reopen,
                    onTap: () => _set(ErrorStatus.open),
                  ),
              ],
            ),
          ],
        ),
      ),
      const SettingsGroupHeader(ErrorsStrings.symbolizeHeader),
      M3Card(
        padding: const EdgeInsets.all(AppSpacing.lg),
        onTap: () {
          Haptics.tap();
          Clipboard.setData(ClipboardData(text: command));
          _say(ErrorsStrings.copied);
        },
        child: Row(
          children: [
            Expanded(
              child: SelectableText(command, style: context.text.caption),
            ),
            const SizedBox(width: AppSpacing.sm),
            AppIcon(
              ErrorsIcons.copy,
              size: AppIconSize.sm,
              color: p.textSecondary,
            ),
          ],
        ),
      ),
      if (d.builds.isNotEmpty) ...[
        const SettingsGroupHeader(ErrorsStrings.buildsHeader),
        SettingsGroup(
          entries: [
            for (final b in d.builds)
              GroupEntry(
                ListTile(
                  title: Text(ErrorsStrings.buildLabel(b.build)),
                  trailing: Text(
                    '${ErrorsStrings.users(b.users)} · ${ErrorsStrings.events(b.count)}',
                    style: context.text.caption.copyWith(
                      color: p.textSecondary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
      const SettingsGroupHeader(ErrorsStrings.samplesHeader),
      if (d.samples.isEmpty)
        const M3Card(child: Text(ErrorsStrings.noSamples))
      else
        for (final s in d.samples) ...[
          _SampleCard(
            sample: s,
            now: _now,
            email: _c.emails[s.id],
            onReveal: () => _c.revealUser(s.id),
          ),
          const SizedBox(height: ErrorsSizes.sampleSpacing),
        ],
    ];
  }
}

class _Act extends StatelessWidget {
  const _Act({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final AppIconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = primary ? p.accent : p.textPrimary;
    return TextButton.icon(
      onPressed: onTap,
      icon: AppIcon(icon, size: AppIconSize.sm, color: color),
      label: Text(label, style: context.text.label.copyWith(color: color)),
    );
  }
}

class _SampleCard extends StatelessWidget {
  const _SampleCard({
    required this.sample,
    required this.now,
    required this.email,
    required this.onReveal,
  });

  final ErrorSample sample;
  final DateTime now;

  /// null: not fetched; '' : none on record.
  final String? email;
  final VoidCallback onReveal;

  String _device() {
    final d = sample.device;
    return [
      for (final k in ['model', 'sdk', 'abi', 'locale', 'net', 'memBucket'])
        if (d[k] != null) '${d[k]}',
      if (d['fg'] == false) 'background',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = sample;
    final at = s.at;
    final device = _device();
    return M3Card(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            [
              ErrorsStrings.buildLabel(s.build),
              ?(at == null ? null : timeAgo(at, now)),
              s.kind,
            ].join(' · '),
            style: context.text.label,
          ),
          if (s.message.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(s.message, style: context.text.bodySmall),
          ],
          if (device.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                AppIcon(
                  ErrorsIcons.device,
                  size: AppIconSize.xs,
                  color: p.textTertiary,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    device,
                    style: context.text.caption.copyWith(color: p.textTertiary),
                  ),
                ),
              ],
            ),
          ],
          if (s.stack.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              ErrorsStrings.stackHeader,
              style: context.text.label.copyWith(color: p.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xs),
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              color: p.codeBackground,
              child: SelectableText(
                s.stack,
                maxLines: ErrorsSizes.stackMaxLines,
                style: context.text.caption,
              ),
            ),
          ],
          if (s.breadcrumbs.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              ErrorsStrings.breadcrumbsHeader,
              style: context.text.label.copyWith(color: p.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xs),
            for (final c in s.breadcrumbs)
              Text(
                c,
                style: context.text.caption.copyWith(color: p.textSecondary),
              ),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: Text(
                  email == null
                      ? s.user
                      : email!.isEmpty
                      ? ErrorsStrings.noEmail
                      : email!,
                  style: context.text.caption.copyWith(color: p.textTertiary),
                ),
              ),
              if (email == null)
                TextButton(
                  onPressed: () {
                    Haptics.tap();
                    onReveal();
                  },
                  child: Text(
                    ErrorsStrings.showUser,
                    style: context.text.label,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
