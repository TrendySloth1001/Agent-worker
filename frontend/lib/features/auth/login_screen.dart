import 'package:flutter/material.dart';

import '../../core/constants/app_sizes.dart';
import '../../core/constants/auth_constants.dart';
import '../../core/haptics.dart';
import '../../core/theme/app_palette.dart';
import '../../data/chat_api.dart';
import 'auth_controller.dart';
import 'register_screen.dart';
import 'widgets/auth_widgets.dart';
import 'widgets/sso_buttons.dart';
import 'widgets/trouble_sheet.dart';

final _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

bool validEmail(String s) => _emailRe.hasMatch(s.trim());

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  String? _emailError, _passwordError, _formError;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    // Shown once, e.g. "Your session expired".
    _formError = AuthController.instance.notice;
    AuthController.instance.notice = null;
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    setState(() {
      _emailError = validEmail(email) ? null : AuthStrings.errEmail;
      _passwordError = _password.text.isEmpty ? AuthStrings.errPassword : null;
      _formError = null;
    });
    if (_emailError != null || _passwordError != null) {
      Haptics.error();
      return;
    }
    FocusScope.of(context).unfocus();
    Haptics.tap();
    setState(() => _loading = true);
    try {
      await AuthController.instance.login(email, _password.text);
      Haptics.received();
    } on ApiException catch (e) {
      Haptics.error();
      if (mounted) setState(() => _formError = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toRegister() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RegisterScreen(initialEmail: _email.text.trim()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AuthScaffold(
      title: AuthStrings.loginTitle,
      subtitle: AuthStrings.loginSubtitle,
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SwitchPrompt(
            question: AuthStrings.noAccount,
            action: AuthStrings.toRegister,
            onTap: _loading ? null : _toRegister,
          ),
          const SizedBox(height: AppSpacing.xs),
          const LegalNote(),
        ],
      ),
      children: [
        FormError(_formError),
        AuthField(
          label: AuthStrings.email,
          showLabel: false,
          controller: _email,
          icon: AuthIcons.email,
          error: _emailError,
          enabled: !_loading,
          gap: AppSpacing.md,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email, AutofillHints.username],
          onSubmitted: (_) => _passwordFocus.requestFocus(),
          onChanged: (_) {
            if (_emailError != null) setState(() => _emailError = null);
          },
        ),
        AuthField(
          label: AuthStrings.password,
          showLabel: false,
          controller: _password,
          focusNode: _passwordFocus,
          icon: AuthIcons.password,
          error: _passwordError,
          enabled: !_loading,
          gap: 0,
          obscure: true,
          keyboardType: TextInputType.visiblePassword,
          autofillHints: const [AutofillHints.password],
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          onChanged: (_) {
            if (_passwordError != null) setState(() => _passwordError = null);
          },
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            style: TextButton.styleFrom(foregroundColor: p.textSecondary),
            onPressed: _loading ? null : () => showTroubleSheet(context),
            child: Text(
              AuthStrings.trouble,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium!.copyWith(color: p.textSecondary),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        PillButton(
          label: AuthStrings.signIn,
          loadingLabel: AuthStrings.signingIn,
          height: AuthSizes.buttonHeight,
          loading: _loading,
          onPressed: _submit,
        ),
        SsoSection(enabled: !_loading),
      ],
    );
  }
}
