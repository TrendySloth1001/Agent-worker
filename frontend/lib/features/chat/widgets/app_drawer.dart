import 'package:flutter/material.dart';

import '../../../core/app_scope.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../data/conversation.dart';
import '../../../data/conversations_api.dart';
import '../../../data/docs_api.dart';
import '../../docs/doc_registry.dart';
import '../../docs/doc_screen.dart';
import '../../history/history_controller.dart';
import '../../history/widgets/chat_actions.dart';
import '../../history/widgets/conversation_list.dart';
import '../../history/widgets/docs_sheet.dart';
import '../../history/widgets/history_footer.dart';
import '../../history/widgets/history_header.dart';
import '../../knowledge/knowledge_screen.dart';
import '../../profile/profile_screen.dart';
import '../../settings/settings_screen.dart';
import '../../storage/storage_screen.dart';
import '../chat_controller.dart';
import 'drawer_shell.dart';
import '../share/chat_export.dart';

/// Left sidebar: wordmark with search and new chat, the conversation list
/// (grouped by date, swipe to pin or archive), and a footer with quick
/// entries and the account.
class AppDrawer extends StatefulWidget {
  const AppDrawer({super.key, required this.chat, this.history, this.docsApi});

  final ChatController chat;

  /// Defaults to a controller over the app's server; tests pass their own.
  final HistoryController? history;

  /// Defaults to the real docs API.
  final DocsApi? docsApi;

  @override
  State<AppDrawer> createState() => AppDrawerState();
}

class AppDrawerState extends State<AppDrawer> {
  HistoryController? _history;
  bool _ownsHistory = false;
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  bool _searchOpen = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_history != null) return;
    final given = widget.history;
    if (given != null) {
      _history = given;
    } else {
      _ownsHistory = true;
      _history = HistoryController(
        ConversationsApi(AppScope.of(context).baseUrl),
      );
    }
    _history!.load();
  }

  @override
  void dispose() {
    if (_ownsHistory) _history?.dispose();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// Reloads the list; called each time the drawer opens.
  void refresh() => _history?.load();

  void _closeDrawer() => DrawerShell.maybeOf(context)?.close();

  void _newChat() {
    _closeDrawer();
    widget.chat.newChat();
  }

  Future<void> _openChat(ConversationSummary item) async {
    Haptics.tap();
    final messenger = ScaffoldMessenger.of(context);
    _closeDrawer();
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
      _closeDrawer();
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
    _closeDrawer();
    navigator.push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  Future<void> _pin(ConversationSummary chat) async {
    final ok = await _history!.setPinned(chat.id, !chat.pinned);
    ok ? Haptics.received() : Haptics.error();
  }

  Future<void> _archive(ConversationSummary chat) =>
      archiveChat(context, chat, _history!);

  Future<void> _rename(ConversationSummary chat, String title) async {
    final history = _history!;
    if (title.isEmpty || title == chat.title) {
      history.cancelRename();
      return;
    }
    final updated = await history.rename(chat.id, title);
    if (updated == null) {
      Haptics.error();
      history.cancelRename();
      return;
    }
    Haptics.received();
    widget.chat.onConversationChanged(chat.id, title: updated.title ?? title);
  }

  Future<void> _openDocs() async {
    final navigator = Navigator.of(context);
    final doc = await showDocsSheet(context, api: widget.docsApi);
    if (doc == null || !mounted) return;
    _closeDrawer();
    if (!navigator.mounted) return;
    openDoc(navigator.context, doc.id, seed: doc);
  }

  void _closeSearch() {
    _search.clear();
    _history!.clearSearch();
    setState(() => _searchOpen = false);
  }

  void _toggleArchived(bool value) {
    _search.clear();
    _searchOpen = false;
    _history!.showArchived(value);
    setState(() {});
  }

  /// Chats with a reply, round table or document being written right now.
  Set<String> _runningIds() {
    final chat = widget.chat;
    return {
      if (chat.isSending && chat.conversationId != null) chat.conversationId!,
      ?chat.backgroundChatId,
      for (final d in DocRegistry.instance.running) ?d.doc.conversationId,
    };
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final history = _history!;
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final compact = size.height < AppSizes.drawerCompactHeight;
    return Material(
      color: p.background,
      surfaceTintColor: Colors.transparent,
      child: Padding(
        padding: EdgeInsets.only(top: padding.top, left: padding.left),
        child: Column(
          children: [
            DrawerDragRegion(
              child: ListenableBuilder(
                listenable: history,
                builder: (context, _) => HistoryHeader(
                  searchOpen: _searchOpen,
                  archived: history.archived,
                  search: _search,
                  searchFocus: _searchFocus,
                  onQuery: history.search,
                  onOpenSearch: () => setState(() => _searchOpen = true),
                  onCloseSearch: _closeSearch,
                  onNewChat: _newChat,
                  onBack: () => _toggleArchived(false),
                ),
              ),
            ),
            Expanded(
              child: ListenableBuilder(
                listenable: Listenable.merge([
                  widget.chat,
                  DocRegistry.instance,
                ]),
                builder: (context, _) => ConversationList(
                  controller: history,
                  currentId: widget.chat.conversationId,
                  runningIds: _runningIds(),
                  onOpen: _openChat,
                  onPin: _pin,
                  onArchive: _archive,
                  onRename: _rename,
                  onActions: (chat) => showChatActions(
                    context,
                    chat: chat,
                    controller: history,
                    onDeleted: (id) =>
                        widget.chat.onConversationChanged(id, deleted: true),
                    onFork: _forkChat,
                    onExport: (chat) => exportSavedChat(
                      context,
                      id: chat.id,
                      title: chat.title,
                      openId: widget.chat.conversationId,
                      openMessages: widget.chat.messages,
                      modelName: widget.chat.modelName,
                    ),
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
            DrawerDragRegion(
              child: ListenableBuilder(
                listenable: history,
                builder: (context, _) => HistoryFooter(
                  archivedActive: history.archived,
                  compact: compact,
                  onKnowledge: () => _push(const KnowledgeScreen()),
                  onDocs: _openDocs,
                  onStorage: () => _push(const StorageScreen()),
                  onArchived: () => _toggleArchived(!history.archived),
                  onProfile: () => _push(const ProfileScreen()),
                  onSettings: () => _push(const SettingsScreen()),
                ),
              ),
            ),
            SizedBox(height: padding.bottom),
          ],
        ),
      ),
    );
  }
}
