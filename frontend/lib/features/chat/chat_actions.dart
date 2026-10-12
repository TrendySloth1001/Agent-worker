import 'package:flutter/widgets.dart';

import '../../data/chat_message.dart';

/// Lets rich blocks inside a reply talk back to the chat (e.g. the ```ask
/// card sends the user's pick as their next message).
class ChatActions extends InheritedWidget {
  const ChatActions({
    super.key,
    required this.send,
    required this.latest,
    required this.sending,
    required this.answerFor,
    this.edit,
    required super.child,
  });

  final void Function(String text) send;

  /// The last message in the chat.
  final ChatMessage? latest;
  final bool sending;

  /// The user message that follows [reply], if any.
  final String? Function(ChatMessage reply) answerFor;

  /// Puts text in the composer to edit before sending.
  final void Function(String text)? edit;

  static ChatActions? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ChatActions>();

  @override
  bool updateShouldNotify(ChatActions old) =>
      latest != old.latest || sending != old.sending;
}

/// The reply a markdown tree belongs to.
class ReplyScope extends InheritedWidget {
  const ReplyScope({super.key, required this.message, required super.child});

  final ChatMessage message;

  static ChatMessage? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ReplyScope>()?.message;

  @override
  bool updateShouldNotify(ReplyScope old) => message != old.message;
}
