import '../../core/constants/wait_copy.dart';
import '../../data/chat_message.dart';
import 'stream_retry.dart';

/// What the wait line says.
enum WaitKind { picking, model, switching, phase, think }

/// One step of the wait line. [text] is empty for [WaitKind.think]: the
/// playful word generator fills that in. [logoIds] are model ids whose logos
/// lead the line.
class WaitStep {
  const WaitStep(this.kind, {this.text = '', this.logoIds = const []});

  final WaitKind kind;
  final String text;
  final List<String> logoIds;

  @override
  bool operator ==(Object other) =>
      other is WaitStep &&
      other.kind == kind &&
      other.text == text &&
      other.logoIds.join('|') == logoIds.join('|');

  @override
  int get hashCode => Object.hash(kind, text, logoIds.join('|'));
}

/// Turns the latest server event of a waiting reply into the line to show.
/// [nameOf] gives a model's friendly name, or null when it is not known:
/// raw ids are never shown.
WaitStep resolveWait(
  ChatMessage m, {
  required String? Function(String id) nameOf,
}) {
  final status = m.status;
  if (status == StreamRetry.reconnectingPhase) {
    return const WaitStep(WaitKind.phase, text: WaitStrings.reconnecting);
  }
  switch (m.waitLast) {
    case 'status':
      final text = WaitStrings.phases[status];
      if (text != null) return WaitStep(WaitKind.phase, text: text);
    case 'model':
      final id = m.modelId;
      final name = id == null ? null : nameOf(id);
      if (id != null && name != null) {
        return m.waitAttempt > 1
            ? WaitStep(
                WaitKind.switching,
                text: WaitStrings.switchingTo(name),
                logoIds: [id],
              )
            : WaitStep(
                WaitKind.model,
                text: WaitStrings.goingWith(name),
                logoIds: [id],
              );
      }
      if (m.waitAttempt > 1) {
        return const WaitStep(WaitKind.switching, text: WaitStrings.switching);
      }
    case 'start':
      if (m.waitCandidates.isNotEmpty) {
        // One logo per distinct friendly name, best candidates first.
        final seen = <String>{};
        final logos = <String>[];
        for (final id in m.waitCandidates) {
          final key = nameOf(id) ?? id;
          if (seen.add(key)) logos.add(id);
          if (logos.length == WaitStrings.maxLogos) break;
        }
        return WaitStep(
          WaitKind.picking,
          text: WaitStrings.picking,
          logoIds: logos,
        );
      }
  }
  return const WaitStep(WaitKind.think);
}
