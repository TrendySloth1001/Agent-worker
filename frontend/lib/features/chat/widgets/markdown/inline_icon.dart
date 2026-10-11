import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'package:markdown/markdown.dart' as md;

import '../../../../core/constants/app_config.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../data/chat_api.dart';

/// `{{icon:SET:NAME}}` in a reply, e.g. `{{icon:logos:postgresql}}`.
const _pattern =
    r'\{\{icon:([a-z0-9]+(?:-[a-z0-9]+)*):([a-z0-9]+(?:-[a-z0-9]+)*)\}\}';

/// Drops an `{{icon:…}}` / `{{image:…}}` marker that is still being streamed
/// in, so `{{icon:lo` or `{{image:TCP hand` never shows.
String hidePartialIcon(String text) =>
    text.replaceFirst(RegExp(r'\{\{(?:[a-z]{0,5}(?::[^}\n]*)?)?\}?$'), '');

class IconSyntax extends md.InlineSyntax {
  IconSyntax() : super(_pattern);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text('icon', '${match[1]}:${match[2]}'));
    return true;
  }
}

class IconBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final parts = element.textContent.split(':');
    final style = parentStyle ?? context.text.body;
    // A Text.rich holding a WidgetSpan is merged into the surrounding
    // paragraph, so the icon sits in the line instead of wrapping alone.
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: InlineIcon(
              set: parts.first,
              name: parts.last,
              size:
                  (style.fontSize ?? AppIconSize.md) * AppSizes.inlineIconScale,
              color: style.color,
            ),
          ),
        ],
      ),
    );
  }
}

/// One Iconify icon. Unknown names render as nothing.
class InlineIcon extends StatefulWidget {
  const InlineIcon({
    super.key,
    required this.set,
    required this.name,
    required this.size,
    this.color,
    this.fallback,
  });

  final String set;
  final String name;
  final double size;
  final Color? color;

  /// Shown when no icon matches (instead of nothing).
  final Widget? fallback;

  @override
  State<InlineIcon> createState() => _InlineIconState();
}

class _InlineIconState extends State<InlineIcon> {
  ResolvedIcon? _icon;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(InlineIcon old) {
    super.didUpdateWidget(old);
    if (old.set != widget.set || old.name != widget.name) _resolve();
  }

  void _resolve() {
    _icon = IconCache.peek(widget.set, widget.name);
    if (_icon != null) return;
    final set = widget.set, name = widget.name;
    IconCache.load(set, name).then((icon) {
      if (!mounted || set != widget.set || name != widget.name) return;
      setState(() => _icon = icon);
    });
  }

  @override
  Widget build(BuildContext context) {
    final icon = _icon;
    if (icon != null && icon.svg.isEmpty && widget.fallback != null) {
      return widget.fallback!;
    }
    return SizedBox.square(
      dimension: widget.size,
      child: icon == null || icon.svg.isEmpty
          ? null
          : SvgPicture.string(
              icon.svg,
              width: widget.size,
              height: widget.size,
              // Tint by the icon actually returned: a requested color logo
              // may have been swapped for a monochrome one.
              colorFilter: AppConfig.colorIconSets.contains(icon.set)
                  ? null
                  : ColorFilter.mode(
                      widget.color ?? context.palette.textPrimary,
                      BlendMode.srcIn,
                    ),
            ),
    );
  }
}

/// An icon after the backend resolved it: [set] is the set it really came
/// from; an empty [svg] means no match.
class ResolvedIcon {
  const ResolvedIcon(this.set, this.svg);
  final String set;
  final String svg;
}

/// Fetches each icon once and keeps recent ones in memory. Misses are cached
/// too, so a bad name is asked for only once.
abstract final class IconCache {
  static final _icons = <String, ResolvedIcon>{};
  static final _pending = <String, Future<ResolvedIcon?>>{};
  static final _client = http.Client();

  static ResolvedIcon? peek(String set, String name) => _icons['$set:$name'];

  static Future<ResolvedIcon?> load(String set, String name) {
    final key = '$set:$name';
    final hit = _icons[key];
    if (hit != null) return Future.value(hit);
    return _pending[key] ??= _fetch(set, name).whenComplete(() {
      // A block body: returning the removed future here would make this
      // future wait on itself and never complete.
      _pending.remove(key);
    });
  }

  static Future<ResolvedIcon?> _fetch(String set, String name) async {
    final key = '$set:$name';
    try {
      final res = await _client
          .get(Uri.parse(AppConfig.iconUrl(set, name)), headers: apiHeaders())
          .timeout(AppDurations.iconFetchTimeout);
      final ok = res.statusCode == 200 && res.body.startsWith('<svg');
      final resolved = res.headers['x-icon-id'] ?? key;
      _remember(
        key,
        ResolvedIcon(resolved.split(':').first, ok ? _unsized(res.body) : ''),
      );
      return _icons[key];
    } catch (_) {
      // Network trouble: do not cache, so it can load next time.
      return null;
    }
  }

  /// Iconify sizes the root in `em` ("1.26em"), which flutter_svg cannot
  /// resolve and silently draws nothing. The widget sets the size, so the
  /// root width/height are dropped and the viewBox keeps the aspect ratio.
  static String _unsized(String svg) {
    final end = svg.indexOf('>');
    if (end < 0) return svg;
    final root = svg
        .substring(0, end)
        .replaceAll(RegExp(r'\s(width|height)="[^"]*"'), '');
    return root + svg.substring(end);
  }

  static void _remember(String key, ResolvedIcon icon) {
    _icons.remove(key);
    _icons[key] = icon;
    while (_icons.length > AppSizes.inlineIconCacheSize) {
      _icons.remove(_icons.keys.first);
    }
  }
}
