import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/app_strings.dart';

/// A browser app installed on the device.
class InstalledBrowser {
  const InstalledBrowser({
    required this.package,
    required this.label,
    required this.isDefault,
    this.icon,
  });

  final String package;
  final String label;
  final bool isDefault;
  final Uint8List? icon;
}

/// Android bridge for listing browsers and opening links or pages in one.
abstract final class Browsers {
  static const _channel = MethodChannel(BrowserStrings.channel);

  static bool get supported => !kIsWeb && Platform.isAndroid;

  /// Every app that handles https links, the system default first.
  static Future<List<InstalledBrowser>> list() async {
    if (!supported) return const [];
    try {
      final raw = await _channel.invokeListMethod<Map>('listBrowsers');
      return [
        for (final m in raw ?? const <Map>[])
          InstalledBrowser(
            package: m['package'] as String,
            label: m['label'] as String? ?? m['package'] as String,
            isDefault: m['isDefault'] == true,
            icon: m['iconPng'] is String
                ? base64Decode(m['iconPng'] as String)
                : null,
          ),
      ];
    } catch (e) {
      if (kDebugMode) debugPrint('[browsers] list failed: $e');
      return const [];
    }
  }

  /// Opens [url] in [package], or the system default when it is empty.
  static Future<bool> openUrl(String url, {String package = ''}) async {
    if (!supported) {
      final uri = Uri.tryParse(url);
      if (uri == null) return false;
      try {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        return false;
      }
    }
    try {
      return await _channel.invokeMethod<bool>('openUrl', {
            'url': url,
            'package': package.isEmpty ? null : package,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Packages that can open [url] itself, the one Android would pick first.
  /// Empty off Android or on failure.
  static Future<List<String>> resolvesUrl(String url) async {
    if (!supported) return const [];
    try {
      final raw = await _channel.invokeListMethod<String>('resolvesUrl', {
        'url': url,
      });
      return raw ?? const [];
    } catch (_) {
      return const [];
    }
  }

  /// "Open with…" for a file cached under the app's previews folder.
  /// False when no app can open it (or off Android).
  static Future<bool> openFile(String path, String mime) async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('openFile', {
            'path': path,
            'mime': mime,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Opens an HTML document in [package]. False when nothing could show it.
  static Future<bool> openHtml(
    String html, {
    String title = '',
    String package = '',
  }) async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('openHtml', {
            'html': html,
            'title': title,
            'package': package.isEmpty ? null : package,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }
}
