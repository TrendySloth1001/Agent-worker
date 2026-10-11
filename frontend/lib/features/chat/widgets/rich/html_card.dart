import 'package:flutter/material.dart';

import '../../../../core/constants/app_icons.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/widget_html.dart';
import '../../../../core/constants/widget_kit.dart';
import '../../../../core/haptics.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/browser_picker.dart';
import 'html_doc.dart';
import 'html_fullscreen.dart';
import 'html_kit.dart';
import 'html_source.dart';
import 'html_view.dart';
import 'rich_frame.dart';

/// Renders the model's HTML page inline in a sandboxed WebView that sizes
/// itself to the content (capped, with EXPAND), plus fullscreen, source,
/// copy and open-in-browser.
class HtmlCard extends StatefulWidget {
  const HtmlCard({super.key, required this.source});

  /// Raw fenced-block body.
  final String source;

  @override
  State<HtmlCard> createState() => _HtmlCardState();
}

class _HtmlCardState extends State<HtmlCard> {
  late final String _html = HtmlDoc.clean(widget.source);
  late final bool _cut = HtmlDoc.isTruncated(widget.source);
  double _content = 0;
  bool _showSource = false;
  bool _expanded = false;
  bool _failed = false;

  bool get _tooLarge => _html.length > HtmlSizes.maxSourceChars;
  bool get _renderable => HtmlDoc.isRenderable(_html);
  bool get _overflows => _content > HtmlSizes.maxHeight;

  /// Taller than even the expanded card: only then does the page scroll
  /// inside the card (collapsed pages never do, so there is one scroller).
  bool get _scrollsInside =>
      _expanded && _content > HtmlSizes.expandedMaxHeight;

  double get _height {
    if (_content <= 0) return HtmlSizes.minHeight;
    final cap = _expanded ? HtmlSizes.expandedMaxHeight : HtmlSizes.maxHeight;
    return _content.clamp(HtmlSizes.minHeight, cap);
  }

  void _onHeight(double h) {
    if ((h - _content).abs() < HtmlSizes.heightEpsilon) return;
    setState(() => _content = h);
  }

  void _fullscreen(bool source) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => HtmlFullscreen(source: _html, startOnSource: source),
      ),
    );
  }

  Future<bool> _browser() async {
    final package = await pickOrRemembered(context);
    if (package == null) return true;
    final kit = await HtmlKit.load();
    if (!mounted) return true;
    final dark = context.palette.isDark;
    final ok = await openHtmlInBrowser(
      _html,
      kit: kit,
      dark: dark,
      package: package,
    );
    if (!ok && mounted) {
      final tooBig =
          HtmlDoc.forBrowser(_html, kit, dark: dark).length >
          HtmlSizes.maxBrowserChars;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: context.palette.surfaceHigh,
          content: Text(
            tooBig ? HtmlStrings.browserTooLarge : HtmlStrings.browserFailed,
            style: context.text.label,
          ),
        ),
      );
      Haptics.error();
      // The snack above replaces RichAction's generic one.
      return true;
    }
    return ok;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;

    if (!_renderable) {
      return RichCard(
        title: WidgetKitStrings.html,
        leading: AppIcon(AppIcons.code, size: AppIconSize.sm, color: p.accent),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: SelectableText(widget.source, style: t.code),
        ),
      );
    }

    final sourceOnly = _tooLarge || _failed;
    final showSource = _showSource || sourceOnly;
    final title = HtmlDoc.title(_html);

    return RichCard(
      title: title == null
          ? WidgetKitStrings.html
          : '${WidgetKitStrings.html}${HtmlStrings.separator}'
                '${title.toUpperCase()}',
      leading: AppIcon(AppIcons.web, size: AppIconSize.sm, color: p.accent),
      actions: [
        if (!sourceOnly)
          RichAction(
            icon: AppIcons.fullscreen,
            label: HtmlStrings.fullscreen,
            onTap: () async {
              _fullscreen(false);
              return true;
            },
          ),
        if (!sourceOnly)
          RichAction(
            icon: showSource ? AppIcons.web : AppIcons.code,
            label: showSource ? HtmlStrings.preview : HtmlStrings.source,
            onTap: () async {
              setState(() => _showSource = !_showSource);
              return true;
            },
          ),
        if (!showSource && _overflows)
          RichAction(
            icon: _expanded ? AppIcons.collapse : AppIcons.expand,
            label: _expanded ? HtmlStrings.collapse : HtmlStrings.expand,
            onTap: () async {
              setState(() => _expanded = !_expanded);
              return true;
            },
          ),
        RichAction.copy(text: _html, label: HtmlStrings.copyHtml),
        if (!_tooLarge)
          RichAction(
            icon: AppIcons.openExternal,
            label: HtmlStrings.browser,
            onTap: _browser,
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_cut && !sourceOnly)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              child: Text(
                HtmlStrings.truncated,
                style: t.caption.copyWith(color: p.accent),
              ),
            ),
          _body(context, showSource: showSource, sourceOnly: sourceOnly),
        ],
      ),
    );
  }

  Widget _body(
    BuildContext context, {
    required bool showSource,
    required bool sourceOnly,
  }) {
    final p = context.palette;
    final t = context.text;
    return showSource
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (sourceOnly)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.sm,
                    AppSpacing.md,
                    0,
                  ),
                  child: Text(
                    _tooLarge ? HtmlStrings.tooLarge : HtmlStrings.failed,
                    style: t.caption.copyWith(color: p.accent),
                  ),
                ),
              HtmlSourceView(
                source: _html,
                maxHeight: HtmlSizes.sourceMaxHeight,
              ),
            ],
          )
        : AnimatedContainer(
            duration: AppDurations.normal,
            curve: Curves.easeOut,
            height: _height,
            child: Stack(
              children: [
                Positioned.fill(
                  child: HtmlWebView(
                    source: _html,
                    onHeight: _onHeight,
                    onFailed: () => setState(() => _failed = true),
                    captureVerticalDrag: _scrollsInside,
                  ),
                ),
                if (_overflows && !_expanded)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: HtmlSizes.fadeHeight,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              p.background.withValues(alpha: 0),
                              p.background,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                if (_content <= 0)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: LinearProgressIndicator(
                      minHeight: HtmlSizes.progressHeight,
                      color: p.accent,
                      backgroundColor: p.border,
                    ),
                  ),
              ],
            ),
          );
  }
}
