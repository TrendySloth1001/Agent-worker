import 'package:flutter/material.dart';

import '../../../core/constants/profile_copy.dart';
import '../../../core/widgets/confirm_sheet.dart';
import '../../../core/widgets/illustration.dart';

/// "Taking a break?": the sign-out confirmation, a [ConfirmSheet] with a
/// reassuring line and Stay / Sign out.
abstract final class LogOutSheet {
  /// Opens the sheet; true when the user chose to sign out.
  static Future<bool> show(BuildContext context) => ConfirmSheet.show(
    context,
    illustration: IllustrationKind.homeCoffee,
    kicker: ProfileCopy.logOutKicker,
    title: ProfileCopy.logOutTitle,
    body: ProfileCopy.logOutBody,
    confirmLabel: ProfileCopy.logOut,
    cancelLabel: ProfileCopy.logOutStay,
    destructive: true,
  );
}
