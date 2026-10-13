import 'package:flutter/material.dart';

import '../constants/app_sizes.dart';
import '../constants/confirm_copy.dart';
import '../haptics.dart';
import 'confirm_sheet.dart';
import 'illustration.dart';
import 'm3_kit_extras.dart';

/// A small sheet with one input, in the visual language of [ConfirmSheet].
/// Stays above the keyboard; the illustration (when given) folds away while
/// the keyboard is open. Resolves true when the user confirmed, so the
/// caller reads the value from its own controller.
class InputSheet extends StatelessWidget {
  const InputSheet({
    super.key,
    required this.kicker,
    required this.title,
    required this.field,
    required this.confirmLabel,
    required this.submit,
    this.illustration,
    this.body,
    this.cancelLabel = ConfirmCopy.cancel,
  });

  final IllustrationKind? illustration;
  final String kicker;
  final String title;
  final String? body;
  final Widget field;
  final String confirmLabel;
  final String cancelLabel;

  /// Closes the sheet with true (also wired to the keyboard's done key).
  final VoidCallback submit;

  /// [field] is built with a `submit` callback to wire into `onSubmitted`.
  static Future<bool> show(
    BuildContext context, {
    required String kicker,
    required String title,
    required Widget Function(BuildContext sheet, VoidCallback submit) field,
    required String confirmLabel,
    IllustrationKind? illustration,
    String? body,
    String cancelLabel = ConfirmCopy.cancel,
  }) async {
    final ok = await showM3Sheet<bool>(
      context,
      builder: (sheet) => InputSheet(
        illustration: illustration,
        kicker: kicker,
        title: title,
        body: body,
        field: field(sheet, () => Navigator.pop(sheet, true)),
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        submit: () => Navigator.pop(sheet, true),
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final pill = sheetPillStyle(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenPadding,
            0,
            AppSpacing.screenPadding,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (illustration != null)
                SheetIllustration(
                  kind: illustration!,
                  height: ConfirmSizes.formIllustration,
                ),
              SheetHeadline(kicker: kicker, title: title, body: body),
              const SizedBox(height: AppSpacing.lg),
              field,
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: pill,
                      onPressed: () {
                        Haptics.tap();
                        Navigator.pop(context, false);
                      },
                      child: Text(cancelLabel),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('input-ok'),
                      style: pill,
                      onPressed: () {
                        Haptics.tap();
                        submit();
                      },
                      child: Text(confirmLabel),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
