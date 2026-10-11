import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/auth_constants.dart';
import '../../../core/constants/illustrations.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/system_chrome.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/dot_grid_background.dart';
import '../../../core/widgets/illustration.dart';

/// Dot-grid page with the big "sparky" wordmark over a centered form.
/// Scrolls above the keyboard.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title, subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // Read above the Scaffold, which strips the inset from its body.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final illustration =
        keyboardOpen || screenHeight < IllustrationSizes.loginHiddenBelow
        ? 0.0
        : screenHeight < IllustrationSizes.loginCompactBelow
        ? IllustrationSizes.loginCompact
        : IllustrationSizes.login;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: systemOverlayFor(context),
      child: Scaffold(
        backgroundColor: p.background,
        body: Stack(
          children: [
            const Positioned.fill(child: DotGridBackground()),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, box) => SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                    vertical: AppSpacing.xl,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: box.maxHeight - AppSpacing.xl * 2,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: AuthSizes.formMaxWidth,
                        ),
                        child: AutofillGroup(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _AuthIllustration(height: illustration),
                              const Wordmark(),
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                AuthStrings.tagline,
                                style: context.text.bodySmall,
                              ),
                              const SizedBox(height: AppSpacing.xxl),
                              Text(title, style: context.text.label),
                              const SizedBox(height: AppSpacing.xs),
                              Text(subtitle, style: context.text.bodySmall),
                              const SizedBox(height: AppSpacing.xl),
                              ...children,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The peep-with-a-laptop over the wordmark. Collapses to nothing
/// ([height] 0) while the keyboard is open or on very short screens.
class _AuthIllustration extends StatelessWidget {
  const _AuthIllustration({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : IllustrationDurations.resize,
      curve: Curves.easeOutCubic,
      alignment: Alignment.topLeft,
      child: height == 0
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Illustration(
                  kind: IllustrationKind.login,
                  height: height,
                ),
              ),
            ),
    );
  }
}

/// "sparky" in Space Grotesk bold, with a red dot.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.size = AppFontSize.displayLarge});

  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Text.rich(
      TextSpan(
        children: [
          const TextSpan(text: AuthStrings.brand),
          TextSpan(
            text: '.',
            style: TextStyle(color: p.accent),
          ),
        ],
      ),
      style: context.text.display.copyWith(fontSize: size),
      semanticsLabel: AuthStrings.brand,
    );
  }
}

/// Mono label over a 1px bordered field; the error shows inline below.
class AuthField extends StatefulWidget {
  const AuthField({
    super.key,
    required this.label,
    required this.controller,
    required this.icon,
    this.hint,
    this.error,
    this.obscure = false,
    this.keyboardType,
    this.autofillHints,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
    this.onChanged,
    this.focusNode,
    this.enabled = true,
    this.textCapitalization = TextCapitalization.none,
    this.maxLength,
  });

  final String label;
  final String? hint, error;
  final TextEditingController controller;
  final AppIconData icon;
  final bool obscure, enabled;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted, onChanged;
  final FocusNode? focusNode;
  final TextCapitalization textCapitalization;
  final int? maxLength;

  @override
  State<AuthField> createState() => _AuthFieldState();
}

class _AuthFieldState extends State<AuthField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final error = widget.error;
    OutlineInputBorder border(Color c) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.field),
      borderSide: BorderSide(color: c, width: AppBorder.thin),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.label, style: context.text.caption),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: widget.controller,
            focusNode: widget.focusNode,
            enabled: widget.enabled,
            obscureText: widget.obscure && _hidden,
            enableSuggestions: !widget.obscure,
            autocorrect: false,
            keyboardType: widget.keyboardType,
            autofillHints: widget.autofillHints,
            textInputAction: widget.textInputAction,
            textCapitalization: widget.textCapitalization,
            onSubmitted: widget.onSubmitted,
            onChanged: widget.onChanged,
            maxLength: widget.maxLength,
            style: context.text.body,
            decoration: InputDecoration(
              hintText: widget.hint,
              counterText: '',
              filled: true,
              fillColor: p.surface,
              prefixIcon: Padding(
                padding: const EdgeInsets.only(
                  left: AppSpacing.lg,
                  right: AppSpacing.sm,
                ),
                child: AppIcon(
                  widget.icon,
                  size: AppIconSize.md,
                  color: p.textSecondary,
                ),
              ),
              prefixIconConstraints: const BoxConstraints(),
              suffixIcon: widget.obscure
                  ? IconButton(
                      tooltip: _hidden ? AuthStrings.show : AuthStrings.hide,
                      icon: AppIcon(
                        _hidden ? AuthIcons.show : AuthIcons.hide,
                        size: AppIconSize.md,
                        color: p.textSecondary,
                      ),
                      onPressed: () {
                        Haptics.tap();
                        setState(() => _hidden = !_hidden);
                      },
                    )
                  : null,
              border: border(error != null ? p.error : p.border),
              enabledBorder: border(error != null ? p.error : p.border),
              focusedBorder: border(error != null ? p.error : p.textPrimary),
              disabledBorder: border(p.border),
            ),
          ),
          AnimatedSize(
            duration: AppDurations.fast,
            alignment: Alignment.topLeft,
            child: error == null
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(
                      top: AppSpacing.xs,
                      left: AppSpacing.lg,
                    ),
                    child: Text(
                      error,
                      style: context.text.caption.copyWith(color: p.error),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Filled pill; shows a spinner while [loading].
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.destructive = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading, destructive;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final bg = destructive ? p.error : p.textPrimary;
    final fg = destructive ? AppColors.white : p.textInverse;
    return SizedBox(
      height: AppSizes.buttonHeight,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          disabledBackgroundColor: loading ? bg : p.disabled,
          shape: const StadiumBorder(),
        ),
        onPressed: loading ? null : onPressed,
        child: loading
            ? SizedBox(
                width: AppIconSize.md,
                height: AppIconSize.md,
                child: CircularProgressIndicator(
                  strokeWidth: AppBorder.thick,
                  color: fg,
                ),
              )
            : Text(label, style: context.text.button.copyWith(color: fg)),
      ),
    );
  }
}

/// Inline error banner above the button.
class FormError extends StatelessWidget {
  const FormError(this.message, {super.key});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final m = message;
    return AnimatedSize(
      duration: AppDurations.fast,
      child: m == null
          ? const SizedBox(width: double.infinity)
          : Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: AppSpacing.lg),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: p.error, width: AppBorder.thin),
              ),
              child: Row(
                children: [
                  AppIcon(AppIcons.alert, size: AppIconSize.sm, color: p.error),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      m,
                      style: context.text.bodySmall.copyWith(
                        color: p.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

/// Password strength 0..3 from length and character variety.
int passwordStrength(String s) {
  if (s.length < AuthSizes.minPassword) return s.isEmpty ? 0 : 1;
  var kinds = 0;
  for (final re in [
    RegExp('[a-z]'),
    RegExp('[A-Z]'),
    RegExp('[0-9]'),
    RegExp(r'[^A-Za-z0-9]'),
  ]) {
    if (re.hasMatch(s)) kinds++;
  }
  if (s.length >= 14 || (s.length >= 10 && kinds >= 3)) return 3;
  return kinds >= 2 ? 2 : 1;
}

/// Three-segment strength bar with a label and hint.
class StrengthHint extends StatelessWidget {
  const StrengthHint({super.key, required this.password});

  final String password;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final level = passwordStrength(password);
    final label = switch (level) {
      0 => '',
      1 => AuthStrings.strengthWeak,
      2 => AuthStrings.strengthOk,
      _ => AuthStrings.strengthStrong,
    };
    final color = level <= 1 ? p.error : p.textPrimary;
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        bottom: AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var i = 0; i < AuthSizes.strengthSegments; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: AnimatedContainer(
                    duration: AppDurations.fast,
                    height: AuthSizes.strengthBar,
                    decoration: BoxDecoration(
                      color: i < level ? color : p.border,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                  ),
                ),
              ],
              const SizedBox(width: AppSpacing.md),
              SizedBox(
                width: AppSpacing.xxxl + AppSpacing.lg,
                child: Text(
                  label,
                  textAlign: TextAlign.end,
                  style: context.text.caption.copyWith(color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(AuthStrings.strengthHint, style: context.text.caption),
        ],
      ),
    );
  }
}

/// "Question? ACTION" row under the form.
class SwitchPrompt extends StatelessWidget {
  const SwitchPrompt({
    super.key,
    required this.question,
    required this.action,
    required this.onTap,
  });

  final String question, action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(question, style: context.text.bodySmall),
          TextButton(
            onPressed: onTap == null
                ? null
                : () {
                    Haptics.tap();
                    onTap!();
                  },
            child: Text(
              action,
              style: context.text.button.copyWith(color: p.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
