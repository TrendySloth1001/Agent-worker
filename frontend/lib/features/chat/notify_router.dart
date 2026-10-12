import 'package:flutter/material.dart';

import '../../core/notify/notify_target.dart';
import '../../data/files_api.dart';
import '../docs/doc_screen.dart';
import '../knowledge/knowledge_screen.dart';
import '../memory/memory_screen.dart';
import '../settings/settings_pages.dart';
import '../settings/settings_screen.dart';
import '../settings/widgets/settings_kit.dart';
import 'preview/file_preview.dart';

/// The one handler for a tapped notification (or in-app link): every
/// [NotifyTarget] ends up here. [openChat] opens a saved chat in the chat
/// screen, which owns that state.
Future<void> routeNotifyTarget(
  BuildContext context,
  NotifyTarget target, {
  required Future<void> Function(String id) openChat,
}) async {
  final nav = Navigator.of(context);
  switch (target) {
    case ChatTarget(:final id) || TableTarget(:final id):
      // Back to the chat screen, then the chat.
      nav.popUntil((r) => r.isFirst);
      await openChat(id);
    case DocTarget(:final id):
      await openDoc(context, id);
    case FileTarget(:final id):
      try {
        final file = await FilesApi.instance.get(id);
        if (!context.mounted) return;
        await openFilePreview(context, [file], file);
      } catch (_) {
        // Deleted or offline: nothing to show.
      }
    case MemoryTarget():
      await MemoryScreen.open(context);
    case SettingsTarget(:final page):
      if (page == 'knowledge') {
        await nav.push(settingsRoute(const KnowledgeScreen()));
        return;
      }
      final category = SettingsCategory.values
          .where((c) => c.name == page)
          .firstOrNull;
      if (category == null) {
        await nav.push(settingsRoute(const SettingsScreen()));
      } else {
        await openSettingsCategory(context, category);
      }
  }
}
