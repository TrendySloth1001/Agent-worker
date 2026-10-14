import 'package:flutter/cupertino.dart'
    show
        CupertinoDatePicker,
        CupertinoDatePickerMode,
        CupertinoTextThemeData,
        CupertinoTheme,
        CupertinoThemeData;
import 'package:flutter/material.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/constants/notify_copy.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/input_sheet.dart';
import '../../../core/notify/notification_center.dart';
import '../../../core/notify/notify_policy.dart';
import '../../../core/notify/notify_prefs.dart';
import 'settings_kit.dart';

/// Whether Android lets sparky show notifications, with an "Allow" button
/// (system dialog, or the app's system settings when that can no longer
/// appear). Rechecks when the user comes back from the system settings.
class NotifyPermissionTile extends StatefulWidget {
  const NotifyPermissionTile({super.key, this.center});

  final NotificationCenter? center;

  @override
  State<NotifyPermissionTile> createState() => _NotifyPermissionTileState();
}

class _NotifyPermissionTileState extends State<NotifyPermissionTile>
    with WidgetsBindingObserver {
  NotificationCenter get _center =>
      widget.center ?? NotificationCenter.instance;
  NotifyPermission? _state;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final s = await _center.permission();
    if (mounted) setState(() => _state = s);
  }

  Future<void> _allow() async {
    Haptics.tap();
    final s = await _center.allow();
    if (mounted) setState(() => _state = s);
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final granted = state == NotifyPermission.granted;
    return SettingsTile(
      icon: granted ? AppIcons.ok : AppIcons.alert,
      title: NotifyCopy.permissionLabel,
      summary: switch (state) {
        NotifyPermission.granted => NotifyCopy.permissionGranted,
        NotifyPermission.denied => NotifyCopy.permissionDenied,
        _ => NotifyCopy.permissionUnavailable,
      },
      trailing: state == NotifyPermission.denied
          ? FilledButton.tonal(
              onPressed: _allow,
              child: const Text(NotifyCopy.allow),
            )
          : null,
    );
  }
}

/// Quiet hours: a switch, and when on, the From and Until times.
class QuietHoursTiles extends StatelessWidget {
  const QuietHoursTiles({super.key, required this.prefs});

  final NotifyPrefs prefs;

  Future<void> _pick(
    BuildContext context,
    String title,
    int minute,
    ValueChanged<int> set,
  ) async {
    var picked = minute;
    final p = context.palette;
    final ok = await InputSheet.show(
      context,
      kicker: NotifyCopy.quietKicker,
      title: title,
      confirmLabel: NotifyCopy.quietSet,
      field: (sheet, submit) => SizedBox(
        height: NotifySizes.timeWheel,
        child: CupertinoTheme(
          data: CupertinoThemeData(
            brightness: p.isDark ? Brightness.dark : Brightness.light,
            textTheme: CupertinoTextThemeData(
              dateTimePickerTextStyle: sheet.text.body.copyWith(
                color: p.textPrimary,
              ),
            ),
          ),
          child: CupertinoDatePicker(
            mode: CupertinoDatePickerMode.time,
            use24hFormat: MediaQuery.alwaysUse24HourFormatOf(sheet),
            initialDateTime: DateTime(2000, 1, 1, minute ~/ 60, minute % 60),
            onDateTimeChanged: (d) => picked = d.hour * 60 + d.minute,
          ),
        ),
      ),
    );
    if (ok) set(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SettingsSwitchTile(
          icon: NotifyIcons.quiet,
          title: NotifyCopy.quietLabel,
          summary: NotifyCopy.quietHelp,
          value: prefs.quietOn,
          onChanged: prefs.setQuietOn,
        ),
        if (prefs.quietOn) ...[
          SettingsTile(
            icon: NotifyIcons.quietFrom,
            title: NotifyCopy.quietFrom,
            trailing: Text(QuietHours.format(prefs.quietStart)),
            onTap: () => _pick(
              context,
              NotifyCopy.quietFrom,
              prefs.quietStart,
              prefs.setQuietStart,
            ),
          ),
          SettingsTile(
            icon: NotifyIcons.quietTo,
            title: NotifyCopy.quietTo,
            trailing: Text(QuietHours.format(prefs.quietEnd)),
            onTap: () => _pick(
              context,
              NotifyCopy.quietTo,
              prefs.quietEnd,
              prefs.setQuietEnd,
            ),
          ),
        ],
      ],
    );
  }
}

/// Sends a sample notification.
class NotifyTestTile extends StatelessWidget {
  const NotifyTestTile({super.key, this.center});

  final NotificationCenter? center;

  @override
  Widget build(BuildContext context) {
    return SettingsTile(
      icon: NotifyIcons.test,
      title: NotifyCopy.testLabel,
      summary: NotifyCopy.testHelp,
      onTap: () async {
        final ok = await (center ?? NotificationCenter.instance).sendTest();
        if (!context.mounted) return;
        ok ? Haptics.received() : Haptics.error();
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(ok ? NotifyCopy.testSent : NotifyCopy.testBlocked),
            ),
          );
      },
    );
  }
}
