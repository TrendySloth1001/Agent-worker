import '../../../../core/platform/browsers.dart';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../../core/constants/widget_html.dart';
import '../../../../core/theme/app_palette.dart';
import 'html_doc.dart';
import 'html_kit.dart';

/// Sandboxed WebView that renders one model-written HTML document.
///
/// JavaScript is on, file/content access is off, every navigation away from
/// the document is blocked and http(s)/mailto/tel links open externally.
class HtmlWebView extends StatefulWidget {
  const HtmlWebView({
    super.key,
    required this.source,
    this.onHeight,
    this.onFailed,
    this.zoom = false,
    this.captureVerticalDrag = false,
  });

  final String source;

  /// Content height in logical pixels, reported by the page.
  final ValueChanged<double>? onHeight;
  final VoidCallback? onFailed;
  final bool zoom;

  /// Lets the page scroll itself inside a scrolling parent.
  final bool captureVerticalDrag;

  @override
  State<HtmlWebView> createState() => _HtmlWebViewState();
}

class _HtmlWebViewState extends State<HtmlWebView> {
  late final WebViewController _controller;
  String? _themeSig;
  bool _loaded = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _onNavigation,
          onPageFinished: (_) => _loaded = true,
          onWebResourceError: (e) {
            if (e.isForMainFrame ?? true) widget.onFailed?.call();
          },
        ),
      )
      ..addJavaScriptChannel(
        HtmlWeb.channel,
        onMessageReceived: (m) {
          final h = double.tryParse(m.message);
          if (h != null && mounted) widget.onHeight?.call(h);
        },
      );
    if (widget.zoom) _controller.enableZoom(true);
  }

  NavigationDecision _onNavigation(NavigationRequest r) {
    final url = r.url;
    if (url == HtmlWeb.baseUrl ||
        url.startsWith('${HtmlWeb.baseUrl}#') ||
        url == 'about:blank') {
      return NavigationDecision.navigate;
    }
    final uri = Uri.tryParse(url);
    if (uri != null &&
        const {'http', 'https', 'mailto', 'tel'}.contains(uri.scheme)) {
      launchUrl(uri, mode: LaunchMode.externalApplication).catchError((_) {
        return false;
      });
    }
    return NavigationDecision.prevent;
  }

  HtmlTheme _theme(BuildContext context) {
    final p = context.palette;
    return HtmlTheme(bg: p.background, dark: p.isDark);
  }

  int _loadId = 0;

  Future<void> _load(HtmlTheme theme) async {
    _loaded = false;
    final id = ++_loadId;
    final kit = await HtmlKit.load();
    if (!mounted || id != _loadId) return;
    await _controller.loadHtmlString(
      HtmlDoc.prepare(widget.source, theme, kit),
      baseUrl: HtmlWeb.baseUrl,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final theme = _theme(context);
    if (_themeSig != theme.signature) {
      _themeSig = theme.signature;
      _controller.setBackgroundColor(theme.bg);
      if (!_started || _loaded) {
        _started = true;
        _load(theme);
      }
    }
  }

  @override
  void didUpdateWidget(covariant HtmlWebView old) {
    super.didUpdateWidget(old);
    if (old.source != widget.source) _load(_theme(context));
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(
      controller: _controller,
      gestureRecognizers: {
        if (widget.captureVerticalDrag)
          Factory<VerticalDragGestureRecognizer>(
            VerticalDragGestureRecognizer.new,
          ),
        if (widget.zoom)
          Factory<EagerGestureRecognizer>(EagerGestureRecognizer.new),
      },
    );
  }
}

/// Opens [html] (with the kit inlined and the current theme) in the device
/// browser. Returns false when
/// nothing could take it.
Future<bool> openHtmlInBrowser(
  String html, {
  required HtmlKit kit,
  required bool dark,
  String package = '',
}) async {
  try {
    final doc = HtmlDoc.forBrowser(html, kit, dark: dark);
    if (Browsers.supported) {
      return await Browsers.openHtml(
        doc,
        title: HtmlDoc.title(html) ?? '',
        package: package,
      );
    }
    if (doc.length > HtmlSizes.maxBrowserChars) return false;
    final uri = Uri.dataFromString(
      doc,
      mimeType: 'text/html',
      encoding: utf8,
      base64: true,
    );
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (e) {
    if (kDebugMode) debugPrint('[html] browser open failed: $e');
    return false;
  }
}
