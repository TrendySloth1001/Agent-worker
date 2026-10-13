import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/app_sizes.dart';
import '../../core/constants/auth_constants.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/system_chrome.dart';
import '../../core/widgets/dot_matrix_backdrop.dart';
import '../chat/chat_screen.dart';
import '../onboarding/onboarding_gate.dart';
import 'auth_controller.dart';
import 'login_screen.dart';
import 'widgets/auth_widgets.dart';

/// Start-up check, then the login screen or the chat. The chat is keyed by
/// user, so switching accounts never shows the previous user's state.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AuthController.instance;
    return ListenableBuilder(
      listenable: auth,
      builder: (context, _) => AnimatedSwitcher(
        duration: AppDurations.normal,
        child: switch (auth.status) {
          AuthStatus.restoring => const _Splash(),
          AuthStatus.signedOut => const LoginScreen(key: ValueKey('login')),
          AuthStatus.signedIn => OnboardingGate(
            key: ValueKey('chat:${auth.user?.id}'),
            user: auth.user,
            child: const ChatScreen(),
          ),
        },
      ),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: systemOverlayFor(context),
      child: Scaffold(
        backgroundColor: p.background,
        body: Stack(
          children: [
            const Positioned.fill(child: DotMatrixBackdrop.page()),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Wordmark(),
                  const SizedBox(height: AppSpacing.xl),
                  const SizedBox(
                    width: AuthSizes.splashProgress,
                    child: LinearProgressIndicator(),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(AuthStrings.restoring, style: context.text.caption),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
