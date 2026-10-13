import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/auth_constants.dart';
import '../../../core/constants/illustrations.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/system_chrome.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/dot_matrix_backdrop.dart';
import '../../../core/widgets/illustration.dart';

/// Dot-grid auth page: a small brand bar, an optional centered
/// illustration, one headline with a subtitle, the form, and [footer] pinned
/// to the bottom. Scrolls above the keyboard; the illustration collapses
/// while the keyboard is open or the screen is short.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
    this.footer,
    this.illustration = true,
    this.onBack,
  });

  final String title, subtitle;
  final List<Widget> children;

  /// Pinned under the form (e.g. "New to sparky? Create account").
  final Widget? footer;

  /// Show the peep-with-a-laptop above the headline.
  final bool illustration;

  /// Shows a back button in the brand bar.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // Read above the Scaffold, which strips the inset from its body.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    // Large text needs the room: measure the height in "1x text" units.
    final screenHeight =
        MediaQuery.sizeOf(context).height /
        MediaQuery.textScalerOf(context).scale(1);
    final art =
        !illustration ||
            keyboardOpen ||
            screenHeight < IllustrationSizes.loginHiddenBelow
        ? 0.0
        : screenHeight < IllustrationSizes.loginCompactBelow
        ? IllustrationSizes.loginCompact
        : IllustrationSizes.login;
    final bottomGap = keyboardOpen ? AppSpacing.lg : AppSpacing.xl;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: systemOverlayFor(context),
      child: Scaffold(
        backgroundColor: p.background,
        body: Stack(
          children: [
            const Positioned.fill(child: DotMatrixBackdrop.page()),
            SafeArea(
              child: Column(
                children: [
                  _BrandBar(onBack: onBack),
                  Expanded(
                    // No intrinsics here: the error banner and illustration
                    // animate their size, which intrinsic passes misjudge.
                    child: LayoutBuilder(
                      builder: (context, box) => SingleChildScrollView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: EdgeInsets.fromLTRB(
                          AppSpacing.xl,
                          AppSpacing.sm,
                          AppSpacing.xl,
                          bottomGap,
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: AuthSizes.formMaxWidth,
                              minHeight: math.max(
                                0,
                                box.maxHeight - AppSpacing.sm - bottomGap,
                              ),
                            ),
                            child: AutofillGroup(
                              // Equal room above the form and between it and
                              // the footer; scrolls once it no longer fits.
                              child: Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const SizedBox.shrink(),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _AuthIllustration(height: art),
                                      _Heading(
                                        title: title,
                                        subtitle: subtitle,
                                      ),
                                      const SizedBox(height: AppSpacing.xl),
                                      ...children,
                                    ],
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      top: AppSpacing.lg,
                                    ),
                                    child: footer ?? const SizedBox.shrink(),
                                  ),
                                ],
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
          ],
        ),
      ),
    );
  }
}

/// "sparky•" at the top-left, as in the sidebar; a back button before it
/// on pushed pages.
class _BrandBar extends StatelessWidget {
  const _BrandBar({this.onBack});

  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final back = onBack;
    return SizedBox(
      height: AppSizes.appBarHeight,
      child: Row(
        children: [
          if (back != null)
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.xs),
              child: IconButton(
                tooltip: AuthStrings.back,
                icon: AppIcon(
                  AppIcons.back,
                  size: AppIconSize.lg,
                  color: context.palette.textPrimary,
                ),
                onPressed: () {
                  Haptics.tap();
                  back();
                },
              ),
            )
          else
            const SizedBox(width: AppSpacing.xl),
          const Wordmark(size: AppFontSize.title, compact: true),
        ],
      ),
    );
  }
}

/// The one headline of the page and its subtitle, centered.
class _Heading extends StatelessWidget {
  const _Heading({required this.title, required this.subtitle});

  final String title, subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: context.text.headline.copyWith(fontSize: AuthSizes.headline),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: context.text.body.copyWith(
            color: context.palette.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// The peep-with-a-laptop over the headline. Collapses to nothing
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
      alignment: Alignment.topCenter,
      child: height == 0
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xl),
              child: Center(
                child: Illustration(
                  kind: IllustrationKind.login,
                  height: height,
                ),
              ),
            ),
    );
  }
}

/// "sparky" in Space Grotesk bold, with a red dot. [compact] draws the
/// sidebar's brand: semibold with a round dot after it.
class Wordmark extends StatelessWidget {
  const Wordmark({
    super.key,
    this.size = AppFontSize.displayLarge,
    this.compact = false,
  });

  final double size;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (compact) {
      return Semantics(
        label: AuthStrings.brand,
        excludeSemantics: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AuthStrings.brand,
              style: context.text.title.copyWith(
                fontSize: size,
                fontVariations: const [FontVariation.weight(600)],
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Container(
              width: AppSizes.dot,
              height: AppSizes.dot,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: p.accent,
              ),
            ),
          ],
        ),
      );
    }
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

/// Filled tonal pill field with a leading icon; the error shows inline
/// below. With [showLabel] the label sits above the field (Profile sheets);
/// without it the label is the hint. Password fields get show/hide and a
/// Caps Lock note.
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
    this.showLabel = true,
    this.gap = AppSpacing.lg,
  });

  final String label;
  final String? hint, error;
  final TextEditingController controller;
  final AppIconData icon;
  final bool obscure, enabled, showLabel;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted, onChanged;
  final FocusNode? focusNode;
  final TextCapitalization textCapitalization;
  final int? maxLength;

  /// Space below the field.
  final double gap;

  @override
  State<AuthField> createState() => _AuthFieldState();
}

class _AuthFieldState extends State<AuthField> {
  bool _hidden = true;
  bool _capsLock = false;
  FocusNode? _ownFocus;

  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  @override
  void initState() {
    super.initState();
    if (widget.obscure) {
      HardwareKeyboard.instance.addHandler(_onKey);
      _focus.addListener(_syncCaps);
    }
  }

  @override
  void dispose() {
    if (widget.obscure) {
      HardwareKeyboard.instance.removeHandler(_onKey);
      _focus.removeListener(_syncCaps);
    }
    _ownFocus?.dispose();
    super.dispose();
  }

  bool _onKey(KeyEvent _) {
    _syncCaps();
    return false;
  }

  /// Caps Lock is only known with a hardware keyboard.
  void _syncCaps() {
    final on =
        _focus.hasFocus &&
        HardwareKeyboard.instance.lockModesEnabled.contains(
          KeyboardLockMode.capsLock,
        );
    if (on != _capsLock && mounted) setState(() => _capsLock = on);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final scheme = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final error = widget.error;
    final note = error ?? (_capsLock ? AuthStrings.capsLock : null);
    final noteColor = error != null ? p.error : p.textSecondary;
    OutlineInputBorder border(Color c) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.field),
      borderSide: BorderSide(color: c, width: AppBorder.thin),
    );
    return Padding(
      padding: EdgeInsets.only(bottom: widget.gap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showLabel) ...[
            Text(
              widget.label,
              style: tt.labelLarge!.copyWith(color: p.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
          ],
          TextField(
            controller: widget.controller,
            focusNode: _focus,
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
              hintText: widget.hint ?? (widget.showLabel ? null : widget.label),
              counterText: '',
              contentPadding: widget.showLabel
                  ? null
                  : const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AuthSizes.fieldPadV,
                    ),
              prefixIcon: Padding(
                padding: const EdgeInsets.only(
                  left: AppSpacing.lg + AppSpacing.xxs,
                  right: AppSpacing.md,
                ),
                child: AppIcon(
                  widget.icon,
                  size: AppIconSize.md,
                  color: error != null ? p.error : scheme.onSurfaceVariant,
                ),
              ),
              prefixIconConstraints: const BoxConstraints(),
              suffixIcon: widget.obscure
                  ? Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.xs),
                      child: IconButton(
                        tooltip: _hidden ? AuthStrings.show : AuthStrings.hide,
                        icon: AppIcon(
                          _hidden ? AuthIcons.show : AuthIcons.hide,
                          size: AppIconSize.md,
                          color: scheme.onSurfaceVariant,
                        ),
                        onPressed: () {
                          Haptics.tap();
                          setState(() => _hidden = !_hidden);
                        },
                      ),
                    )
                  : null,
              enabledBorder: border(
                error != null ? p.error : Colors.transparent,
              ),
              focusedBorder: border(error != null ? p.error : p.textPrimary),
            ),
          ),
          AnimatedSize(
            duration: AppDurations.fast,
            alignment: Alignment.topLeft,
            child: note == null
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(
                      top: AppSpacing.sm,
                      left: AppSpacing.lg + AppSpacing.xxs,
                      right: AppSpacing.lg,
                    ),
                    child: Row(
                      children: [
                        AppIcon(
                          error != null ? AppIcons.alert : AuthIcons.capsLock,
                          size: AppIconSize.sm,
                          color: noteColor,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            note,
                            style: tt.bodySmall!.copyWith(color: noteColor),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Filled pill; while [loading] it is disabled and shows a spinner (and
/// [loadingLabel] when given).
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.destructive = false,
    this.loadingLabel,
    this.height = AppSizes.buttonHeight,
  });

  final String label;
  final String? loadingLabel;
  final VoidCallback? onPressed;
  final bool loading, destructive;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final bg = destructive ? p.error : p.textPrimary;
    final fg = destructive ? AppColors.white : p.textInverse;
    final style = Theme.of(context).textTheme.titleMedium!.copyWith(color: fg);
    final spinner = SizedBox.square(
      key: const ValueKey('spinner'),
      dimension: AuthSizes.spinner,
      child: CircularProgressIndicator(strokeWidth: AppBorder.thick, color: fg),
    );
    final pending = loadingLabel;
    return SizedBox(
      height: height,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          disabledBackgroundColor: loading ? bg : p.disabled,
          disabledForegroundColor: loading ? fg : null,
          shape: const StadiumBorder(),
        ),
        onPressed: loading ? null : onPressed,
        child: AnimatedSwitcher(
          duration: AppDurations.fast,
          child: !loading
              ? Text(label, key: const ValueKey('idle'), style: style)
              : pending == null
              ? spinner
              : Row(
                  key: const ValueKey('busy'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    spinner,
                    const SizedBox(width: AppSpacing.md),
                    Flexible(
                      child: Text(
                        pending,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: style,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Inline error banner: a tonal red card with an alert icon.
class FormError extends StatelessWidget {
  const FormError(this.message, {super.key, this.gap = AppSpacing.lg});

  final String? message;

  /// Space below the banner.
  final double gap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final m = message;
    return AnimatedSize(
      duration: AppDurations.fast,
      alignment: Alignment.topCenter,
      child: m == null
          ? const SizedBox(width: double.infinity)
          : Semantics(
              liveRegion: true,
              child: Container(
                width: double.infinity,
                margin: EdgeInsets.only(bottom: gap),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  color: Color.alphaBlend(
                    p.error.withValues(alpha: AuthSizes.errorTint),
                    p.background,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xxs),
                      child: AppIcon(
                        AppIcons.alert,
                        size: AppIconSize.md,
                        color: p.error,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
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
                  style: Theme.of(
                    context,
                  ).textTheme.labelMedium!.copyWith(color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(AuthStrings.strengthHint, style: context.text.bodySmall),
        ],
      ),
    );
  }
}

/// "Question? Action" row at the foot of the page; the action is a real
/// text button in the accent.
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
    final tap = onTap;
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          question,
          style: context.text.body.copyWith(color: p.textSecondary),
        ),
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: p.accent,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          ),
          onPressed: tap == null
              ? null
              : () {
                  Haptics.tap();
                  tap();
                },
          child: Text(
            action,
            style: Theme.of(context).textTheme.titleMedium!.copyWith(
              color: tap == null ? p.disabled : p.accent,
            ),
          ),
        ),
      ],
    );
  }
}

/// "By continuing, you agree to sparky's Terms of Service and Privacy
/// Policy." with both names as links that open in the browser.
class LegalNote extends StatefulWidget {
  const LegalNote({super.key});

  @override
  State<LegalNote> createState() => _LegalNoteState();
}

class _LegalNoteState extends State<LegalNote> {
  late final _terms = TapGestureRecognizer()
    ..onTap = () => _open(AuthLegal.termsUrl());
  late final _privacy = TapGestureRecognizer()
    ..onTap = () => _open(AuthLegal.privacyUrl());

  @override
  void dispose() {
    _terms.dispose();
    _privacy.dispose();
    super.dispose();
  }

  Future<void> _open(Uri uri) async {
    Haptics.tap();
    var ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!ok && mounted) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text(AuthLegal.openFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final base = context.text.bodySmall.copyWith(color: p.textTertiary);
    final link = base.copyWith(
      color: p.textSecondary,
      decoration: TextDecoration.underline,
      decorationColor: p.textTertiary,
    );
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          const TextSpan(text: AuthLegal.lead),
          TextSpan(text: AuthLegal.terms, style: link, recognizer: _terms),
          const TextSpan(text: AuthLegal.and),
          TextSpan(text: AuthLegal.privacy, style: link, recognizer: _privacy),
          const TextSpan(text: AuthLegal.end),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}
