import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/sso_constants.dart';
import '../../../core/haptics.dart';
import '../../../core/platform/google_auth.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/brand_mark.dart';
import '../../../data/chat_api.dart';
import '../../../data/sso_api.dart';
import '../auth_controller.dart';
import 'auth_widgets.dart';
import 'github_device_sheet.dart';
import 'github_web_sheet.dart';

/// "OR" and the CONTINUE WITH GITHUB / GOOGLE buttons under the email form.
/// Shows only the providers the server has set up (GET /auth/providers), so
/// adding the Google client id on the server needs no app rebuild.
class SsoSection extends StatefulWidget {
  const SsoSection({super.key, this.enabled = true});

  /// False while the email form is submitting.
  final bool enabled;

  @override
  State<SsoSection> createState() => _SsoSectionState();
}

class _SsoSectionState extends State<SsoSection> {
  SsoProviders? _providers;
  bool _github = false, _google = false;
  String? _error;

  bool get _busy => _github || _google;

  @override
  void initState() {
    super.initState();
    SsoApi.instance.providers().then(
      (p) {
        if (mounted) setState(() => _providers = p);
      },
      // Offline or an older server: no buttons, the email form still works.
      onError: (_) {},
    );
  }

  Future<void> _continueWithGithub() async {
    setState(() {
      _github = true;
      _error = null;
    });
    try {
      // One tap (OAuth web flow); the device code stays as the fallback.
      if (_providers?.githubWeb ?? false) {
        final w = await showGithubWebSheet(
          context,
          title: SsoStrings.sheetTitle,
          mode: GithubWeb.signin,
        );
        if (w != GithubWebSheetResult.useCode || !mounted) return;
      }
      if (!mounted) return;
      final r = await showGithubDeviceSheet(
        context,
        title: SsoStrings.sheetTitle,
        start: () => SsoApi.instance.startGithub(AuthController.device),
        poll: SsoApi.instance.pollGithub,
      );
      final session = r?.session;
      if (session != null) {
        await AuthController.instance.signInWithSession(session);
      }
    } finally {
      if (mounted) setState(() => _github = false);
    }
  }

  Future<void> _continueWithGoogle() async {
    final clientId = _providers?.googleWebClientId;
    if (clientId == null) return;
    Haptics.tap();
    setState(() {
      _google = true;
      _error = null;
    });
    try {
      final token = await GoogleAuth.idToken(clientId);
      if (token == null) return;
      await AuthController.instance.signInWithGoogle(token);
      Haptics.received();
    } on ApiException catch (e) {
      Haptics.error();
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _google = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _providers;
    final enabled = widget.enabled && !_busy;
    return AnimatedSize(
      duration: AppDurations.fast,
      alignment: Alignment.topCenter,
      child: p == null || !p.any
          ? const SizedBox(width: double.infinity)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const OrDivider(),
                FormError(_error),
                if (p.github)
                  SsoButton(
                    label: SsoStrings.github,
                    mark: BrandMark.github(
                      size: SsoSizes.mark,
                      color: context.palette.textPrimary,
                    ),
                    loading: _github,
                    onPressed: enabled ? _continueWithGithub : null,
                  ),
                if (p.github && p.google) const SizedBox(height: AppSpacing.md),
                if (p.google)
                  SsoButton(
                    label: SsoStrings.google,
                    mark: const BrandMark.google(size: SsoSizes.mark),
                    loading: _google,
                    onPressed: enabled ? _continueWithGoogle : null,
                  ),
              ],
            ),
    );
  }
}

/// Thin rule with "OR" in the middle.
class OrDivider extends StatelessWidget {
  const OrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final line = Expanded(
      child: Divider(color: context.palette.border, height: AppBorder.thin),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Row(
        children: [
          line,
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: SsoSizes.dividerGap,
            ),
            child: Text(SsoStrings.or, style: context.text.caption),
          ),
          line,
        ],
      ),
    );
  }
}

/// Full-width outlined pill with a brand mark; a spinner while [loading].
class SsoButton extends StatelessWidget {
  const SsoButton({
    super.key,
    required this.label,
    required this.mark,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final Widget mark;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final active = onPressed != null || loading;
    return SizedBox(
      height: AppSizes.buttonHeight,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          shape: const StadiumBorder(),
          foregroundColor: p.textPrimary,
          side: BorderSide(
            color: active ? p.borderStrong : p.border,
            width: AppBorder.thin,
          ),
        ),
        onPressed: loading || onPressed == null
            ? null
            : () {
                Haptics.tap();
                onPressed!();
              },
        child: loading
            ? SizedBox.square(
                dimension: AppIconSize.md,
                child: CircularProgressIndicator(
                  strokeWidth: AppBorder.thick,
                  color: p.textPrimary,
                ),
              )
            : Opacity(
                opacity: active ? 1 : SsoSizes.disabledAlpha,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    mark,
                    const SizedBox(width: AppSpacing.md),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(
                          context,
                        ).textTheme.titleSmall!.copyWith(color: p.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
