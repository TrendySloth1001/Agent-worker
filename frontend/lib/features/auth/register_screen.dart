import 'package:flutter/material.dart';

import '../../core/constants/app_sizes.dart';
import '../../core/constants/auth_constants.dart';
import '../../core/haptics.dart';
import '../../data/chat_api.dart';
import 'auth_controller.dart';
import 'login_screen.dart';
import 'widgets/auth_widgets.dart';
import 'widgets/sso_buttons.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, this.initialEmail = ''});

  final String initialEmail;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _name = TextEditingController();
  late final _email = TextEditingController(text: widget.initialEmail);
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmFocus = FocusNode();
  String? _nameError, _emailError, _passwordError, _confirmError, _formError;
  bool _loading = false;

  @override
  void dispose() {
    for (final c in [_name, _email, _password, _confirm]) {
      c.dispose();
    }
    for (final f in [_emailFocus, _passwordFocus, _confirmFocus]) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final pass = _password.text;
    setState(() {
      _nameError = _name.text.trim().isEmpty ? AuthStrings.errName : null;
      _emailError = validEmail(_email.text) ? null : AuthStrings.errEmail;
      _passwordError = pass.length < AuthSizes.minPassword
          ? AuthStrings.errPasswordShort
          : null;
      _confirmError = _confirm.text != pass ? AuthStrings.errConfirm : null;
      _formError = null;
    });
    if ([
      _nameError,
      _emailError,
      _passwordError,
      _confirmError,
    ].any((e) => e != null)) {
      Haptics.error();
      return;
    }
    FocusScope.of(context).unfocus();
    Haptics.tap();
    setState(() => _loading = true);
    try {
      await AuthController.instance.register(_name.text, _email.text, pass);
      Haptics.received();
      // The gate now shows the chat; drop this page from the stack.
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on ApiException catch (e) {
      Haptics.error();
      if (mounted) setState(() => _formError = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _clear(String? error, VoidCallback reset) {
    if (error != null) setState(reset);
  }

  @override
  Widget build(BuildContext context) {
    void back() => Navigator.of(context).maybePop();
    return AuthScaffold(
      title: AuthStrings.registerTitle,
      subtitle: AuthStrings.registerSubtitle,
      illustration: false,
      onBack: Navigator.of(context).canPop() ? back : null,
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SwitchPrompt(
            question: AuthStrings.haveAccount,
            action: AuthStrings.toLogin,
            onTap: _loading ? null : back,
          ),
          const SizedBox(height: AppSpacing.xs),
          const LegalNote(),
        ],
      ),
      children: [
        FormError(_formError),
        AuthField(
          label: AuthStrings.name,
          showLabel: false,
          controller: _name,
          icon: AuthIcons.name,
          error: _nameError,
          enabled: !_loading,
          gap: AppSpacing.md,
          maxLength: AuthSizes.nameMax,
          keyboardType: TextInputType.name,
          textCapitalization: TextCapitalization.words,
          autofillHints: const [AutofillHints.name],
          onSubmitted: (_) => _emailFocus.requestFocus(),
          onChanged: (_) => _clear(_nameError, () => _nameError = null),
        ),
        AuthField(
          label: AuthStrings.email,
          showLabel: false,
          controller: _email,
          focusNode: _emailFocus,
          icon: AuthIcons.email,
          error: _emailError,
          enabled: !_loading,
          gap: AppSpacing.md,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          onSubmitted: (_) => _passwordFocus.requestFocus(),
          onChanged: (_) => _clear(_emailError, () => _emailError = null),
        ),
        AuthField(
          label: AuthStrings.newPasswordHint,
          showLabel: false,
          controller: _password,
          focusNode: _passwordFocus,
          icon: AuthIcons.password,
          error: _passwordError,
          enabled: !_loading,
          gap: AppSpacing.md,
          obscure: true,
          keyboardType: TextInputType.visiblePassword,
          autofillHints: const [AutofillHints.newPassword],
          onSubmitted: (_) => _confirmFocus.requestFocus(),
          onChanged: (_) {
            setState(() => _passwordError = null);
          },
        ),
        if (_password.text.isNotEmpty) StrengthHint(password: _password.text),
        AuthField(
          label: AuthStrings.confirm,
          showLabel: false,
          controller: _confirm,
          focusNode: _confirmFocus,
          icon: AuthIcons.password,
          error: _confirmError,
          enabled: !_loading,
          gap: AppSpacing.xl,
          obscure: true,
          keyboardType: TextInputType.visiblePassword,
          autofillHints: const [AutofillHints.newPassword],
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          onChanged: (_) => _clear(_confirmError, () => _confirmError = null),
        ),
        PillButton(
          label: AuthStrings.createAccount,
          loadingLabel: AuthStrings.creatingAccount,
          height: AuthSizes.buttonHeight,
          loading: _loading,
          onPressed: _submit,
        ),
        SsoSection(enabled: !_loading),
      ],
    );
  }
}
