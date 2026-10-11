import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/app_scope.dart';
import '../../../core/platform/browsers.dart';
import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../data/files_api.dart';

/// Fresh signed URL for a file: the one we hold, else GET /files/:id.
Future<String?> resolveFileUrl(FileInfo f, {bool force = false}) async {
  if (!force && f.url != null) return f.url;
  if (f.id.isEmpty) return null;
  try {
    return (await FilesApi.instance.get(f.id, force: force)).url;
  } catch (_) {
    return null;
  }
}

void _notice(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text, style: context.text.label)));
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

/// Standard preview app bar: back, file name, actions.
class PreviewBar extends StatelessWidget implements PreferredSizeWidget {
  const PreviewBar({super.key, required this.file, this.extra = const []});

  final FileInfo file;
  final List<Widget> extra;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      leading: IconButton(
        icon: const AppIcon(AppIcons.back, size: AppIconSize.md),
        tooltip: AppStrings.back,
        onPressed: () {
          Haptics.tap();
          Navigator.pop(context);
        },
      ),
      title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      actions: [
        ...extra,
        PreviewActions(file: file),
      ],
    );
  }
}
