import 'package:flutter/material.dart';

import 'core/app_scope.dart';
import 'core/constants/app_config.dart';
import 'core/constants/app_strings.dart';
import 'core/theme/app_theme.dart';
import 'data/chat_api.dart';
import 'data/usage_api.dart';
import 'features/chat/chat_screen.dart';
import 'features/settings/settings_controller.dart';
import 'features/settings/usage_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await SettingsController.load();
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
  final _usage = UsageController(UsageApi(AppConfig.apiBaseUrl));

  @override
  void dispose() {
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
          home: const ChatScreen(),
        ),
      ),
    );
  }
}
