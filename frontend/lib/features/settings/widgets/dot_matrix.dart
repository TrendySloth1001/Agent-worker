import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/constants/settings_copy.dart';
import '../../../core/theme/app_palette.dart';

/// A square dot lattice that fades out towards its edges. The Nothing-style
/// texture behind the profile avatar and in empty states.
class DotGrid extends StatelessWidget {
  const DotGrid({super.key, required this.size, this.color});

  final double size;

  /// Defaults to the tertiary text colour.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size.square(size),
        painter: _DotGridPainter(color ?? context.palette.textTertiary),
      ),
    );
  }
}

class _DotGridPainter extends CustomPainter {
  _DotGridPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const step = SettingsSizes.dotSpacing;
    final center = size.center(Offset.zero);
    final reach = size.width / 2;
    final paint = Paint();
    final count = (size.width / step).floor();
    final inset = (size.width - (count - 1) * step) / 2;
    for (var y = 0; y < count; y++) {
      for (var x = 0; x < count; x++) {
        final at = Offset(inset + x * step, inset + y * step);
        final t = ((at - center).distance / reach).clamp(0.0, 1.0);
        final alpha = (1 - t * t) * 0.55;
        if (alpha <= 0.02) continue;
        paint.color = color.withValues(alpha: alpha);
        canvas.drawCircle(at, SettingsSizes.dotRadius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotGridPainter old) => old.color != color;
}

/// Up to two letters drawn in a 5x7 dot-matrix font, centred in a circle.
/// Used as the avatar when the account has no photo.
class DotMonogram extends StatelessWidget {
  const DotMonogram({
    super.key,
    required this.text,
    required this.size,
    this.color,
  });

  final String text;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: CustomPaint(
        size: Size.square(size),
        painter: _MonogramPainter(
          text: text,
          color: color ?? p.textPrimary,
          background: p.surfaceRaised,
          border: p.borderStrong,
        ),
      ),
    );
  }
}

class _MonogramPainter extends CustomPainter {
  _MonogramPainter({
    required this.text,
    required this.color,
    required this.background,
    required this.border,
  });

  final String text;
  final Color color, background, border;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    canvas.drawCircle(Offset(r, r), r, Paint()..color = background);
    canvas.drawCircle(
      Offset(r, r),
      r - 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = border,
    );
    final letters = text
        .toUpperCase()
        .runes
        .map(String.fromCharCode)
        .take(2)
        .map((c) => _glyphs[c] ?? _glyphs['?']!)
        .toList();
    if (letters.isEmpty) return;
    const cols = 5, rows = 7, gap = 1;
    final totalCols = letters.length * cols + (letters.length - 1) * gap;
    // Fit the glyph block inside the circle's inscribed square.
    final cell = math.min(
      size.width * 0.62 / totalCols,
      size.height * 0.5 / rows,
    );
    final left = (size.width - totalCols * cell) / 2;
    final top = (size.height - rows * cell) / 2;
    final dot = Paint()..color = color;
    for (var l = 0; l < letters.length; l++) {
      for (var y = 0; y < rows; y++) {
        for (var x = 0; x < cols; x++) {
          if (letters[l][y][x] != '#') continue;
          final cx = left + ((l * (cols + gap)) + x + 0.5) * cell;
          final cy = top + (y + 0.5) * cell;
          canvas.drawCircle(Offset(cx, cy), cell * 0.38, dot);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_MonogramPainter old) =>
      old.text != text || old.color != color || old.background != background;
}

/// A small cluster of dots with one lit in the accent colour. Sits at the end
/// of the large title bar.
class DotAccent extends StatelessWidget {
  const DotAccent({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget dot(Color c) => Container(
      width: SettingsSizes.accentDot,
      height: SettingsSizes.accentDot,
      margin: const EdgeInsets.symmetric(horizontal: SettingsSizes.accentGap),
      decoration: BoxDecoration(shape: BoxShape.circle, color: c),
    );
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.only(right: SettingsSizes.headerInset),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [dot(p.border), dot(p.borderStrong), dot(p.accent)],
        ),
      ),
    );
  }
}

const _glyphs = <String, List<String>>{
  'A': ['.###.', '#...#', '#...#', '#####', '#...#', '#...#', '#...#'],
  'B': ['####.', '#...#', '#...#', '####.', '#...#', '#...#', '####.'],
  'C': ['.###.', '#...#', '#....', '#....', '#....', '#...#', '.###.'],
  'D': ['####.', '#...#', '#...#', '#...#', '#...#', '#...#', '####.'],
  'E': ['#####', '#....', '#....', '####.', '#....', '#....', '#####'],
  'F': ['#####', '#....', '#....', '####.', '#....', '#....', '#....'],
  'G': ['.###.', '#...#', '#....', '#.###', '#...#', '#...#', '.###.'],
  'H': ['#...#', '#...#', '#...#', '#####', '#...#', '#...#', '#...#'],
  'I': ['.###.', '..#..', '..#..', '..#..', '..#..', '..#..', '.###.'],
  'J': ['..###', '...#.', '...#.', '...#.', '...#.', '#..#.', '.##..'],
  'K': ['#...#', '#..#.', '#.#..', '##...', '#.#..', '#..#.', '#...#'],
  'L': ['#....', '#....', '#....', '#....', '#....', '#....', '#####'],
  'M': ['#...#', '##.##', '#.#.#', '#.#.#', '#...#', '#...#', '#...#'],
  'N': ['#...#', '##..#', '#.#.#', '#..##', '#...#', '#...#', '#...#'],
  'O': ['.###.', '#...#', '#...#', '#...#', '#...#', '#...#', '.###.'],
  'P': ['####.', '#...#', '#...#', '####.', '#....', '#....', '#....'],
  'Q': ['.###.', '#...#', '#...#', '#...#', '#.#.#', '#..#.', '.##.#'],
  'R': ['####.', '#...#', '#...#', '####.', '#.#..', '#..#.', '#...#'],
  'S': ['.####', '#....', '#....', '.###.', '....#', '....#', '####.'],
  'T': ['#####', '..#..', '..#..', '..#..', '..#..', '..#..', '..#..'],
  'U': ['#...#', '#...#', '#...#', '#...#', '#...#', '#...#', '.###.'],
  'V': ['#...#', '#...#', '#...#', '#...#', '#...#', '.#.#.', '..#..'],
  'W': ['#...#', '#...#', '#...#', '#.#.#', '#.#.#', '##.##', '#...#'],
  'X': ['#...#', '#...#', '.#.#.', '..#..', '.#.#.', '#...#', '#...#'],
  'Y': ['#...#', '#...#', '.#.#.', '..#..', '..#..', '..#..', '..#..'],
  'Z': ['#####', '....#', '...#.', '..#..', '.#...', '#....', '#####'],
  '0': ['.###.', '#...#', '#..##', '#.#.#', '##..#', '#...#', '.###.'],
  '1': ['..#..', '.##..', '..#..', '..#..', '..#..', '..#..', '.###.'],
  '2': ['.###.', '#...#', '....#', '...#.', '..#..', '.#...', '#####'],
  '3': ['####.', '....#', '....#', '.###.', '....#', '....#', '####.'],
  '4': ['...#.', '..##.', '.#.#.', '#..#.', '#####', '...#.', '...#.'],
  '5': ['#####', '#....', '####.', '....#', '....#', '#...#', '.###.'],
  '6': ['.###.', '#....', '#....', '####.', '#...#', '#...#', '.###.'],
  '7': ['#####', '....#', '...#.', '..#..', '.#...', '.#...', '.#...'],
  '8': ['.###.', '#...#', '#...#', '.###.', '#...#', '#...#', '.###.'],
  '9': ['.###.', '#...#', '#...#', '.####', '....#', '....#', '.###.'],
  '?': ['.###.', '#...#', '....#', '...#.', '..#..', '.....', '..#..'],
};
