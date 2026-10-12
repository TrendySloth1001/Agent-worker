import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/constants/settings_copy.dart';

import '../../core/constants/app_sizes.dart';
import '../../core/constants/docs.dart';
import '../../core/theme/app_palette.dart';
import '../../core/widgets/dot_meter.dart';
import '../../data/doc_models.dart';
import 'doc_controller.dart';
import 'doc_section_menu.dart';

/// Whether the reader shows the progress bar for [doc].
bool showsDocProgress(Doc doc) =>
    doc.isRunning ||
    doc.status == DocStatus.outlineReady ||
    DocStatus.canResume(doc.status);

/// Live progress: phase, sections done, ETA, a dot meter, and STOP /
/// RESUME / START. The ETA counts down locally between status events.
class DocProgressBar extends StatefulWidget {
  const DocProgressBar({super.key, required this.controller});

  final DocController controller;

  @override
  State<DocProgressBar> createState() => _DocProgressBarState();
}

class _DocProgressBarState extends State<DocProgressBar> {
  Timer? _tick;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(TableMeterSizes.tick, (_) {
      if (mounted && widget.controller.doc.isRunning) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _run(Future<bool> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) docToast(context, DocStrings.actionFailed);
  }

  int? _etaLeft(Doc doc) {
    final eta = doc.etaMs;
    if (eta == null || eta <= 0) return null;
    final since = doc.statusAt == null
        ? 0
        : DateTime.now().difference(doc.statusAt!).inMilliseconds;
    final left = eta - since;
    return left > 0 ? left : null;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final doc = c.doc;
    final p = context.palette;
    final t = context.text;
    final total = doc.total > 0 ? doc.total : doc.body.length;
    final done = doc.body.where((s) => s.isDone).length;
    final eta = _etaLeft(doc);
    final running = doc.isRunning;
    final String label;
    if (c.reconnecting) {
      label = DocStrings.reconnecting;
    } else if (running) {
      label = DocStrings.phase(doc.phase.isEmpty ? doc.status : doc.phase);
    } else if (doc.status == DocStatus.outlineReady) {
      label = DocStrings.outlineReadyHint;
    } else {
      label = DocStrings.status(doc.status);
    }
    final detail = [
      if (total > 0) DocStrings.doneOf(done, total),
      if (running && eta != null) DocStrings.eta(eta),
    ].join(DocStrings.sep);

    final Widget action;
    if (running) {
      action = DocTextButton(
        label: DocStrings.stop,
        icon: DocIcons.stop,
        accent: true,
        onTap: _busy ? null : () => _run(c.stop),
      );
    } else if (doc.status == DocStatus.outlineReady) {
      action = DocTextButton(
        label: DocStrings.start,
        filled: true,
        onTap: _busy ? null : () => _run(c.startWriting),
      );
    } else {
      action = DocTextButton(
        label: DocStrings.resume,
        icon: DocIcons.resume,
        filled: true,
        onTap: _busy ? null : () => _run(c.resume),
      );
    }

    return Container(
      constraints: const BoxConstraints(minHeight: DocSizes.progressHeight),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(SettingsSizes.groupOuterRadius),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _Pulse(active: running, color: p.accent),
                    const SizedBox(width: AppSpacing.sm),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodySmall.copyWith(
                          color: p.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                if (detail.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodySmall.copyWith(
                      fontSize: DocSizes.metaSize,
                      color: p.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.xs),
                DotMeter(
                  fraction: total == 0 ? 0 : done / total,
                  litColor: running ? p.accent : p.textPrimary,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          action,
        ],
      ),
    );
  }
}

/// A dot that breathes while [active].
class _Pulse extends StatefulWidget {
  const _Pulse({required this.active, required this.color});

  final bool active;
  final Color color;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(vsync: this, duration: DocSizes.pulse);

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_Pulse old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.active && !_anim.isAnimating) {
      _anim.repeat(reverse: true);
    } else if (!widget.active && _anim.isAnimating) {
      _anim.stop();
      _anim.value = 1;
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: DocSizes.pulseMin, end: 1.0).animate(_anim),
      child: Container(
        width: DocSizes.statusDot,
        height: DocSizes.statusDot,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.active ? widget.color : context.palette.textTertiary,
        ),
      ),
    );
  }
}

/// One status dot per section: done solid, writing accent, failed accent
/// ring, pending hollow.
class DocStatusDot extends StatelessWidget {
  const DocStatusDot({
    super.key,
    required this.status,
    this.size = DocSizes.statusDot,
  });

  final String status;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (Color? fill, Color ring) = switch (status) {
      DocSectionStatus.done => (p.textPrimary, p.textPrimary),
      DocSectionStatus.writing => (p.accent, p.accent),
      DocSectionStatus.failed => (null, p.accent),
      _ => (null, p.borderStrong),
    };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fill,
        border: Border.all(color: ring, width: AppBorder.thin),
      ),
    );
  }
}
