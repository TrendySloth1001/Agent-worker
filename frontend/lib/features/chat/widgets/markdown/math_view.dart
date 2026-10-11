import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/markdown_sizes.dart';
import '../../../../core/haptics.dart';
import '../../../../core/theme/app_palette.dart';

/// TeX that failed to parse: the source in inline-code style.
Widget _raw(BuildContext context, String tex) {
  final p = context.palette;
  return Text(
    tex,
    style: context.text.code.copyWith(
      fontSize: MdSizes.tableCodeFontSize,
      color: p.textPrimary,
      backgroundColor: p.surfaceHigh,
    ),
  );
}

/// Math inside a sentence, at the surrounding font size and colour. Sits on
/// the text baseline of its line; wider than the line: scaled down to fit.
class InlineMath extends StatelessWidget {
  const InlineMath({
    super.key,
    required this.tex,
    required this.fontSize,
    required this.color,
  });

  final String tex;
  final double fontSize;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Math.tex(
        tex,
        mathStyle: MathStyle.text,
        textStyle: TextStyle(fontSize: fontSize, color: color),
        onErrorFallback: (_) => _raw(context, tex),
      ),
    );
  }
}

/// Math inside a table cell: shrinks toward [MdSizes.tableMathMinScale] to
/// fit the column, and only then scrolls sideways at that scale.
class TableMath extends StatefulWidget {
  const TableMath({
    super.key,
    required this.tex,
    required this.fontSize,
    required this.color,
  });

  final String tex;
  final double fontSize;
  final Color color;

  @override
  State<TableMath> createState() => _TableMathState();
}

class _TableMathState extends State<TableMath> {
  final _key = GlobalKey();
  double _scale = 1;
  double _avail = 0;

  void _measure() {
    if (!mounted || _avail <= 0) return;
    final w = _key.currentContext?.size?.width;
    if (w == null || w <= 0) return;
    // One-way ratchet (never grows back) so measuring cannot oscillate.
    final next = (_scale * _avail / w).clamp(MdSizes.tableMathMinScale, 1.0);
    if (next < _scale - 0.01) setState(() => _scale = next);
  }

  @override
  void didUpdateWidget(TableMath old) {
    super.didUpdateWidget(old);
    if (old.tex != widget.tex || old.fontSize != widget.fontSize) _scale = 1;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final math = Math.tex(
          widget.tex,
          key: _key,
          mathStyle: MathStyle.text,
          textStyle: TextStyle(
            fontSize: widget.fontSize * _scale,
            color: widget.color,
          ),
          onErrorFallback: (_) => _raw(context, widget.tex),
        );
        if (!box.hasBoundedWidth) return math;
        if ((_avail - box.maxWidth).abs() > 0.5) {
          _avail = box.maxWidth;
          _scale = 1;
        }
        WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
        return ConstrainedBox(
          constraints: BoxConstraints(maxWidth: box.maxWidth),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: math,
          ),
        );
      },
    );
  }
}

/// `$$ … $$`, `\[ … \]` or a ```math fence: centred, scrolls sideways when
/// wider than the screen. Long-press copies the TeX.
class MathBlock extends StatefulWidget {
  const MathBlock({super.key, required this.tex});

  final String tex;

  @override
  State<MathBlock> createState() => _MathBlockState();
}

class _MathBlockState extends State<MathBlock> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.tex));
    Haptics.tap();
    if (!mounted) return;
    setState(() => _copied = true);
    await Future.delayed(AppDurations.copiedFeedback);
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final body = context.text.body;
    final color = _copied ? p.accent : p.textPrimary;
    return GestureDetector(
      onLongPress: _copy,
      behavior: HitTestBehavior.opaque,
      child: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: box.hasBoundedWidth ? box.maxWidth : 0,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Center(
                child: Math.tex(
                  widget.tex,
                  mathStyle: MathStyle.display,
                  textStyle: TextStyle(
                    fontSize: body.fontSize! * MdSizes.mathDisplayScale,
                    color: color,
                  ),
                  onErrorFallback: (_) => _raw(context, widget.tex),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
