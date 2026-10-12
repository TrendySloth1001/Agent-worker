import 'package:flutter/foundation.dart';

/// A "delete all chats" that went through, and what it left alone.
class ChatsWiped {
  const ChatsWiped({
    required this.deleted,
    required this.includeArchived,
    required this.includePinned,
  });

  final int deleted;
  final bool includeArchived;
  final bool includePinned;
}

/// Tells the sidebar (and the open chat) that chats were deleted elsewhere,
/// e.g. from Settings, so it reloads and leaves a chat that is gone.
class ConversationEvents extends ChangeNotifier {
  ConversationEvents._();

  static final instance = ConversationEvents._();

  /// The latest wipe; listeners read it when notified.
  ChatsWiped? lastWipe;

  void wiped(ChatsWiped event) {
    lastWipe = event;
    notifyListeners();
  }
}
