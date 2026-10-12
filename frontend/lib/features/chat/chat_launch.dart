import 'package:flutter/foundation.dart';

/// Lets a screen pushed over the chat start a fresh chat with a first
/// message (e.g. "Ask Sparky about this repo"). The chat screen listens.
class ChatLaunch {
  ChatLaunch._();
  static final instance = ChatLaunch._();

  /// Set to a message to open a new chat with it; the chat screen clears it.
  final prompt = ValueNotifier<String?>(null);

  /// Connected-app items the new chat is about (`{provider, id, title}`),
  /// read live by the server on every turn of that chat.
  List<Map<String, String>> apps = const [];

  void ask(String text, {List<Map<String, String>> apps = const []}) {
    this.apps = apps;
    prompt.value = text;
  }
}
