import 'dart:math' as math;

import '../constants/mascot.dart';
import 'mascot.dart';

/// One lit dot: [a] is its brightness, [accent] picks the red.
typedef MascotDot = ({double a, bool accent});

/// The lit dots of one mascot frame. Pure data so it can be tested.
class MascotFrame {
  MascotFrame() : _dots = List.filled(MascotGrid.cols * MascotGrid.rows, null);

  final List<MascotDot?> _dots;

  /// Cells inside the head (unlit dots are drawn brighter there).
  static bool inHead(int c, int r) => c >= 2 && c <= 14 && r >= 4 && r <= 11;

  MascotDot? at(int c, int r) => _dots[r * MascotGrid.cols + c];

  int get litCount => _dots.where((d) => d != null).length;

  void set(int c, int r, {double a = 1, bool accent = false}) {
    if (c < 0 || c >= MascotGrid.cols || r < 0 || r >= MascotGrid.rows) return;
    _dots[r * MascotGrid.cols + c] = (a: a, accent: accent);
  }

  /// Draws the 'X' cells of [rows] with the top-left corner at ([c], [r]).
  void pattern(
    int c,
    int r,
    List<String> rows, {
    double a = 1,
    bool accent = false,
  }) {
    for (var y = 0; y < rows.length; y++) {
      for (var x = 0; x < rows[y].length; x++) {
        if (rows[y][x] == 'X') set(c + x, r + y, a: a, accent: accent);
      }
    }
  }

  void hline(int c0, int c1, int r, {double a = 1, bool accent = false}) {
    for (var c = c0; c <= c1; c++) {
      set(c, r, a: a, accent: accent);
    }
  }
}

const _caret = ['.X.', 'X.X', '...'];
const _cross = ['X.X', '.X.', 'X.X'];
const _less = ['..X', '.X.', 'X..', '.X.', '..X'];
const _more = ['X..', '.X.', '..X', '.X.', 'X..'];
const _zed = ['XXX', '.X.', 'XXX'];

const _confetti = [
  (0, 1),
  (2, 0),
  (5, 1),
  (11, 1),
  (14, 0),
  (16, 2),
  (0, 13),
  (16, 13),
  (3, 14),
  (13, 14),
  (0, 4),
  (16, 4),
];

const _gaze = [0, -1, -1, 0, 1, 1, 0, 0];

/// Builds the dots of [state] at [seconds] into the loop.
MascotFrame buildMascotFrame(MascotState state, double seconds) {
  final t = seconds % MascotGrid.loopSeconds;
  final f = MascotFrame();
  final pulse = 0.5 + 0.5 * math.sin(2 * math.pi * t / 2);

  // Vertical offset of the head: hops and breathing.
  var dy = 0;
  if (state == MascotState.celebrating) dy = (t * 3).floor() % 2;
  if (state == MascotState.sleeping) dy = t >= 2 ? 1 : 0;

  void head(int c, int r, {double a = 1, bool accent = false}) =>
      f.set(c, r + dy, a: a, accent: accent);
  void headPattern(int c, int r, List<String> p, {bool accent = false}) =>
      f.pattern(c, r + dy, p, accent: accent);
  void headLine(int c0, int c1, int r) => f.hline(c0, c1, r + dy);

  // Shadow under the head.
  f.hline(5, 11, 14, a: 0.35);

  // Head outline: stepped corners, sides and ears.
  headLine(3, 13, 3);
  headLine(3, 13, 12);
  for (var r = 5; r <= 10; r++) {
    head(1, r);
    head(15, r);
  }
  for (final (c, r) in [(2, 4), (14, 4), (2, 11), (14, 11)]) {
    head(c, r);
  }
  for (var r = 6; r <= 8; r++) {
    head(0, r);
    head(16, r);
  }

  // Antenna with the spark on top; a fork for the code mascot.
  head(8, 2);
  head(8, 1, a: state == MascotState.sleeping ? 0.4 : 1);
  if (state == MascotState.github) {
    final right = t < 2;
    head(7, 0, accent: !right, a: right ? 1 : 0.6 + 0.4 * pulse);
    head(9, 0, accent: right, a: right ? 0.6 + 0.4 * pulse : 1);
  } else {
    final double spark;
    switch (state) {
      case MascotState.sleeping:
        spark = 0.2;
      case MascotState.error:
        spark = (t * 4).floor().isEven ? 1 : 0.15;
      case MascotState.offline:
        spark = (t * 6).floor() % 5 == 0 ? 0.8 : 0.12;
      case MascotState.celebrating:
        spark = (t * 6).floor().isEven ? 1 : 0.4;
      default:
        spark = 0.45 + 0.55 * pulse;
    }
    head(8, 0, accent: true, a: spark);
  }

  // Square eyes, 2 wide and 3 tall; [gx]/[gy] move the gaze.
  const left = 4, right = 11;
  void eyes(int gx, int gy, {bool blink = false}) {
    for (final c in [left + gx, right + gx]) {
      for (var r = blink ? 7 : 6; r <= (blink ? 7 : 8); r++) {
        head(c, r + gy);
        head(c + 1, r + gy);
      }
    }
  }

  void smile() {
    headLine(7, 9, 10);
    head(6, 9);
    head(10, 9);
  }

  switch (state) {
    case MascotState.idle:
      eyes(t >= 1.0 && t < 1.8 ? 1 : 0, 0, blink: t >= 2.6 && t < 2.75);
      smile();
    case MascotState.thinking:
      eyes(1, -1);
      headLine(7, 9, 10);
      final on = (t / 0.4).floor() % 4;
      for (var i = 0; i < 3; i++) {
        f.set(12 + i * 2, 1, accent: on == i, a: on == i ? 1 : 0.35);
      }
    case MascotState.writing:
      eyes(0, 1);
      final n = 1 + ((t / MascotGrid.loopSeconds) * 9).floor();
      for (var i = 0; i < n && i < 9; i++) {
        head(4 + i, 11, accent: true);
      }
      if ((t * 4).floor().isEven && n < 9) head(4 + n, 11, a: 0.8);
    case MascotState.searching:
      eyes(_gaze[(t * 2).floor() % _gaze.length], 0);
      head(8, 9, a: 0.9);
      head(7, 10);
      head(9, 10);
      head(8, 11, a: 0.9);
    case MascotState.celebrating:
      headPattern(left, 6, _caret);
      headPattern(right - 1, 6, _caret);
      headLine(6, 10, 9);
      headLine(7, 9, 10);
      for (var i = 0; i < _confetti.length; i++) {
        final s = 0.5 + 0.5 * math.sin(2 * math.pi * (t + i / 5));
        if (s > 0.35) {
          f.set(_confetti[i].$1, _confetti[i].$2, accent: i.isEven, a: s);
        }
      }
    case MascotState.sleeping:
      headLine(left, left + 2, 8);
      headLine(right - 1, right + 1, 8);
      head(8, 10);
      final z = (t / 2) % 1.0;
      f.pattern(13, 0, _zed, a: math.sin(math.pi * z).clamp(0.15, 1.0));
      f.set(11, 1, a: math.sin(math.pi * ((z + 0.5) % 1.0)).clamp(0.15, 1.0));
    case MascotState.error:
      headPattern(left, 6, _cross, accent: true);
      headPattern(right - 1, 6, _cross, accent: true);
      headLine(7, 9, 10);
      head(6, 11);
      head(10, 11);
      if ((t * 3).floor().isEven) {
        f.set(15, 0, accent: true);
        f.set(15, 1, accent: true);
        f.set(15, 3, accent: true);
      }
    case MascotState.offline:
      for (final c in [left, left + 1, right, right + 1]) {
        head(c, 8, a: 0.6);
      }
      head(6, 10);
      head(7, 11);
      head(8, 10);
      head(9, 11);
      head(10, 10);
      // Signal bars; only the first one tries to blink.
      for (var i = 0; i < 3; i++) {
        final live = i == 0 && (t * 2).floor().isEven;
        for (var h = 0; h <= i; h++) {
          f.set(13 + i, 2 - h, accent: i == 0, a: live ? 1 : 0.25);
        }
      }
    case MascotState.github:
      headPattern(left, 5, _less);
      headPattern(right - 1, 5, _more);
      smile();
  }
  return f;
}
