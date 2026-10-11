import 'package:flutter/painting.dart';

import '../../../../core/constants/widget_html.dart';
import 'html_kit.dart';

/// What the page needs to know about the app theme: the kit CSS picks its
/// colours from the `theme-dark` / `theme-light` class set on the root element.
class HtmlTheme {
  const HtmlTheme({required this.bg, required this.dark});

  /// WebView backdrop while the page paints.
  final Color bg;
  final bool dark;

  String get signature => '${bg.toARGB32()}$dark';
}

/// Pure helpers that turn the model's HTML into a safe, themed document.
abstract final class HtmlDoc {
  static final _fence = RegExp(r'^\s*```[a-zA-Z]*\s*\n([\s\S]*?)\n?```\s*$');
  static final _titleTag = RegExp(
    r'<title[^>]*>([\s\S]*?)</title>',
    caseSensitive: false,
  );
  static final _doctype = RegExp(r'<!doctype', caseSensitive: false);
  static final _htmlTag = RegExp(r'<html[^>]*>', caseSensitive: false);
  static final _headTag = RegExp(r'<head[^>]*>', caseSensitive: false);
  static final _viewportMeta = RegExp(
    r'<meta[^>]+name\s*=\s*["\x27]?viewport',
    caseSensitive: false,
  );
  static final _tag = RegExp(r'<[a-zA-Z!][^>]*>');

  /// Removes an accidental markdown fence the model left inside the block.
  static String clean(String source) {
    final m = _fence.firstMatch(source);
    return (m != null ? m.group(1)! : source).trim();
  }

  /// Document title, or null when there is none.
  static String? title(String html) {
    final raw = _titleTag.firstMatch(html)?.group(1);
    if (raw == null) return null;
    var t = raw
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (t.isEmpty) return null;
    if (t.length > HtmlSizes.titleMaxChars) {
      t = '${t.substring(0, HtmlSizes.titleMaxChars - 1)}…';
    }
    return t;
  }

  /// True when there is something worth rendering.
  static bool isRenderable(String html) =>
      html.trim().isNotEmpty && _tag.hasMatch(html);

  static final _bodyClose = RegExp(r'</body\s*>', caseSensitive: false);

  /// Kit pieces injected before the author's markup (tokens, defaults,
  /// components: all easy to override) ...
  static String _head(HtmlKit kit, bool dark, {required bool web}) =>
      '${HtmlWeb.charset}'
      '${web ? '<meta http-equiv="Content-Security-Policy" content="${HtmlWeb.csp}">' : ''}'
      '${web ? '' : HtmlWeb.exportFonts}'
      '<style>${web ? kit.web : kit.export}</style>'
      '<script>${HtmlWeb.themeScript(dark)}</script>'
      '${web ? '<script>${HtmlWeb.script}</script>' : ''}';

  /// ... and after it: the enforcement rules and cleaners.
  static String _tail(HtmlKit kit, String html) =>
      '<style>${kit.enforce}</style>'
      '<script>${HtmlWeb.cleanScript}</script>'
      '${html.toLowerCase().contains('<${HtmlWeb.iconifyTag}') ? HtmlWeb.iconifyScript : ''}';

  static String _assemble(
    String source,
    String head,
    String Function(String) tail,
  ) {
    final html = clean(source);
    final withViewport = _viewportMeta.hasMatch(html)
        ? head
        : '$head${HtmlWeb.viewport}';
    final t = tail(html);

    String body;
    final close = _bodyClose.allMatches(html).lastOrNull;
    if (close != null) {
      body = html.replaceRange(close.start, close.start, t);
    } else {
      body = '$html$t';
    }

    final headTag = _headTag.firstMatch(body);
    if (headTag != null) {
      return _withDoctype(
        body.replaceRange(headTag.end, headTag.end, withViewport),
      );
    }
    final root = _htmlTag.firstMatch(body);
    if (root != null) {
      return _withDoctype(
        body.replaceRange(root.end, root.end, '<head>$withViewport</head>'),
      );
    }
    // Fragment: wrap it. A stray <body> tag inside is tolerated by browsers.
    return '<!doctype html><html><head>$withViewport'
        '</head><body>$body</body></html>';
  }

  /// Full document for the in-app WebView: CSP, viewport, themed kit with the
  /// bundled fonts, enforcement rules and the height reporter, whatever shape
  /// the source has.
  static String prepare(String source, HtmlTheme theme, HtmlKit kit) =>
      _assemble(
        source,
        _head(kit, theme.dark, web: true),
        (html) => _tail(kit, html),
      );

  /// Document for the external browser: the same kit inlined, web fonts from
  /// Google Fonts, the current theme class, no CSP and no height reporter.
  static String forBrowser(String source, HtmlKit kit, {required bool dark}) =>
      _assemble(
        source,
        _head(kit, dark, web: false),
        (html) => _tail(kit, html),
      );

  static String _withDoctype(String html) =>
      _doctype.hasMatch(html) ? html : '<!doctype html>$html';
}
