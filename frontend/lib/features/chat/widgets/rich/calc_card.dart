import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/widget_kit.dart';
import '../../../../core/constants/widget_playful.dart';
import '../../../../core/haptics.dart';
import '../../../../core/theme/app_palette.dart';
import 'calc_eval.dart';
import 'playful_common.dart';
import 'rich_frame.dart';

class CalcInput {
  const CalcInput(
    this.id,
    this.label,
    this.def,
    this.min,
    this.max,
    this.suffix,
    this.step,
  );
  final String id, label, suffix;
  final double def, min, max, step;
}

class CalcOutput {
  const CalcOutput(this.id, this.label, this.expr, this.suffix, this.decimals);

  /// Variable name later outputs use to refer to this one.
  final String id;
  final String label, suffix;
  final CalcExpr expr;
  final int decimals;
}

class CalcData {
  const CalcData(this.title, this.inputs, this.outputs);
  final String title;
  final List<CalcInput> inputs;
  final List<CalcOutput> outputs;
}

/// Parses a ```calc block; null when it has no outputs.
CalcData? parseCalc(String src) {
  var title = '';
  final inputs = <CalcInput>[];
  final outputs = <CalcOutput>[];
  for (final line in playfulLines(src)) {
    final kv = playfulKeyValue(line);
    if (kv == null) continue;
    final (key, value) = kv;
    final parts = value.split('|').map((e) => e.trim()).toList();
    if (key == 'title') {
      title = value;
    } else if (key == 'input' &&
        inputs.length < PlayfulLimits.calcInputs &&
        parts.length >= 3) {
      final id = parts[0].toLowerCase();
      if (!RegExp(r'^[a-z_][a-z0-9_]*$').hasMatch(id)) continue;
      final def = double.tryParse(parts[2]);
      if (def == null) continue;
      var lo = 0.0, hi = def == 0 ? 100.0 : def.abs() * 4;
      if (parts.length > 3 && parts[3].contains('..')) {
        final r = parts[3].split('..');
        lo = double.tryParse(r[0].trim()) ?? lo;
        hi = double.tryParse(r[1].trim()) ?? hi;
      }
      if (hi <= lo) hi = lo + 1;
      final frac = [
        parts[2],
        if (parts.length > 3) parts[3],
      ].any((s) => s.replaceAll('..', '|').contains('.'));
      inputs.add(
        CalcInput(
          id,
          parts[1].isEmpty ? id : parts[1],
          def.clamp(lo, hi).toDouble(),
          lo,
          hi,
          parts.length > 4 ? parts[4] : '',
          frac ? 0.01 : 1,
        ),
      );
    } else if (key == 'out' &&
        outputs.length < PlayfulLimits.calcOutputs &&
        parts.length >= 2) {
      try {
        final id = '__o${outputs.length}';
        outputs.add(
          CalcOutput(
            id,
            parts[0],
            CalcExpr.parse(_referToOutputs(parts[1], outputs)),
            parts.length > 2 ? parts[2] : '',
            (parts.length > 3 ? int.tryParse(parts[3]) ?? 2 : 2).clamp(0, 6),
          ),
        );
      } on FormatException {
        continue;
      }
    }
  }
  if (outputs.isEmpty) return null;
  return CalcData(title, inputs, outputs);
}

/// Models write later outputs in terms of earlier ones by name
/// ("EMI*years*12", "Total payment - principal"). Each earlier output's label
/// (full, without its "(...)" part, and as a slug) becomes its variable.
String _referToOutputs(String expr, List<CalcOutput> earlier) {
  final names = <(String, String)>[];
  for (final o in earlier) {
    final full = o.label.trim();
    final short = full.replaceAll(RegExp(r'\s*\(.*?\)\s*'), ' ').trim();
    final slug = full
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    for (final n in {full, short, slug}) {
      if (n.isNotEmpty) names.add((n, o.id));
    }
  }
  // Longest first, so "Total payment" wins over "Total".
  names.sort((a, b) => b.$1.length.compareTo(a.$1.length));
  var out = expr;
  for (final (name, id) in names) {
    out = out.replaceAll(
      RegExp(
        '(?<![A-Za-z0-9_])${RegExp.escape(name)}(?![A-Za-z0-9_])',
        caseSensitive: false,
      ),
      id,
    );
  }
  return out;
}

/// Currency symbols read before the number: ₹2,000,000.
const _prefixSymbols = {r'$', '€', '£', '¥', '₹', '₩', '₽', '₺', '₦', '₱'};

/// 12345.678 -> `12,345.68`
String formatCalcNumber(double v, int decimals) {
  final s = v.abs().toStringAsFixed(decimals);
  final dot = s.indexOf('.');
  final whole = dot < 0 ? s : s.substring(0, dot);
  final frac = dot < 0 ? '' : s.substring(dot);
  final b = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) b.write(',');
    b.write(whole[i]);
  }
  final neg = v < 0 && double.parse(s) != 0;
  return '${neg ? '-' : ''}$b$frac';
}

String _withSuffix(String num, String suffix) {
  if (suffix.isEmpty) return num;
  if (_prefixSymbols.contains(suffix)) {
    return num.startsWith('-') ? '-$suffix${num.substring(1)}' : '$suffix$num';
  }
  return '$num${suffix.length <= 2 ? '' : ' '}$suffix';
}

/// ```calc block: sliders feed live outputs.
class CalcCard extends StatefulWidget {
  const CalcCard({super.key, required this.source});

  final String source;

  @override
  State<CalcCard> createState() => _CalcCardState();
}

class _CalcCardState extends State<CalcCard> {
  late CalcData? _data = parseCalc(widget.source);
  late Map<String, double> _vals = _defaults();

  Map<String, double> _defaults() => {
    for (final i in _data?.inputs ?? const <CalcInput>[]) i.id: i.def,
  };

  @override
  void didUpdateWidget(CalcCard old) {
    super.didUpdateWidget(old);
    if (old.source != widget.source) {
      _data = parseCalc(widget.source);
      _vals = _defaults();
    }
  }

  /// Inputs plus every output computed so far, in order.
  Map<String, double> _withOutputsUpTo(CalcOutput target) {
    final vars = {..._vals};
    for (final o in _data?.outputs ?? const <CalcOutput>[]) {
      if (identical(o, target)) break;
      final v = o.expr.eval(vars);
      if (v != null) vars[o.id] = v;
    }
    return vars;
  }

  String _out(CalcOutput o) {
    final v = o.expr.eval(_withOutputsUpTo(o));
    if (v == null) return PlayfulStrings.dash;
    return _withSuffix(formatCalcNumber(v, o.decimals), o.suffix);
  }

  Future<void> _edit(CalcInput i) async {
    Haptics.tap();
    final ctl = TextEditingController(text: _fmtInput(i, _vals[i.id]!));
    final p = context.palette;
    final t = context.text;
    final res = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.surfaceHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(color: p.border),
        ),
        title: Text(i.label.toUpperCase(), style: t.label),
        content: TextField(
          controller: ctl,
          autofocus: true,
          maxLength: PlayfulSizes.inputMaxLength,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
          ],
          style: t.body,
          cursorColor: p.accent,
          decoration: InputDecoration(
            counterText: '',
            helperText: '${_fmtInput(i, i.min)} .. ${_fmtInput(i, i.max)}',
            helperStyle: t.caption,
            suffixText: i.suffix,
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: p.accent),
            ),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, double.tryParse(v)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              PlayfulStrings.cancel,
              style: t.caption.copyWith(color: p.textTertiary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, double.tryParse(ctl.text)),
            child: Text(
              PlayfulStrings.ok,
              style: t.caption.copyWith(color: p.accent),
            ),
          ),
        ],
      ),
    );
    ctl.dispose();
    if (res != null && mounted) {
      setState(() => _vals[i.id] = res.clamp(i.min, i.max).toDouble());
    }
  }

  String _fmtInput(CalcInput i, double v) =>
      formatCalcNumber(v, i.step < 1 ? 2 : 0).replaceAll(',', '');

  String _csv() {
    final d = _data!;
    return [
      if (d.title.isNotEmpty) d.title,
      for (final i in d.inputs)
        '${i.label}: ${_withSuffix(formatCalcNumber(_vals[i.id]!, i.step < 1 ? 2 : 0), i.suffix)}',
      for (final o in d.outputs) '${o.label}: ${_out(o)}',
    ].join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    if (d == null) {
      return PlayfulFallback(
        title: WidgetKitStrings.calc,
        source: widget.source,
      );
    }
    final p = context.palette;
    final t = context.text;
    return RichCard(
      title: d.title.isEmpty
          ? WidgetKitStrings.calc
          : '${WidgetKitStrings.calc} / ${d.title.toUpperCase()}',
      actions: [
        RichAction(
          icon: PlayfulIcons.reset,
          label: PlayfulStrings.reset,
          onTap: () async {
            setState(() => _vals = _defaults());
            return true;
          },
        ),
        RichAction.copy(text: _csv(), label: PlayfulStrings.copyResults),
      ],
      child: Padding(
        padding: const EdgeInsets.all(PlayfulSizes.pad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final i in d.inputs) _inputRow(context, i),
            if (d.inputs.isNotEmpty)
              Divider(color: p.border, height: AppSpacing.xl),
            for (var k = 0; k < d.outputs.length; k++)
              Padding(
                padding: EdgeInsets.only(
                  bottom: k == d.outputs.length - 1 ? 0 : AppSpacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.outputs[k].label.toUpperCase(), style: t.caption),
                    const SizedBox(height: AppSpacing.xs),
                    DotNumber(
                      _out(d.outputs[k]),
                      size: k == 0
                          ? PlayfulSizes.bigNumberFont + 6
                          : PlayfulSizes.bigNumberFont - 6,
                      color: k == 0 ? p.accent : null,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _inputRow(BuildContext context, CalcInput i) {
    final p = context.palette;
    final t = context.text;
    final v = _vals[i.id]!;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(i.label.toUpperCase(), style: t.caption)),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _edit(i),
                child: Container(
                  constraints: const BoxConstraints(
                    minHeight: PlayfulSizes.btnHeight,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: p.borderStrong)),
                  ),
                  child: Text(
                    _withSuffix(
                      formatCalcNumber(v, i.step < 1 ? 2 : 0),
                      i.suffix,
                    ),
                    style: t.label,
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: PlayfulSizes.sliderTrack,
              activeTrackColor: p.accent,
              inactiveTrackColor: p.border,
              thumbColor: p.accent,
              overlayColor: p.accent.withValues(alpha: PlayfulSizes.flashAlpha),
              thumbShape: const RoundSliderThumbShape(
                enabledThumbRadius: PlayfulSizes.sliderThumb,
                elevation: 0,
                pressedElevation: 0,
              ),
              overlayShape: const RoundSliderOverlayShape(
                overlayRadius: PlayfulSizes.sliderOverlay,
              ),
              trackShape: const RectangularSliderTrackShape(),
            ),
            child: Slider(
              value: v.clamp(i.min, i.max).toDouble(),
              min: i.min,
              max: i.max,
              onChangeStart: (_) => Haptics.tap(),
              onChanged: (nv) {
                final r = i.step < 1
                    ? (nv * 100).roundToDouble() / 100
                    : nv.roundToDouble();
                if (r != _vals[i.id]) {
                  setState(() => _vals[i.id] = r);
                }
              },
              onChangeEnd: (_) => Haptics.tick(),
            ),
          ),
        ],
      ),
    );
  }
}
