import 'package:flutter/material.dart';

import '../../../core/app_scope.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/chat_cleanup.dart';
import '../../../core/haptics.dart';
import '../../../data/chat_api.dart';
import '../../../data/conversation_events.dart';
import '../../../data/conversations_api.dart';
import 'settings_kit.dart';
import '../../../core/widgets/confirm_sheet.dart';
import '../../../core/widgets/illustration.dart';
import '../../../core/constants/confirm_copy.dart';
import '../../../core/widgets/m3_kit_extras.dart';

/// Destructive Settings row that deletes every chat, after a typed confirm.
class DeleteAllChatsTile extends StatelessWidget {
  const DeleteAllChatsTile({super.key, this.api});

  /// Defaults to the app's server; tests pass their own.
  final ConversationsApi? api;

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return SettingsTile(
      icon: ChatCleanupIcons.delete,
      title: ChatCleanupStrings.deleteAll,
      summary: ChatCleanupStrings.deleteAllHelp,
      iconColor: error,
      titleColor: error,
      onTap: () => showDeleteAllChats(context, api: api),
    );
  }
}

/// Asks (options and a typed DELETE), deletes behind a progress state, then
/// reports how many went. Returns the count, or null when nothing happened.
Future<int?> showDeleteAllChats(
  BuildContext context, {
  ConversationsApi? api,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final server = api ?? ConversationsApi(AppScope.of(context).baseUrl);
  final result = await showM3Sheet<ChatsWiped>(
    context,
    dismissible: false,
    builder: (_) => DeleteAllChatsSheet(api: server),
  );
  if (result == null) return null;
  Haptics.received();
  ConversationEvents.instance.wiped(result);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(ChatCleanupStrings.deletedAll(result.deleted))),
    );
  return result.deleted;
}

/// The confirm sheet: what to include, the typed word, then progress or
/// the error in place. Pops with the outcome once the server answered.
class DeleteAllChatsSheet extends StatefulWidget {
  const DeleteAllChatsSheet({super.key, required this.api});

  final ConversationsApi api;

  @override
  State<DeleteAllChatsSheet> createState() => _DeleteAllChatsSheetState();
}

class _DeleteAllChatsSheetState extends State<DeleteAllChatsSheet> {
  final _word = TextEditingController();
  bool _archived = true;
  bool _keepPinned = false;
  bool _busy = false;
  String? _error;

  bool get _confirmed =>
      _word.text.trim().toUpperCase() == ChatCleanupStrings.confirmWord;

  @override
  void dispose() {
    _word.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    Haptics.tap();
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final n = await widget.api.deleteAll(
        includeArchived: _archived,
        includePinned: !_keepPinned,
      );
      if (!mounted) return;
      Navigator.pop(
        context,
        ChatsWiped(
          deleted: n,
          includeArchived: _archived,
          includePinned: !_keepPinned,
        ),
      );
    } on ApiException {
      if (!mounted) return;
      Haptics.error();
      setState(() {
        _busy = false;
        _error = ChatCleanupStrings.deleteAllFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final pill = sheetPillStyle(context);
    return PopScope(
      canPop: !_busy,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenPadding,
              0,
              AppSpacing.screenPadding,
              AppSpacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SheetIllustration(
                  kind: IllustrationKind.emptyHistory,
                  height: ConfirmSizes.formIllustration,
                ),
                const SheetHeadline(
                  kicker: ConfirmCopy.kickerDelete,
                  title: ChatCleanupStrings.deleteAllTitle,
                ),
                const SizedBox(height: AppSpacing.lg),
                if (_busy) _progress(text) else _form(scheme, text),
                if (!_busy) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: pill,
                          onPressed: () {
                            Haptics.tap();
                            Navigator.pop(context);
                          },
                          child: const Text(ChatCleanupStrings.cancel),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: FilledButton(
                          key: const ValueKey('delete-all-ok'),
                          style: sheetDestructiveStyle(context),
                          onPressed: _confirmed ? _delete : null,
                          child: const Text(ChatCleanupStrings.delete),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _progress(TextTheme text) {
    return Semantics(
      liveRegion: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox.square(
            dimension: ChatCleanupSizes.progress,
            child: CircularProgressIndicator(
              strokeWidth: ChatCleanupSizes.progressStroke,
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Text(ChatCleanupStrings.deleting, style: text.bodyMedium),
        ],
      ),
    );
  }

  Widget _form(ColorScheme scheme, TextTheme text) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          ChatCleanupStrings.deleteAllBody,
          textAlign: TextAlign.center,
          style: text.bodyMedium!.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.sm),
        _check(
          ChatCleanupStrings.includeArchived,
          _archived,
          (v) => _archived = v,
        ),
        _check(
          ChatCleanupStrings.keepPinned,
          _keepPinned,
          (v) => _keepPinned = v,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          ChatCleanupStrings.typeToConfirm,
          style: text.labelLarge!.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _word,
          autocorrect: false,
          enableSuggestions: false,
          textCapitalization: TextCapitalization.characters,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _confirmed ? _delete() : null,
          style: text.bodyLarge,
          decoration: InputDecoration(
            hintText: ChatCleanupStrings.confirmWord,
            filled: false,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: BorderSide(color: scheme.outline),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: BorderSide(
                color: scheme.error,
                width: AppBorder.thick,
              ),
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.md),
          Semantics(
            liveRegion: true,
            child: Text(
              _error!,
              style: text.bodySmall!.copyWith(color: scheme.error),
            ),
          ),
        ],
      ],
    );
  }

  Widget _check(String label, bool value, ValueChanged<bool> set) {
    void toggle() {
      Haptics.tap();
      setState(() => set(!value));
    }

    // A plain row so the box lines up with the text above it.
    return MergeSemantics(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: toggle,
        child: SizedBox(
          height: AppSizes.minTap,
          child: Row(
            children: [
              Checkbox(
                value: value,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (_) => toggle(),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
