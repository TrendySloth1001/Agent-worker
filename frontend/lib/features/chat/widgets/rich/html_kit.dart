import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/widget_html.dart';

/// The design-kit stylesheet (assets/html/kit.css) in the three shapes the
/// pages need.
class HtmlKit {
  const HtmlKit({
    required this.web,
    required this.export,
    required this.enforce,
  });

  /// Defaults and components with the bundled fonts inlined as data: URIs
  /// (the WebView has no path to flutter assets under its https base URL).
  final String web;

  /// Same without the font block: the exported page links Google Fonts.
  final String export;

  /// `!important` rules that go after the author's CSS.
  final String enforce;

  static const empty = HtmlKit(web: '', export: '', enforce: '');

  static Future<HtmlKit>? _cached;

  /// Loaded once per run; falls back to no kit if the asset is unreadable.
  static Future<HtmlKit> load() => _cached ??= _read();

  static Future<HtmlKit> _read() async {
    try {
      final css = await rootBundle.loadString(HtmlWeb.kitAsset);
      final cut = css.indexOf(HtmlWeb.kitEnforceMark);
      final base = cut < 0 ? css : css.substring(0, cut);
      final enforce = cut < 0
          ? ''
          : css.substring(cut + HtmlWeb.kitEnforceMark.length);

      final start = base.indexOf(HtmlWeb.kitFontsStart);
      final end = base.indexOf(HtmlWeb.kitFontsEnd);
      if (start < 0 || end < start) {
        return HtmlKit(web: base, export: base, enforce: enforce);
      }
      final fonts = base.substring(start, end + HtmlWeb.kitFontsEnd.length);
      final export = base.replaceRange(
        start,
        end + HtmlWeb.kitFontsEnd.length,
        '',
      );

      var inlined = fonts;
      final re = RegExp(HtmlWeb.kitFontUrl);
      for (final m in re.allMatches(fonts)) {
        final data = await rootBundle.load(
          '${HtmlWeb.kitFontDir}${m.group(1)}',
        );
        final b64 = base64Encode(data.buffer.asUint8List());
        inlined = inlined.replaceFirst(
          m.group(0)!,
          'url(data:font/ttf;base64,$b64)',
        );
      }
      return HtmlKit(
        web: base.replaceRange(
          start,
          end + HtmlWeb.kitFontsEnd.length,
          inlined,
        ),
        export: export,
        enforce: enforce,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[html] kit load failed: $e');
      return HtmlKit.empty;
    }
  }
}
