import 'package:flutter/material.dart';

import '../about/whats_new_sheet.dart';
import '../update/update_trigger.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/constants/app_strings.dart';
import '../../core/constants/share_export.dart';
import '../../core/haptics.dart';
import '../../core/notify/notification_center.dart';
import '../../core/app_scope.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/system_chrome.dart';
import '../../core/widgets/m3_kit_extras.dart';
import '../../core/widgets/dot_grid_background.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/size_reporter.dart';
import '../../data/chat_message.dart';
import '../../data/conversations_api.dart';
import '../../data/files_api.dart';
import '../docs/doc_background_chip.dart';
import '../docs/doc_screen.dart';
import 'notify_router.dart';
import 'chat_actions.dart';
import 'chat_controller.dart';
import 'chat_launch.dart';
import 'share/chat_export.dart';
import 'voice/voice_controller.dart';
import 'voice/voice_setup.dart';
import 'widgets/app_drawer.dart';
import 'widgets/chat_switch_transition.dart';
import 'widgets/drawer_shell.dart';
import 'widgets/background_table_chip.dart';
import 'widgets/chat_input.dart';
import 'widgets/empty_state.dart';
import 'widgets/context_card.dart';
import 'widgets/lineage_banner.dart';
import 'widgets/message_bubble.dart';
import 'widgets/message_editor.dart';
import '../../core/constants/app_icons.dart';
import '../../core/widgets/app_icon.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final ChatController _controller;
  late final VoiceController _voice;
  final _scroll = ScrollController();
  final _shell = GlobalKey<DrawerShellState>();
  final _drawer = GlobalKey<AppDrawerState>();
  final _showScrollButton = ValueNotifier(false);
  late final UpdateSheetTrigger _updateSheet;

  /// The user message being edited in place, if any.
  ChatMessage? _editing;

  /// Height of the floating input, which grows with its chips and text.
  final _inputHeight = ValueNotifier(AppSizes.bottomInset);

  @override
  void initState() {
    super.initState();
    final scope = context.getInheritedWidgetOfExactType<AppScope>()!;
    _controller = ChatController(
      scope.api,
      scope.settings,
      ConversationsApi(scope.baseUrl),
    );
    _controller.loadModels();
    _voice = createVoiceController(scope.settings);
    // After an app update: a one-time "What's new" sheet (never on first install).
    // A new-version sheet waits for a calm moment, and never shares a launch
    // with "What's new".
    _updateSheet = UpdateSheetTrigger(
      context: () => context,
      isBusy: () => _controller.isSending,
    )..start();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (await WhatsNew.maybeShow(context)) _updateSheet.whatsNewShown();
    });
    _controller.addListener(() {
      if (_controller.messages.isEmpty) _showScrollButton.value = false;
      // Another chat opened, or the message was replaced.
      if (_editing != null && !_controller.messages.contains(_editing)) {
        _editing = null;
      }
    });
    _scroll.addListener(() {
      _showScrollButton.value = _scroll.offset > AppSizes.scrollButtonThreshold;
    });
    _controller.docStarted.addListener(_onDocStarted);
    NotificationCenter.instance.target.addListener(_onNotificationOpened);
    ChatLaunch.instance.prompt.addListener(_onLaunch);
    ChatLaunch.instance.fresh.addListener(_onFresh);
    NotificationCenter.instance.currentChat = () => _controller.conversationId;
    // A cold start from a notification has its target waiting already.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _onNotificationOpened(),
    );
  }

  /// A screen asked for a new chat with a first message.
  void _onLaunch() {
    final text = ChatLaunch.instance.prompt.value;
    if (text == null || !mounted) return;
    ChatLaunch.instance.prompt.value = null;
    _controller.newChat();
    _controller.appRefs = ChatLaunch.instance.apps;
    ChatLaunch.instance.apps = const [];
    _controller.send(text);
  }

  /// A screen asked for an empty new chat (the tour from Settings).
  void _onFresh() {
    if (mounted) _controller.newChat();
  }

  /// A tapped notification (or in-app link) opens what it points at.
  void _onNotificationOpened() {
    final t = NotificationCenter.instance.target.value;
    if (t == null || !mounted) return;
    NotificationCenter.instance.target.value = null;
    routeNotifyTarget(context, t, openChat: _openChat);
  }

  /// A document started from the composer opens in the reader.
  void _onDocStarted() {
    final id = _controller.docStarted.value;
    if (id == null || !mounted) return;
    _controller.docStarted.value = null;
    openDoc(context, id);
  }

  Future<void> _notifyMe(ChatMessage message) async {
    final ok = await _controller.notifyWhenDone(message);
    if (!mounted) return;
    _toast(ok ? TableWaitStrings.notifyOn : TableWaitStrings.notifyBlocked);
  }

  @override
  void dispose() {
    _updateSheet.dispose();
    NotificationCenter.instance.target.removeListener(_onNotificationOpened);
    ChatLaunch.instance.prompt.removeListener(_onLaunch);
    ChatLaunch.instance.fresh.removeListener(_onFresh);
    NotificationCenter.instance.currentChat = () => null;
    _controller.dispose();
    _voice.dispose();
    _scroll.dispose();
    _showScrollButton.dispose();
    _inputHeight.dispose();
    super.dispose();
  }

  void _toast(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  /// Opens another saved chat (a fork parent or a merge source).
  Future<void> _openChat(String id) async {
    if (id == _controller.conversationId) return;
    if (await _controller.open(id)) {
      Haptics.received();
    } else {
      Haptics.error();
      _toast(AppStrings.chatLoadFailed);
    }
  }

  Future<void> _fork(ChatMessage at, {bool before = false}) async {
    final ok = await _controller.fork(at, before: before);
    if (ok == null || !mounted) return;
    if (ok) {
      Haptics.received();
      _toast(LineageStrings.forked);
    } else {
      Haptics.error();
      _toast(LineageStrings.forkFailed);
    }
  }

  /// Sends an edited message; the reply after it is asked for again.
  void _submitEdit(ChatMessage at, String text, List<FileInfo> files) {
    if (!_controller.edit(at, text, attachments: files)) {
      Haptics.error();
      _toast(EditStrings.busy);
      return;
    }
    setState(() => _editing = null);
  }

  void _export() {
    Haptics.tap();
    exportChat(
      context,
      title: _controller.title,
      load: () async => List.of(_controller.messages),
      modelName: _controller.modelName,
    );
  }

  void _scrollToBottom() {
    Haptics.tap();
    _scroll.animateTo(
      0,
      duration: AppDurations.slow,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final scope = AppScope.of(context);

    return AnnotatedRegion(
      value: systemOverlayFor(context),
      child: DrawerShell(
        key: _shell,
        drawer: AppDrawer(key: _drawer, chat: _controller),
        onOpening: () => _drawer.currentState?.refresh(),
        child: Scaffold(
          body: ListenableBuilder(
            listenable: Listenable.merge([_controller, _inputHeight]),
            builder: (context, _) {
              final isEmpty = _controller.messages.isEmpty;
              final bottomClear =
                  padding.bottom + AppSpacing.md + _inputHeight.value;
              return Stack(
                children: [
                  const Positioned.fill(child: DotGridBackground()),
                  Positioned.fill(
                    child: ChatSwitchTransition(
                      token: _controller.conversationId,
                      child: isEmpty
                          ? EmptyState(onSuggestion: _controller.send)
                          : _messageList(padding, bottomClear),
                    ),
                  ),
                  _Fade(
                    top: true,
                    height: padding.top + AppSizes.topInset + AppSpacing.lg,
                  ),
                  _Fade(top: false, height: bottomClear + AppSpacing.md),
                  Positioned(
                    top: padding.top + AppSpacing.sm,
                    left: AppSpacing.screenPadding,
                    right: AppSpacing.screenPadding,
                    child: _TopBar(
                      controller: _controller,
                      onMenu: () => _shell.currentState?.open(),
                      onExport: _controller.isSending ? null : _export,
                    ),
                  ),
                  Positioned(
                    left: AppSpacing.screenPadding,
                    right: AppSpacing.screenPadding,
                    bottom: padding.bottom + AppSpacing.md,
                    child: Column(
                      children: [
                        if (!isEmpty) _scrollButton(),
                        SizeReporter(
                          onSize: (size) => _inputHeight.value = size.height,
                          child: ChatInput(
                            onSend: (text, files) =>
                                _controller.send(text, attachments: files),
                            onStop: _controller.stop,
                            isStreaming: _controller.isSending,
                            webMode: _controller.webMode,
                            knowledge: _controller.knowledge,
                            onToggleWebSearch: _controller.cycleWebMode,
                            suggestion: _controller.suggestion,
                            onAcceptSuggestion: _controller.acceptSuggestion,
                            onDismissSuggestion: _controller.dismissSuggestion,
                            onToggleKnowledge: _controller.toggleKnowledge,
                            roundTable: _controller.roundTable,
                            onToggleRoundTable: _controller.toggleRoundTable,
                            draft: _controller.draft,
                            autocomplete: scope.settings.autocompleteOn,
                            voice: _voice,
                            sendVoiceAutomatically:
                                scope.settings.voiceAutoSend,
                            conversationId: _controller.conversationId,
                            doc: _controller.doc,
                            onToggleDoc: _controller.toggleDoc,
                            docLength: _controller.docLength,
                            onDocLength: _controller.setDocLength,
                            onSendAsDoc: (text, files) =>
                                _controller.sendDoc(text, attachments: files),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _messageList(EdgeInsets padding, double bottomClear) {
    final messages = _controller.messages;
    final count = messages.length;

    // Reversed so the newest message sits at the bottom and stays in view.
    return ChatActions(
      send: _controller.send,
      latest: messages.isEmpty ? null : messages.last,
      sending: _controller.isSending,
      edit: (text) => _controller.draft.value = text,
      answerFor: (reply) {
        final i = messages.indexOf(reply);
        if (i < 0 || i + 1 >= count) return null;
        final next = messages[i + 1];
        return next.role == Role.user ? next.content : null;
      },
      child: ListView.separated(
        controller: _scroll,
        reverse: true,
        padding: EdgeInsets.fromLTRB(
          AppSpacing.screenPadding,
          padding.top + AppSizes.topInset,
          AppSpacing.screenPadding,
          bottomClear + AppSpacing.xl,
        ),
        itemCount: count + (_controller.isFork ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xl),
        itemBuilder: (context, index) {
          if (index == count) {
            return LineageBanner(
              parentId: _controller.parentId,
              parentTitle: _controller.parentTitle,
              onOpen: _openChat,
            );
          }
          final message = messages[count - 1 - index];
          if (message.role == Role.context) {
            return ContextCard(
              key: ObjectKey(message),
              message: message,
              onOpen: _openChat,
            );
          }
          final canFork =
              !_controller.isSending &&
              !message.isStreaming &&
              !message.isError &&
              message.error == null;
          final isLast = index == 0 && !_controller.isSending;
          if (identical(message, _editing)) {
            return MessageEditor(
              key: ObjectKey(message),
              message: message,
              onCancel: () => setState(() => _editing = null),
              onSend: (text, files) => _submitEdit(message, text, files),
            );
          }
          return MessageBubble(
            key: ObjectKey(message),
            message: message,
            label: _controller.modelName(message.modelId),
            question: _questionFor(messages, count - 1 - index),
            conversationId: _controller.conversationId,
            onFork: canFork
                ? () => _fork(message, before: message.role == Role.user)
                : null,
            onRegenerate: isLast && message.role == Role.assistant
                ? _controller.regenerate
                : null,
            onAnswerFast: message.isStreaming ? _controller.answerFast : null,
            onNotify: message.isStreaming ? () => _notifyMe(message) : null,
            onEdit: message.role == Role.user && !_controller.isSending
                ? () => setState(() => _editing = message)
                : null,
            onTurnIntoDoc: canFork && message.role == Role.assistant
                ? () => _controller.turnIntoDoc(message)
                : null,
          );
        },
      ),
    );
  }

  /// The user message right before the assistant reply at [i], if any.
  String? _questionFor(List<ChatMessage> messages, int i) {
    if (messages[i].role != Role.assistant || i == 0) return null;
    final prev = messages[i - 1];
    return prev.role == Role.user ? prev.content : null;
  }

  Widget _scrollButton() {
    return ValueListenableBuilder(
      valueListenable: _showScrollButton,
      builder: (context, visible, _) => AnimatedScale(
        scale: visible ? 1 : 0,
        duration: AppDurations.normal,
        curve: Curves.easeOutBack,
        child: Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: GestureDetector(
            onTap: _scrollToBottom,
            child: Glass(
              child: SizedBox.square(
                dimension: AppSizes.sendButton,
                child: AppIcon(
                  AppIcons.scrollDown,
                  size: AppIconSize.md,
                  color: context.palette.textPrimary,
                  semanticLabel: AppStrings.scrollToBottom,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.controller,
    required this.onMenu,
    this.onExport,
  });

  final ChatController controller;
  final VoidCallback onMenu;

  /// EXPORT for the open chat; null while a reply streams.
  final VoidCallback? onExport;

  @override
  Widget build(BuildContext context) => M3Themed(child: Builder(builder: _bar));

  Widget _bar(BuildContext context) {
    final canReset = controller.messages.isNotEmpty;
    final title = controller.title;
    return SizedBox(
      height: AppSizes.topBar,
      child: Row(
        children: [
          _BarIcon(
            icon: AppIcons.menu,
            label: AppStrings.openMenu,
            onTap: () {
              Haptics.tap();
              onMenu();
            },
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                Haptics.tap();
                onMenu();
              },
              child: AnimatedSwitcher(
                duration: AppDurations.normal,
                // A round table still running in another chat.
                child: controller.backgroundTable != null
                    ? BackgroundTableChip(
                        key: const ValueKey(BackgroundTableChip),
                        onTap: controller.openBackground,
                      )
                    // A document still being written elsewhere.
                    : DocBackgroundChip(
                        key: const ValueKey(DocBackgroundChip),
                        fallback: Text(
                          title ?? '',
                          key: ValueKey(title),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
              ),
            ),
          ),
          if (canReset)
            _BarIcon(
              icon: ShareIcons.export,
              label: ShareStrings.export,
              onTap: onExport,
            ),
          const SizedBox(width: AppSpacing.sm),
          _NewChatPill(
            onTap: canReset
                ? () {
                    Haptics.tap();
                    controller.newChat();
                  }
                : null,
          ),
        ],
      ),
    );
  }
}

/// New chat: a filled round icon button, the same size as the bar's other
/// icon buttons (disabled on an empty chat).
class _NewChatPill extends StatelessWidget {
  const _NewChatPill({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton.filled(
      onPressed: onTap,
      tooltip: AppStrings.newChat,
      style: IconButton.styleFrom(
        fixedSize: const Size.square(AppSizes.topBar),
        minimumSize: const Size.square(AppSizes.topBar),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: const AppIcon(
        AppIcons.newChat,
        size: AppIconSize.md,
        semanticLabel: AppStrings.newChat,
      ),
    );
  }
}

class _BarIcon extends StatelessWidget {
  const _BarIcon({required this.icon, required this.label, this.onTap});

  final AppIconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // A tonal circle the same height as the new-chat pill, so every control
    // in the bar has the same size and weight.
    return IconButton(
      onPressed: onTap,
      tooltip: label,
      style: IconButton.styleFrom(
        fixedSize: const Size.square(AppSizes.topBar),
        minimumSize: const Size.square(AppSizes.topBar),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: scheme.surfaceContainerHigh,
        disabledBackgroundColor: scheme.surfaceContainerHigh,
      ),
      icon: AppIcon(
        icon,
        size: AppIconSize.md,
        semanticLabel: label,
        color: onTap == null ? scheme.outline : scheme.onSurface,
      ),
    );
  }
}

/// Black-to-clear gradient so content fades out under the floating bars.
class _Fade extends StatelessWidget {
  const _Fade({required this.top, required this.height});

  final bool top;
  final double height;

  @override
  Widget build(BuildContext context) {
    final bg = context.palette.background;
    return Positioned(
      top: top ? 0 : null,
      bottom: top ? null : 0,
      left: 0,
      right: 0,
      height: height,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: top ? Alignment.topCenter : Alignment.bottomCenter,
              end: top ? Alignment.bottomCenter : Alignment.topCenter,
              colors: [bg, bg.withValues(alpha: 0)],
              stops: const [0.75, 1],
            ),
          ),
        ),
      ),
    );
  }
}
