import 'package:flutter/material.dart';

import '../constants/mascot.dart';
import 'illustration.dart';

/// Which scene a screen shows. Kept as a small state vocabulary so callers
/// say what is happening; each maps to one of the Open Peeps illustrations.
enum MascotState {
  idle(MascotStrings.idle),
  thinking(MascotStrings.thinking),
  writing(MascotStrings.writing),
  searching(MascotStrings.searching),
  celebrating(MascotStrings.celebrating),
  sleeping(MascotStrings.sleeping),
  error(MascotStrings.error),
  offline(MascotStrings.offline),

  /// Code and branches, for the GitHub screens.
  github(MascotStrings.github);

  const MascotState(this.label);

  final String label;

  /// The illustration drawn for this state.
  IllustrationKind get illustration => switch (this) {
    github => IllustrationKind.github,
    searching => IllustrationKind.emptyKnowledge,
    sleeping || error || offline => IllustrationKind.emptyHistory,
    _ => IllustrationKind.hello,
  };

  /// The state for a live Round Table phase.
  static MascotState forTablePhase(String? phase) => switch (phase) {
    'researching' => searching,
    'drafting' || 'synthesizing' => writing,
    _ => thinking,
  };

  /// The state for a doc pipeline status or progress phase.
  static MascotState forDocPhase(String phase) => switch (phase) {
    'research' || 'researching' => searching,
    'sections' || 'writing' => writing,
    'finish' || 'finishing' => celebrating,
    _ => thinking,
  };
}

/// A line-art illustration for empty, error and connect screens. Compact
/// slots (progress bars, the round table meter) show nothing, which keeps
/// those surfaces clean.
class Mascot extends StatelessWidget {
  const Mascot({
    super.key,
    required this.state,
    this.size = MascotSizes.medium,
    this.semanticLabel,
  });

  final MascotState state;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    if (size < MascotSizes.medium) return const SizedBox.shrink();
    return Illustration(
      kind: state.illustration,
      height: size,
      semanticLabel: semanticLabel,
    );
  }
}
