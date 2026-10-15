import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/app_scope.dart';
import '../../../core/platform/browsers.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/settings_copy.dart';
import '../../../core/haptics.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../data/files_api.dart';
import '../../settings/widgets/dot_matrix.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/constants/preview.dart';
import '../../../core/constants/connectors.dart';
import '../../../data/drive_ref.dart';
import '../../connectors/connector_actions.dart';
import 'file_actions.dart';
import 'file_info.dart';
import 'preview_view.dart';

/// Fresh signed URL for a file. Signed URLs expire after an hour, so a
/// server file always goes through GET /files/:id (cached while valid); the
/// URL we hold is only a fallback.
Future<String?> resolveFileUrl(FileInfo f, {bool force = false}) async {
  if (f.deleted) return null;
  if (f.id.isEmpty) return f.url;
  try {
    return (await FilesApi.instance.get(f.id, force: force)).url;
  } catch (_) {
    return force ? null : f.url;
  }
}

void _notice(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// OPEN EXTERNALLY and COPY LINK, shared by every preview app bar.
/// [url] may be null while the file only exists on this phone.
class PreviewActions extends StatelessWidget {
  const PreviewActions({super.key, this.file, this.url});

  /// Used to fetch a fresh link when [url] is not given.
  final FileInfo? file;
  final String? url;

  Future<String?> _link() async {
    if (url != null && url!.isNotEmpty) return url;
    final f = file;
    return f == null ? null : resolveFileUrl(f);
  }

  Future<void> _open(BuildContext context) async {
    Haptics.tap();
    final link = await _link();
    final uri = link == null ? null : Uri.tryParse(link);
    var opened = false;
    if (uri != null && context.mounted) {
      opened = await Browsers.openUrl(
        uri.toString(),
        package: AppScope.of(context).settings.browserPackage,
      );
    }
    if (opened || !context.mounted) return;
    Haptics.error();
    _notice(
      context,
      link == null ? AppStrings.previewNoLink : AppStrings.cantOpenLink,
    );
  }

  Future<void> _copy(BuildContext context) async {
    Haptics.tap();
    final link = await _link();
    if (link == null) {
      if (!context.mounted) return;
      Haptics.error();
      _notice(context, AppStrings.previewNoLink);
      return;
    }
    await Clipboard.setData(ClipboardData(text: link));
    if (context.mounted) _notice(context, AppStrings.previewLinkCopied);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const AppIcon(AppIcons.openExternal, size: AppIconSize.md),
          tooltip: AppStrings.previewOpen,
          onPressed: () => _open(context),
        ),
        IconButton(
          icon: const AppIcon(AppIcons.link, size: AppIconSize.md),
          tooltip: AppStrings.previewCopyLink,
          onPressed: () => _copy(context),
        ),
      ],
    );
  }
}

/// Centered state for a preview that is processing or failed to load: dot
/// grid, a Space Grotesk message, an optional hint and a tonal retry button.
class PreviewMessage extends StatelessWidget {
  const PreviewMessage({
    super.key,
    required this.title,
    this.hint,
    this.error = false,
    this.onRetry,
    this.action,
  });

  final String title;
  final String? hint;
  final bool error;
  final VoidCallback? onRetry;

  /// A custom button under the message (instead of RETRY).
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const DotGrid(size: SettingsSizes.emptyDots),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: tt.titleMedium!.copyWith(
                color: error ? scheme.error : scheme.onSurface,
              ),
            ),
            if (hint != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                hint!,
                textAlign: TextAlign.center,
                style: tt.bodyMedium!.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpacing.lg),
              action!,
            ] else if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.lg),
              FilledButton.tonal(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, AppSizes.buttonHeight),
                ),
                onPressed: () {
                  Haptics.tap();
                  onRetry!();
                },
                child: const Text(AppStrings.retry),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum _MenuAction { share, download, openWith, copyLink, info, addToKb, delete }

/// ASK SPARKY button and the overflow menu (share, download, open with,
/// copy link, info, delete) shared by every preview app bar.
class PreviewMenu extends StatelessWidget {
  const PreviewMenu({super.key, required this.file, this.color});

  final FileInfo file;

  /// Icon color on an immersive (dark) bar.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (canAskAboutFile(file))
          IconButton(
            icon: AppIcon(PreviewIcons.ask, size: AppIconSize.md, color: color),
            tooltip: PreviewStrings.ask,
            onPressed: () => askAboutFile(context, file),
          ),
        PopupMenuButton<_MenuAction>(
          tooltip: PreviewStrings.more,
          icon: AppIcon(PreviewIcons.more, size: AppIconSize.md, color: color),
          onOpened: Haptics.tap,
          onSelected: (a) => switch (a) {
            _MenuAction.share => shareFile(context, file),
            _MenuAction.download => downloadFile(context, file),
            _MenuAction.openWith => openFileWith(context, file),
            _MenuAction.copyLink => _copyLink(context, file),
            _MenuAction.info => showFileInfoSheet(context, file),
            _MenuAction.addToKb => addItemToKnowledge(
              context,
              provider: ConnectorIds.drive,
              id: file.driveFileId ?? '',
            ),
            _MenuAction.delete => deleteFileWithConfirm(context, file),
          },
          itemBuilder: (_) => [
            for (final (a, icon, label) in [
              (_MenuAction.share, PreviewIcons.share, PreviewStrings.share),
              (
                _MenuAction.download,
                PreviewIcons.download,
                PreviewStrings.download,
              ),
              (
                _MenuAction.openWith,
                PreviewIcons.openWith,
                PreviewStrings.openWith,
              ),
              (_MenuAction.copyLink, AppIcons.link, AppStrings.previewCopyLink),
              (_MenuAction.info, PreviewIcons.info, PreviewStrings.info),
              if (file.isDrive)
                (
                  _MenuAction.addToKb,
                  AppIcons.knowledge,
                  PreviewStrings.addToKb,
                ),
            ])
              if (a != _MenuAction.copyLink || file.id.isNotEmpty)
                PopupMenuItem(
                  value: a,
                  child: Row(
                    children: [
                      AppIcon(icon, size: AppIconSize.md),
                      const SizedBox(width: AppSpacing.md),
                      Text(label),
                    ],
                  ),
                ),
            if (canDeleteFile(file))
              PopupMenuItem(
                value: _MenuAction.delete,
                child: Row(
                  children: [
                    AppIcon(
                      PreviewIcons.delete,
                      size: AppIconSize.md,
                      color: p.accent,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Text(
                      PreviewStrings.delete,
                      style: TextStyle(color: p.accent),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

Future<void> _copyLink(BuildContext context, FileInfo file) async {
  Haptics.tap();
  final link = await resolveFileUrl(file);
  if (!context.mounted) return;
  if (link == null) {
    previewNotice(context, AppStrings.previewNoLink, error: true);
    return;
  }
  await Clipboard.setData(ClipboardData(text: link));
  if (context.mounted) previewNotice(context, AppStrings.previewLinkCopied);
}

/// SHARE, OPEN WITH… and DOWNLOAD as buttons, for cards that have nothing
/// to draw (unknown types, Office files).
class FileActionButtons extends StatelessWidget {
  const FileActionButtons({
    super.key,
    required this.file,
    this.compact = false,
  });

  final FileInfo file;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    Widget button(AppIconData icon, String label, VoidCallback onTap) =>
        FilledButton.tonalIcon(
          style: FilledButton.styleFrom(
            minimumSize: Size(
              0,
              compact ? PreviewSizes.compactButton : AppSizes.buttonHeight,
            ),
          ),
          icon: AppIcon(icon, size: AppIconSize.md),
          label: Text(label),
          onPressed: onTap,
        );
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        button(
          PreviewIcons.openWith,
          PreviewStrings.openWith,
          () => openFileWith(context, file),
        ),
        button(
          PreviewIcons.share,
          PreviewStrings.share,
          () => shareFile(context, file),
        ),
        button(
          PreviewIcons.download,
          PreviewStrings.download,
          () => downloadFile(context, file),
        ),
      ],
    );
  }
}

/// Standard preview app bar: back, file name, actions. [immersive] gives
/// the dark transparent bar used over images and video.
class PreviewBar extends StatelessWidget implements PreferredSizeWidget {
  const PreviewBar({
    super.key,
    required this.file,
    this.extra = const [],
    this.immersive = false,
    this.view,
    this.onView,
  });

  final FileInfo file;
  final List<Widget> extra;
  final bool immersive;

  /// With [onView], the ORIGINAL | SPARKY switch sits under the bar.
  final PreviewView? view;
  final ValueChanged<PreviewView>? onView;

  bool get _switchable => view != null && onView != null;

  @override
  Size get preferredSize => Size.fromHeight(
    kToolbarHeight + (_switchable ? PreviewSizes.toggleBarHeight : 0),
  );

  @override
  Widget build(BuildContext context) {
    final fg = immersive ? AppColors.white : null;
    return AppBar(
      backgroundColor: immersive ? Colors.transparent : null,
      foregroundColor: fg,
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: IconButton(
        icon: AppIcon(AppIcons.back, size: AppIconSize.md, color: fg),
        tooltip: AppStrings.back,
        onPressed: () {
          Haptics.tap();
          Navigator.pop(context);
        },
      ),
      title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      bottom: _switchable
          ? PreferredSize(
              preferredSize: const Size.fromHeight(
                PreviewSizes.toggleBarHeight,
              ),
              child: PreviewViewToggle(
                view: view!,
                onChanged: onView!,
                dark: immersive,
              ),
            )
          : null,
      actions: [
        ...extra,
        PreviewMenu(file: file, color: fg),
      ],
    );
  }
}
