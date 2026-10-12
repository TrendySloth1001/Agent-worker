import 'package:flutter/foundation.dart';

/// Lets a screen pushed over the chat start a fresh chat with a first
/// message (e.g. "Ask Sparky about this repo"). The chat screen listens.
class ChatLaunch {
  ChatLaunch._();
  static final instance = ChatLaunch._();

  /// Set to a message to open a new chat with it; the chat screen clears it.
  final prompt = ValueNotifier<String?>(null);

  void ask(String text) => prompt.value = text;
}
