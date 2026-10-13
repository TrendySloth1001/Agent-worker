import 'package:flutter/material.dart';

import '../constants/app_sizes.dart';
import '../constants/confirm_copy.dart';
import '../haptics.dart';
import '../theme/app_palette.dart';
import 'illustration.dart';
import 'm3_kit_extras.dart';

/// An illustration for the top of a sheet. Collapses while the keyboard is
/// open so the fields of an input sheet stay visible.
class SheetIllustration extends StatelessWidget {
  const SheetIllustration({
    super.key,
    required this.kind,
    this.height = ConfirmSizes.illustration,
    this.gap = AppSpacing.lg,
  });

  final IllustrationKind kind;
  final double height;

  /// Space under the illustration.
  final double gap;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.viewInsetsOf(context).bottom > 0) {
      return const SizedBox.shrink();
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: Illustration(kind: kind, height: height),
        ),
        SizedBox(height: gap),
      ],
    );
  }
}

/// Mono red kicker, headline and secondary body, centred. The text block of
/// a confirm sheet.
class SheetHeadline extends StatelessWidget {
  const SheetHeadline({
    super.key,
    required this.kicker,
    required this.title,
    this.body,
  });

  final String kicker;
  final String title;
  final String? body;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          kicker,
          textAlign: TextAlign.center,
          style: context.text.caption.copyWith(color: p.accent),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(title, textAlign: TextAlign.center, style: context.text.headline),
        if (body != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            body!,
            textAlign: TextAlign.center,
            style: context.text.body.copyWith(color: p.textSecondary),
          ),
        ],
      ],
    );
  }
}

/// Pill style shared by the sheet buttons.
ButtonStyle sheetPillStyle(BuildContext context) => ButtonStyle(
  minimumSize: const WidgetStatePropertyAll(
    Size.fromHeight(AppSizes.buttonHeight),
  ),
  shape: const WidgetStatePropertyAll(StadiumBorder()),
  textStyle: WidgetStatePropertyAll(
    context.text.body.copyWith(
      fontVariations: const [FontVariation.weight(600)],
    ),
  ),
);

/// Red pill style: white text on the error colour in both themes.
ButtonStyle sheetDestructiveStyle(BuildContext context) {
  final p = context.palette;
  return sheetPillStyle(context).copyWith(
    backgroundColor: WidgetStatePropertyAll(p.error),
    foregroundColor: WidgetStatePropertyAll(
      p.isDark ? p.textPrimary : p.textInverse,
    ),
  );
}

/// The confirm bottom sheet: illustration, mono kicker, headline, a plain
/// line of body copy and two pill buttons. [show] resolves true only when
/// the confirm button was tapped.
class ConfirmSheet extends StatelessWidget {
  const ConfirmSheet({
    super.key,
    required this.illustration,
    required this.kicker,
    required this.title,
    required this.confirmLabel,
    this.body,
    this.cancelLabel = ConfirmCopy.cancel,
    this.destructive = false,
  });

  final IllustrationKind illustration;
  final String kicker;
  final String title;
  final String? body;
  final String confirmLabel;
  final String cancelLabel;
  final bool destructive;

  static Future<bool> show(
    BuildContext context, {
    required IllustrationKind illustration,
    required String kicker,
    required String title,
    required String confirmLabel,
    String? body,
    String cancelLabel = ConfirmCopy.cancel,
    bool destructive = false,
  }) async {
    final ok = await showM3Sheet<bool>(
      context,
      builder: (_) => ConfirmSheet(
        illustration: illustration,
        kicker: kicker,
        title: title,
        body: body,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        destructive: destructive,
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final pill = sheetPillStyle(context);
    return SafeArea(
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
            SheetIllustration(kind: illustration),
            SheetHeadline(
              kicker: kicker,
              title: sentenceCase(title),
              body: body,
            ),
            const SizedBox(height: AppSpacing.xl),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('confirm-cancel'),
                    style: pill,
                    onPressed: () {
                      Haptics.tap();
                      Navigator.pop(context, false);
                    },
                    child: Text(sentenceCase(cancelLabel)),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('confirm-ok'),
                    style: destructive ? sheetDestructiveStyle(context) : pill,
                    onPressed: () {
                      Haptics.tap();
                      Navigator.pop(context, true);
                    },
                    child: Text(sentenceCase(confirmLabel)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A sheet that only says "working on it": illustration, a line and a
/// spinner. Cannot be dismissed; the caller pops it when the work is done.
class ProgressSheet extends StatelessWidget {
  const ProgressSheet({
    super.key,
    required this.illustration,
    required this.label,
  });

  final IllustrationKind illustration;
  final String label;

  /// Shows the sheet on the root navigator. Close it with
  /// `Navigator.of(context, rootNavigator: true).pop()`.
  static Future<void> open(
    BuildContext context, {
    required IllustrationKind illustration,
    required String label,
  }) => showM3Sheet<void>(
    context,
    dismissible: false,
    useRootNavigator: true,
    builder: (_) => ProgressSheet(illustration: illustration, label: label),
  );

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return PopScope(
      canPop: false,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenPadding,
            0,
            AppSpacing.screenPadding,
            AppSpacing.xl,
          ),
          child: Semantics(
            liveRegion: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SheetIllustration(kind: illustration),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox.square(
                      dimension: ConfirmSizes.spinner,
                      child: CircularProgressIndicator(
                        strokeWidth: AppBorder.thick,
                        color: p.accent,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Text(label, style: context.text.body),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
