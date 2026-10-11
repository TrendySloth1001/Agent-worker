import 'package:flutter/material.dart';

import '../../../core/app_scope.dart';
import '../../../core/platform/browsers.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/browser_picker.dart';
import '../../../data/files_api.dart';

/// Opens an http(s) link outside the app, with a small notice on failure.
Future<void> openUrl(
  BuildContext context,
  String url, {
  String? package,
}) async {
  Haptics.tap();
  final browser = package ?? AppScope.of(context).settings.browserPackage;
  // Saved notes use a note: URI and have nothing to open.
  if (url.startsWith('note:')) return;
  var target = url;
  // Document citations point at an uploaded file: fetch a fresh signed URL.
  if (url.startsWith('file:')) {
    try {
      target = (await FilesApi.instance.get(url.substring(5))).url ?? '';
    } catch (_) {
      target = '';
    }
  }
  final uri = Uri.tryParse(target);
  var opened = false;
  if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
    opened = await Browsers.openUrl(uri.toString(), package: browser);
  }
  if (opened || !context.mounted) return;
  Haptics.error();
  final p = context.palette;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: p.surfaceHigh,
      content: Text(AppStrings.cantOpenLink, style: context.text.label),
    ),
  );
}

/// Long-press "Open with...": pick a browser, then open [url] in it.
Future<void> openUrlWith(BuildContext context, String url) async {
  final package = await showBrowserPicker(context);
  if (package == null || !context.mounted) return;
  await openUrl(context, url, package: package);
}

/// VISIT: the saved default browser, else asks which one (and can remember
/// it). Does nothing when the picker is dismissed.
Future<void> visitUrl(BuildContext context, String url) async {
  final package = await pickOrRemembered(context);
  if (package == null || !context.mounted) return;
  await openUrl(context, url, package: package);
}
