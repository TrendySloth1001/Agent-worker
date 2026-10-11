import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/theme/app_palette.dart';

/// Result reported by the page: a content height, or a syntax error.
sealed class MermaidResult {
  const MermaidResult();
}

class MermaidSized extends MermaidResult {
  const MermaidSized(this.height);
  final double height;
}

class MermaidFailed extends MermaidResult {
  const MermaidFailed(this.message);
  final String message;
}

/// One WebView that renders a single Mermaid diagram from the bundled asset.
/// Navigation away from the local page is blocked.
class MermaidView extends StatefulWidget {
  const MermaidView({
    super.key,
    required this.source,
    required this.onResult,
    this.full = false,
  });

  final String source;
  final bool full;
  final ValueChanged<MermaidResult> onResult;

  @override
  State<MermaidView> createState() => _MermaidViewState();
}

class _MermaidViewState extends State<MermaidView> {
  late final WebViewController _controller;
  Map<String, String>? _vars;
  bool _loaded = false;
  Timer? _timeout;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) => request.url.startsWith('file:')
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
          onPageFinished: (url) {
            if (kDebugMode) debugPrint('[mermaid] page finished $url');
            _loaded = true;
            _render();
          },
          onWebResourceError: (e) {
            if (kDebugMode) {
              debugPrint(
                '[mermaid] resource error ${e.errorCode} ${e.description} ${e.url}',
              );
            }
            _report(const MermaidFailed('page failed to load'));
          },
        ),
      )
      ..setOnConsoleMessage((m) {
        if (kDebugMode) debugPrint('[mermaid] ${m.level.name}: ${m.message}');
      })
      ..addJavaScriptChannel('Mermaid', onMessageReceived: _onMessage)
      ..loadFlutterAsset('assets/mermaid/diagram.html');
    if (widget.full) _controller.enableZoom(true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final vars = context.palette.mermaidVars();
    final changed = _vars != null && _vars.toString() != vars.toString();
    _vars = vars;
    if (changed && _loaded) _render();
  }

  @override
  void dispose() {
    _timeout?.cancel();
    super.dispose();
  }

  void _report(MermaidResult result) {
    if (kDebugMode) {
      debugPrint(switch (result) {
        MermaidSized(:final height) => '[mermaid] sized $height',
        MermaidFailed(:final message) => '[mermaid] failed: $message',
      });
    }
    _timeout?.cancel();
    if (mounted) widget.onResult(result);
  }

  void _onMessage(JavaScriptMessage message) {
    try {
      final data = jsonDecode(message.message) as Map<String, dynamic>;
      if (data['type'] == 'size') {
        _report(MermaidSized((data['height'] as num).toDouble()));
      } else {
        _report(MermaidFailed(data['message'] as String? ?? ''));
      }
    } catch (_) {
      _report(const MermaidFailed('bad response'));
    }
  }

  void _render() {
    final vars = _vars;
    if (vars == null) return;
    _timeout?.cancel();
    _timeout = Timer(
      AppDurations.diagramTimeout,
      () => _report(const MermaidFailed('timeout')),
    );
    final mode = widget.full ? 'full' : 'inline';
    _controller.runJavaScript(
      'renderDiagram(${jsonEncode(widget.source)}, ${jsonEncode(vars)}, '
      '${jsonEncode(mode)}, ${AppSizes.mermaidMaxInlineHeight});',
    );
  }

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _controller);
}
