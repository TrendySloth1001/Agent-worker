import 'package:flutter/material.dart';

import '../../../core/app_scope.dart';
import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../data/conversation.dart';
import '../../../data/conversations_api.dart';
import '../../history/history_controller.dart';
import '../../history/widgets/chat_actions.dart';
import '../../history/widgets/conversation_list.dart';
import '../../knowledge/knowledge_screen.dart';
import '../../settings/settings_screen.dart';
import '../chat_controller.dart';

/// Left sidebar: new chat, search, conversations, knowledge and settings.
class AppDrawer extends StatefulWidget {
  const AppDrawer({super.key, required this.chat});

  final ChatController chat;

  @override
  State<AppDrawer> createState() => AppDrawerState();
}

class AppDrawerState extends State<AppDrawer> {
  HistoryController? _history;
  final _search = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_history != null) return;
    _history = HistoryController(ConversationsApi(AppScope.of(context).baseUrl))
      ..load();
  }

  @override
  void dispose() {
    _history?.dispose();
    _search.dispose();
    super.dispose();
  }

  /// Reloads the list; called each time the drawer opens.
  void refresh() => _history?.load();

  void _newChat() {
    Haptics.tap();
    Navigator.of(context).pop();
    widget.chat.newChat();
  }

  Future<void> _openChat(ConversationSummary item) async {
    Haptics.tap();
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    if (item.id == widget.chat.conversationId) return;
    if (await widget.chat.open(item.id)) {
      Haptics.received();
    } else {
      Haptics.error();
      messenger.showSnackBar(
        const SnackBar(content: Text(AppStrings.chatLoadFailed)),
      );
    }
  }

  /// Closes the drawer onto the new chat, or reports the failure.
  void _lineageDone(bool ok, {required String done, required String failed}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (ok) {
      Haptics.received();
      Navigator.of(context).pop();
      if (done.isNotEmpty) {
        messenger.showSnackBar(SnackBar(content: Text(done)));
      }
    } else {
      Haptics.error();
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    }
  }

  Future<bool> _forkChat(ConversationSummary chat) async {
    final ok = await widget.chat.forkConversation(chat.id, chat.messageCount);
    _lineageDone(
      ok,
      done: LineageStrings.forked,
      failed: LineageStrings.forkFailed,
    );
    if (ok) _history?.load();
    return ok;
  }

  void _push(Widget screen) {
    Haptics.tap();
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final history = _history!;
    final width = MediaQuery.sizeOf(context).width;
    final padding = MediaQuery.paddingOf(context);
    return Drawer(
      width: (width * AppSizes.drawerWidthFactor).clamp(
        0.0,
        AppSizes.drawerMaxWidth,
      ),
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(right: BorderSide(color: p.border)),
        ),
        child: Padding(
          padding: EdgeInsets.only(top: padding.top),
          child: Column(
            children: [
              _header(context),
              _searchField(context, history),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenPadding,
                  AppSpacing.md,
                  AppSpacing.screenPadding,
                  0,
                ),
                child: ListenableBuilder(
                  listenable: history,
                  builder: (context, _) => _ListHeader(
                    archived: history.archived,
                    onToggle: () {
                      Haptics.tap();
                      history.showArchived(!history.archived);
                    },
                  ),
                ),
              ),
              Expanded(
                child: ListenableBuilder(
                  listenable: widget.chat,
                  builder: (context, _) => ConversationList(
                    controller: history,
                    currentId: widget.chat.conversationId,
                    onOpen: _openChat,
                    onActions: (chat) => showChatActions(
                      context,
                      chat: chat,
                      controller: history,
                      onRenamed: (id, title) =>
                          widget.chat.onConversationChanged(id, title: title),
                      onDeleted: (id) =>
                          widget.chat.onConversationChanged(id, deleted: true),
                      onFork: _forkChat,
                      onMerge: (id, otherId) =>
                          widget.chat.mergeWith(otherId, baseId: id),
                      onMerged: (ok) {
                        _lineageDone(
                          ok,
                          done: '',
                          failed: LineageStrings.mergeFailed,
                        );
                        if (ok) history.load();
                      },
                    ),
                  ),
                ),
              ),
              Divider(height: AppBorder.thin, color: p.border),
              _NavRow(
                icon: AppIcons.knowledge,
                label: AppStrings.knowledgeBase,
                onTap: () => _push(const KnowledgeScreen()),
              ),
              _NavRow(
                icon: AppIcons.settings,
                label: AppStrings.settings,
                onTap: () => _push(const SettingsScreen()),
              ),
              SizedBox(height: padding.bottom + AppSpacing.sm),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenPadding,
        AppSpacing.lg,
        AppSpacing.screenPadding,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(AppStrings.appName.toUpperCase(), style: context.text.label),
          const SizedBox(height: AppSpacing.md),
          Semantics(
            button: true,
            label: AppStrings.newChat,
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _newChat,
              child: Container(
                height: AppSizes.drawerButtonHeight,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(
                    color: p.borderStrong,
                    width: AppBorder.thin,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppIcon(
                      AppIcons.newChat,
                      size: AppIconSize.sm,
                      color: p.textPrimary,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      AppStrings.newChat,
                      style: context.text.caption.copyWith(
                        color: p.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchField(BuildContext context, HistoryController history) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
      child: TextField(
        controller: _search,
        onChanged: history.search,
        style: context.text.body,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          isDense: true,
          hintText: AppStrings.searchChats,
          prefixIcon: AppIcon(
            AppIcons.search,
            size: AppIconSize.md,
            color: p.textTertiary,
          ),
        ),
      ),
    );
  }
}

/// CONVERSATIONS / ARCHIVED caption with a switch to the other list.
class _ListHeader extends StatelessWidget {
  const _ListHeader({required this.archived, required this.onToggle});

  final bool archived;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    return Row(
      children: [
        Expanded(
          child: Text(
            archived ? AppStrings.archived : AppStrings.conversations,
            style: t.caption,
          ),
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(
                  archived ? AppIcons.back : AppIcons.archive,
                  size: AppIconSize.xs,
                  color: p.textSecondary,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  archived ? AppStrings.conversations : AppStrings.archived,
                  style: t.caption.copyWith(color: p.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({required this.icon, required this.label, required this.onTap});

  final AppIconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: AppSizes.rowHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenPadding,
          ),
          child: Row(
            children: [
              AppIcon(icon, size: AppIconSize.md, color: p.textPrimary),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: Text(label, style: context.text.label)),
              AppIcon(
                AppIcons.chevronRight,
                size: AppIconSize.sm,
                color: p.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
