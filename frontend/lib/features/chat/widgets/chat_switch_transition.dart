import 'package:flutter/material.dart';

import '../../../core/constants/history.dart';

/// Material 3 fade-through for the chat area: when [token] changes (another
/// chat, or a new one) the content fades and scales in instead of swapping
/// instantly. A single child is kept, so its scroll state is never doubled.
/// Reduced motion shows the change at once.
class ChatSwitchTransition extends StatefulWidget {
  const ChatSwitchTransition({
    super.key,
    required this.token,
    required this.child,
  });

  final Object? token;
  final Widget child;

  @override
  State<ChatSwitchTransition> createState() => _ChatSwitchTransitionState();
}

class _ChatSwitchTransitionState extends State<ChatSwitchTransition>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: DrawerMotion.chatSwitch,
    value: 1,
  );

  @override
  void didUpdateWidget(ChatSwitchTransition old) {
    super.didUpdateWidget(old);
    if (old.token == widget.token) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = 1;
    } else {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fade = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.2, 1, curve: Curves.easeOut),
    );
    final scale = Tween(
      begin: DrawerMotion.chatSwitchScale,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));
    return FadeTransition(
      opacity: fade,
      child: ScaleTransition(scale: scale, child: widget.child),
    );
  }
}
