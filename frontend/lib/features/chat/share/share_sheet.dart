import 'package:flutter/material.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/widgets/m3_kit_extras.dart';
import '../../settings/widgets/settings_kit.dart';

/// Small M3 action sheet: a title and one grouped row per option. Returns
/// the picked value, or null when dismissed. Callers give the opening haptic.
Future<T?> showShareSheet<T>(
  BuildContext context, {
  required String title,
  required List<(T, AppIconData, String)> options,
}) {
  return showM3Sheet<T>(
    context,
    builder: (sheet) => M3ActionSheet(
      title: sentenceCase(title),
      rows: [
        for (final (value, icon, label) in options)
          SettingsTile(
            icon: icon,
            title: sentenceCase(label),
            onTap: () => Navigator.pop(sheet, value),
          ),
      ],
    ),
  );
}
