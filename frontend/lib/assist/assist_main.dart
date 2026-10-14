import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_scope.dart';
import '../core/errors/error_reporter.dart';
import '../core/constants/app_config.dart';
import '../core/constants/app_strings.dart';
import '../core/notify/notification_center.dart';
import '../core/theme/app_theme.dart';
import '../data/chat_api.dart';
import '../data/conversations_api.dart';
import '../data/usage_api.dart';
import '../features/auth/auth_controller.dart';
import '../features/chat/voice/voice_controller.dart';
import '../features/chat/voice/voice_setup.dart';
import '../features/settings/settings_controller.dart';
import '../features/settings/usage_controller.dart';
import 'assist_bridge.dart';
import 'assist_controller.dart';
import 'assist_overlay.dart';
import 'share_payload.dart';
import '../core/widgets/tap_outside_unfocus.dart';

/// Entry point of the assistant overlay's engine (AssistEngine.kt starts it
/// ahead of time, so the overlay is ready when the power button is held).
/// Its own isolate: it shares only storage with the app.
@pragma('vm:entry-point')
Future<void> assistMain() async {
  // The overlay is its own isolate and engine: it needs the same error hooks.
  ErrorReporter.runGuarded(WidgetsFlutterBinding.ensureInitialized);
  await ErrorReporter.install(assist: true);
  final settings = await SettingsController.load();
  // Reminders from action cards follow the app's notification choices.
  NotificationCenter.instance.attach(settings.notify);
  unawaited(AuthController.instance.restore());
  runApp(AssistApp(bridge: ChannelAssistBridge(), settings: settings));
}

class AssistApp extends StatefulWidget {
  const AssistApp({super.key, required this.bridge, required this.settings});

  final AssistBridge bridge;
  final SettingsController settings;

  @override
  State<AssistApp> createState() => _AssistAppState();
}

class _AssistAppState extends State<AssistApp> {
  final _api = ChatApi();
  late final _usage = UsageController(UsageApi(AppConfig.apiBaseUrl));
  late SettingsController _settings = widget.settings;
  late final AssistController _controller = AssistController(
    bridge: widget.bridge,
    api: _api,
    conversations: ConversationsApi(AppConfig.apiBaseUrl),
    settings: _settings,
  );
  late final VoiceController _voice = createVoiceController(
    _settings,
    context: () => voiceTurns(_controller.messages),
  );
  StreamSubscription<AssistShow>? _shows;
  StreamSubscription<SharedPayload>? _shared;

  @override
  void initState() {
    super.initState();
    _shows = widget.bridge.shows.listen(_onShow);
    _shared = widget.bridge.shared.listen(_controller.receiveShared);
    widget.bridge.ready().then((first) {
      if (first != null && mounted) _onShow(first);
    });
  }

  /// A new opening: fresh state now, then catch up with what the app changed
  /// (settings, sign-in) while this engine waited.
  void _onShow(AssistShow show) {
    _controller.reset(show);
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.bridge.shown());
    WidgetsBinding.instance.scheduleFrame();
    unawaited(_catchUp());
  }

  Future<void> _catchUp() async {
    await AuthController.instance.syncFromStorage();
    try {
      await (await SharedPreferences.getInstance()).reload();
    } catch (_) {}
    final next = await SettingsController.load();
    if (!mounted) return;
    setState(() => _settings = next);
    _controller.settings = next;
    NotificationCenter.instance.attach(next.notify);
  }

  @override
  void dispose() {
    _shows?.cancel();
    _shared?.cancel();
    _controller.dispose();
    _voice.dispose();
    _usage.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      settings: _settings,
      usage: _usage,
      api: _api,
      baseUrl: AppConfig.apiBaseUrl,
      child: ListenableBuilder(
        listenable: _settings,
        builder: (context, _) => MaterialApp(
          title: AppStrings.appName,
          debugShowCheckedModeBanner: false,
          color: Colors.transparent,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: _settings.themeMode,
          builder: (context, child) {
            final media = MediaQuery.of(context);
            return MediaQuery(
              data: media.copyWith(
                textScaler: TextScaler.linear(
                  media.textScaler.scale(1) * _settings.textScaleFactor,
                ),
              ),
              child: TapOutsideUnfocus(child: child!),
            );
          },
          home: AssistOverlay(controller: _controller, voice: _voice),
        ),
      ),
    );
  }
}
