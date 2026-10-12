import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/about.dart';
import '../../../core/constants/auth_constants.dart';
import '../../../core/haptics.dart';
import '../../../core/widgets/m3_kit_extras.dart';
import '../../settings/widgets/settings_kit.dart';
import 'sso_buttons.dart';

/// "Trouble signing in?": there is no email password reset, so this says so
/// and points at the ways back in (GitHub/Google by verified email, or
/// support by email).
Future<void> showTroubleSheet(BuildContext context) {
  Haptics.tap();
  final sso = SsoSection.cached?.any ?? false;
  return showM3Sheet<void>(
    context,
    builder: (sheet) => M3ActionSheet(
      title: AuthStrings.trouble,
      subtitle: AuthStrings.troubleSubtitle,
      rows: [
        if (sso)
          SettingsTile(
            icon: AuthIcons.sso,
            title: AuthStrings.troubleSso,
            summary: AuthStrings.troubleSsoDetail,
            onTap: () => Navigator.pop(sheet),
          ),
        SettingsTile(
          icon: AuthIcons.support,
          title: AuthStrings.troubleSupport,
          summary: AboutStrings.feedbackEmail,
          onTap: () => _emailSupport(sheet),
        ),
      ],
    ),
  );
}

Future<void> _emailSupport(BuildContext sheet) async {
  final messenger = ScaffoldMessenger.maybeOf(sheet);
  final subject = Uri.encodeComponent(AuthStrings.troubleSubject);
  final uri = Uri.parse(
    'mailto:${AboutStrings.feedbackEmail}?subject=$subject',
  );
  var opened = false;
  try {
    opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    opened = false;
  }
  if (opened) return;
  Haptics.error();
  await Clipboard.setData(
    const ClipboardData(text: AboutStrings.feedbackEmail),
  );
  messenger?.showSnackBar(
    const SnackBar(content: Text(AboutStrings.noMailApp)),
  );
}
