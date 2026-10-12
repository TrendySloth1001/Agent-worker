import 'package:flutter/material.dart';

import 'core/app_messenger.dart';
import 'core/app_scope.dart';
import 'core/constants/app_config.dart';
import 'core/constants/app_strings.dart';
import 'core/notify/notification_center.dart';
import 'core/platform/google_auth.dart';
import 'core/theme/app_theme.dart';
import 'data/chat_api.dart';
import 'data/files_api.dart';
import 'data/usage_api.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/auth_gate.dart';
import 'features/auth/sso/github_web_auth.dart';
import 'features/connectors/connector_auth.dart';
import 'features/settings/settings_controller.dart';
import 'features/settings/usage_controller.dart';
import 'features/connections/connections_controller.dart';
import 'features/docs/doc_registry.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await SettingsController.load();
  NotificationCenter.instance.attach(settings.notify);
  await NotificationCenter.instance.init();
  // Per-user caches go on sign-out; the chat itself is rebuilt per user.
  AuthController.instance.addSignOutHook(FilesApi.instance.clearCache);
  AuthController.instance.addSignOutHook(ConnectionsController.instance.reset);
  AuthController.instance.addSignOutHook(GoogleAuth.signOut);
  AuthController.instance.addSignOutHook(DocRegistry.instance.clear);
  // Not awaited: the gate shows a splash until the session is restored.
  AuthController.instance.restore();
  // GitHub one-tap sign-in: deep links back from GitHub, incl. a cold start.
  GithubWebAuth.instance.init();
  ConnectorAuth.instance.init();
  runApp(App(settings: settings));
}

class App extends StatefulWidget {
  const App({super.key, required this.settings});

  final SettingsController settings;

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  final _api = ChatApi();
  final _navigator = GlobalKey<NavigatorState>();
  final _auth = AuthController.instance;
  var _usage = UsageController(UsageApi(AppConfig.apiBaseUrl));
  AuthStatus? _status;
  String? _userId;

  @override
  void initState() {
    super.initState();
    _auth.addListener(_onAuth);
  }

  /// Sign-in, sign-out or a different account: close pushed screens (they
  /// may show the old user's data) and start usage fresh.
  void _onAuth() {
    final status = _auth.status;
    final userId = _auth.user?.id;
    if (status == _status && userId == _userId) return;
    final switched =
        _status != null && (status != _status || userId != _userId);
    _status = status;
    _userId = userId;
    if (!switched) return;
    _navigator.currentState?.popUntil((r) => r.isFirst);
    final old = _usage;
    setState(() => _usage = UsageController(UsageApi(AppConfig.apiBaseUrl)));
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    // Personalization is local; start it from the account name.
    final name = _auth.user?.name.trim() ?? '';
    if (status == AuthStatus.signedIn &&
        name.isNotEmpty &&
        widget.settings.name.trim().isEmpty) {
      widget.settings.setName(name);
    }
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuth);
    _usage.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      settings: widget.settings,
      usage: _usage,
      api: _api,
      baseUrl: AppConfig.apiBaseUrl,
      child: ListenableBuilder(
        listenable: widget.settings,
        builder: (context, _) => MaterialApp(
          title: AppStrings.appName,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: widget.settings.themeMode,
          navigatorKey: _navigator,
          scaffoldMessengerKey: AppMessenger.key,
          builder: (context, child) {
            final media = MediaQuery.of(context);
            return MediaQuery(
              data: media.copyWith(
                textScaler: TextScaler.linear(
                  media.textScaler.scale(1) * widget.settings.textScaleFactor,
                ),
              ),
              child: child!,
            );
          },
          home: const AuthGate(),
        ),
      ),
    );
  }
}
