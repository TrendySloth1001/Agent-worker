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

  static final _fenceLine = RegExp(
    r'^[ \t]*```[a-zA-Z]*[ \t]*$',
    multiLine: true,
  );
  static final _docStart = RegExp(
    r'<!doctype|<html[\s>]',
    caseSensitive: false,
  );
  static final _htmlClose = RegExp(r'</html\s*>', caseSensitive: false);
  static final _textIcon = RegExp(r'\{\{icon:([\w-]+:[\w-]+)\}\}');
  static final _raw = RegExp(
    r'<(script|style|pre|code|textarea)\b[\s\S]*?</\1\s*>',
    caseSensitive: false,
  );
  static final _mdBold = RegExp(r'\*\*([^*<>\n]{1,120}?)\*\*');
  static final _extScript = RegExp(
    r'''<script\b[^>]*\bsrc\s*=\s*["']?(?:https?:)?//([^/"'\s>]+)[^>]*>[\s\S]*?</script\s*>''',
    caseSensitive: false,
  );
  static final _extLink = RegExp(
    r'''<link\b[^>]*\bhref\s*=\s*["']?(?:https?:)?//([^/"'\s>]+)[^>]*>''',
    caseSensitive: false,
  );
  static final _fontImport = RegExp(
    r'''@import\s+url\(\s*["']?https?://fonts\.googleapis\.com[^)]*\)\s*;?''',
    caseSensitive: false,
  );

  /// Model output -> renderable page: drops markdown fences and prose around
  /// the document, turns `{{icon:..}}` and `**bold**` that leaked in from
  /// chat markdown into HTML, removes scripts/stylesheets from hosts the CSP
  /// blocks, and repairs a cut-off ending (see [isTruncated]).
  static String clean(String source) {
    final m = _fence.firstMatch(source);
    var html = (m != null ? m.group(1)! : source).replaceAll(_fenceLine, '');

    final start = _docStart.firstMatch(html);
    if (start != null) html = html.substring(start.start);
    final end = _htmlClose.allMatches(html).lastOrNull;
    if (end != null) html = html.substring(0, end.end);

    html = html.replaceAllMapped(
      _textIcon,
      (m) =>
          '<${HtmlWeb.iconifyTag} icon="${m.group(1)}"></${HtmlWeb.iconifyTag}>',
    );
    html = _outsideRaw(
      html,
      (s) =>
          s.replaceAllMapped(_mdBold, (m) => '<strong>${m.group(1)}</strong>'),
    );
    html = html
        .replaceAllMapped(
          _extScript,
          (m) => _allowed(m.group(1)!) ? m.group(0)! : '',
        )
        .replaceAllMapped(_extLink, (m) {
          final tag = m.group(0)!.toLowerCase();
          final sheet = tag.contains('stylesheet');
          return sheet && _allowed(m.group(1)!) ? m.group(0)! : '';
        })
        .replaceAll(_fontImport, '');
    return _repair(html).trim();
  }

  static bool _allowed(String host) =>
      HtmlWeb.allowedHosts.contains(host.toLowerCase());

  static String _outsideRaw(String html, String Function(String) f) {
    final out = StringBuffer();
    var at = 0;
    for (final m in _raw.allMatches(html)) {
      out
        ..write(f(html.substring(at, m.start)))
        ..write(m.group(0));
      at = m.end;
    }
    out.write(f(html.substring(at)));
    return out.toString();
  }

  static final _partialTag = RegExp(r'<[^<>]*$');

  /// Cuts what a truncated reply leaves broken: a half-written tag, and an
  /// unclosed comment, script or style (which would swallow the rest).
  /// The browser closes ordinary elements by itself.
  static String _repair(String html) {
    var out = html.replaceFirst(_partialTag, '');
    for (final open in const ['<!--', '<script', '<style']) {
      final close = open == '<!--' ? '-->' : '</${open.substring(1)}';
      final lower = out.toLowerCase();
      final o = lower.lastIndexOf(open);
      if (o >= 0 && lower.indexOf(close, o) < 0) out = out.substring(0, o);
    }
    return out;
  }

  static final _bodyOpen = RegExp(r'<(html|body)[\s>]', caseSensitive: false);
  static final _docEnd = RegExp(r'</(html|body)\s*>', caseSensitive: false);

  /// True when the reply ended mid-document (output cap or dropped stream).
  static bool isTruncated(String source) {
    final m = _fence.firstMatch(source);
    final html = (m != null ? m.group(1)! : source).trim();
    if (html.isEmpty) return false;
    if (_partialTag.hasMatch(html)) return true;
    final lower = html.toLowerCase();
    for (final (open, close) in const [
      ('<!--', '-->'),
      ('<script', '</script'),
      ('<style', '</style'),
    ]) {
      final o = lower.lastIndexOf(open);
      if (o >= 0 && lower.indexOf(close, o) < 0) return true;
    }
    return _bodyOpen.hasMatch(html) && !_docEnd.hasMatch(html);
  }

  static final _vh = RegExp(r'(\d+(?:\.\d+)?)[dsl]?vh\b');
  static final _styleBlock = RegExp(
    r'<style\b[\s\S]*?</style\s*>|\bstyle\s*=\s*"[^"]*"',
    caseSensitive: false,
  );

  /// In-app only: viewport heights become fixed pixels (the WebView is sized
  /// to its content, so `100vh` would grow it forever).
  static String _fixedVh(String html) => html.replaceAllMapped(
    _styleBlock,
    (m) => m
        .group(0)!
        .replaceAllMapped(
          _vh,
          (v) => '${(double.parse(v.group(1)!) * HtmlSizes.vhPx).round()}px',
        ),
  );

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
      '${web ? '<style>${HtmlWeb.webStyle}</style>' : ''}'
      '<script>${HtmlWeb.themeScript(dark)}</script>'
      '<script>${HtmlWeb.guardScript()}</script>'
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
        _fixedVh(clean(source)),
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
