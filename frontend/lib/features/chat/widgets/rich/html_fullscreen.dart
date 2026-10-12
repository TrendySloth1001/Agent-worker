import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_icons.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/constants/widget_html.dart';
import '../../../../core/haptics.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/system_chrome.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/copy_action.dart';
import '../../../../core/widgets/browser_picker.dart';
import 'html_doc.dart';
import 'html_kit.dart';
import 'html_source.dart';
import 'html_view.dart';

/// Full-screen page with zoom, a PREVIEW / SOURCE toggle and BROWSER.
class HtmlFullscreen extends StatefulWidget {
  const HtmlFullscreen({super.key, required this.source, this.startOnSource});

  final String source;
  final bool? startOnSource;

  @override
  State<HtmlFullscreen> createState() => _HtmlFullscreenState();
}

class _HtmlFullscreenState extends State<HtmlFullscreen> {
  late bool _source = widget.startOnSource ?? false;
  bool _failed = false;

  Future<void> _browser() async {
    Haptics.tap();
    final package = await pickOrRemembered(context);
    if (package == null || !mounted) return;
    final kit = await HtmlKit.load();
    if (!mounted) return;
    final dark = context.palette.isDark;
    final ok = await openHtmlInBrowser(
      widget.source,
      kit: kit,
      dark: dark,
      package: package,
    );
    if (ok || !mounted) return;
    Haptics.error();
    final tooBig =
        HtmlDoc.forBrowser(widget.source, kit, dark: dark).length >
        HtmlSizes.maxBrowserChars;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          tooBig ? HtmlStrings.browserTooLarge : HtmlStrings.browserFailed,
        ),
      ),
    );
  }

  Widget _action(String label, AppIconData icon, VoidCallback onTap) {
    final p = context.palette;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Haptics.tap();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(icon, size: AppIconSize.sm, color: p.textTertiary),
            const SizedBox(width: AppSpacing.xs),
            Text(label, style: context.text.caption),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final showSource = _source || _failed;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: systemOverlayFor(context),
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const AppIcon(AppIcons.back, size: AppIconSize.md),
            tooltip: AppStrings.back,
            onPressed: () {
              Haptics.tap();
              Navigator.pop(context);
            },
          ),
          title: Text(
            HtmlDoc.title(widget.source) ?? HtmlStrings.screenTitle,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            if (!_failed)
              _action(
                _source ? HtmlStrings.preview : HtmlStrings.source,
                _source ? AppIcons.web : AppIcons.code,
                () => setState(() => _source = !_source),
              ),
            _action(HtmlStrings.browser, AppIcons.openExternal, _browser),
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.screenPadding),
              child: Center(child: CopyAction(text: widget.source)),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(AppBorder.thin),
            child: Divider(color: p.border),
          ),
        ),
        body: SafeArea(
          child: showSource
              ? HtmlSourceView(source: HtmlDoc.clean(widget.source))
              : HtmlWebView(
                  source: widget.source,
                  zoom: true,
                  onFailed: () => setState(() => _failed = true),
                ),
        ),
      ),
    );
  }
}
