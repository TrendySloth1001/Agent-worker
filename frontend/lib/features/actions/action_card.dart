import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/constants/device_actions.dart';
import '../../core/haptics.dart';
import '../../core/theme/app_palette.dart';
import '../../core/widgets/app_icon.dart';
import '../chat/widgets/markdown/code_block.dart';
import 'device_action.dart';
import 'device_action_runner.dart';

/// Where a card is: waiting for the user, running, or finished.
enum ActionCardState { pending, running, done, cancelled, failed }

/// A ```sparky-action block in an answer (chat or overlay): what the model
/// wants to do on the phone, with Confirm / Cancel. Nothing runs until
/// Confirm, and only then through [DeviceActionRunner].
class ActionCard extends StatefulWidget {
  const ActionCard({super.key, required this.source, this.runner});

  final String source;

  /// Defaults to [DeviceActionRunner.instance].
  final DeviceActionRunner? runner;

  /// Outcomes by action, so a card rebuilt after scrolling (or a rerender of
  /// the same answer) does not offer Confirm again.
  static final Map<String, (ActionCardState, String?)> _outcomes = {};

  @visibleForTesting
  static void resetOutcomes() => _outcomes.clear();

  @override
  State<ActionCard> createState() => _ActionCardState();
}

class _ActionCardState extends State<ActionCard> {
  late DeviceAction? _action = DeviceAction.parse(widget.source);
  ActionCardState _state = ActionCardState.pending;
  String? _message;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void didUpdateWidget(ActionCard old) {
    super.didUpdateWidget(old);
    if (old.source != widget.source) {
      _action = DeviceAction.parse(widget.source);
      _state = ActionCardState.pending;
      _message = null;
      _restore();
    }
  }

  void _restore() {
    final a = _action;
    final saved = a == null ? null : ActionCard._outcomes[a.key];
    if (saved != null) {
      _state = saved.$1;
      _message = saved.$2;
    }
  }

  void _settle(ActionCardState state, [String? message]) {
    final a = _action;
    if (a == null) return;
    if (ActionCard._outcomes.length >= DeviceActionSizes.rememberedOutcomes) {
      ActionCard._outcomes.remove(ActionCard._outcomes.keys.first);
    }
    ActionCard._outcomes[a.key] = (state, message);
    if (mounted) {
      setState(() {
        _state = state;
        _message = message;
      });
    }
  }

  Future<void> _confirm() async {
    final a = _action;
    if (a == null || _state != ActionCardState.pending) return;
    Haptics.send();
    setState(() => _state = ActionCardState.running);
    final runner = widget.runner ?? DeviceActionRunner.instance;
    final outcome = await runner.run(a);
    switch (outcome) {
      case ActionOutcome.done:
        Haptics.received();
        _settle(ActionCardState.done, a.doneLabel);
      case ActionOutcome.notFound:
        Haptics.error();
        _settle(ActionCardState.failed, DeviceActionStrings.notFound);
      case ActionOutcome.unavailable:
        Haptics.error();
        _settle(ActionCardState.failed, DeviceActionStrings.unavailable);
      case ActionOutcome.notifyOff:
        Haptics.error();
        _settle(ActionCardState.failed, DeviceActionStrings.notifyOff);
      case ActionOutcome.failed:
        Haptics.error();
        _settle(ActionCardState.failed, DeviceActionStrings.failed);
    }
  }

  void _cancel() {
    if (_state != ActionCardState.pending) return;
    Haptics.tap();
    _settle(ActionCardState.cancelled, DeviceActionStrings.cancelled);
  }

  @override
  Widget build(BuildContext context) {
    final a = _action;
    // Not an action the phone can run: show what the model wrote.
    if (a == null) {
      return CodeBlock(code: widget.source, language: DeviceActionWire.fence);
    }
    final p = context.palette;
    final t = context.text;
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    final enabled = scope?.settings.assistActions ?? true;
    final supported = DeviceActionRunner.supported;
    final blocked = !supported
        ? DeviceActionStrings.notHere
        : !enabled
        ? DeviceActionStrings.off
        : null;
    final details = a.details;
    return Semantics(
      container: true,
      label: '${a.kicker}. ${a.title}',
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: p.isDark ? p.surfaceHigh : p.surfaceRaised,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: p.border, width: AppBorder.thin),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: DeviceActionSizes.iconCircle,
                  height: DeviceActionSizes.iconCircle,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: p.accent,
                  ),
                  child: AppIcon(
                    a.icon,
                    size: AppIconSize.md,
                    color: p.textInverse,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.kicker, style: t.caption),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        a.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.title,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (details.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              for (final (label, value) in details)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: DeviceActionSizes.labelWidth,
                        child: Text(label.toUpperCase(), style: t.caption),
                      ),
                      Expanded(
                        child: Text(
                          value,
                          maxLines: DeviceActionSizes.maxDetailLines,
                          overflow: TextOverflow.ellipsis,
                          style: t.bodySmall.copyWith(color: p.textPrimary),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            if (a.hint != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(a.hint!, style: t.bodySmall),
            ],
            const SizedBox(height: AppSpacing.lg),
            if (_state == ActionCardState.pending && blocked != null)
              Text(blocked, style: t.bodySmall)
            else if (_state == ActionCardState.pending ||
                _state == ActionCardState.running)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _CardButton(
                    label: DeviceActionStrings.cancel,
                    onTap: _state == ActionCardState.running ? null : _cancel,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _CardButton(
                    label: _state == ActionCardState.running
                        ? DeviceActionStrings.running
                        : DeviceActionStrings.confirm,
                    filled: true,
                    onTap: _state == ActionCardState.running ? null : _confirm,
                  ),
                ],
              )
            else
              _Outcome(state: _state, message: _message ?? ''),
          ],
        ),
      ),
    );
  }
}

class _CardButton extends StatelessWidget {
  const _CardButton({required this.label, this.onTap, this.filled = false});

  final String label;
  final VoidCallback? onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fg = filled ? p.textInverse : p.textPrimary;
    return Semantics(
      button: true,
      enabled: onTap != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppDurations.fast,
          height: DeviceActionSizes.buttonHeight,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: filled ? p.textPrimary : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: filled ? p.textPrimary : p.borderStrong,
              width: AppBorder.thin,
            ),
          ),
          child: Text(
            label,
            style: context.text.bodySmall.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _Outcome extends StatelessWidget {
  const _Outcome({required this.state, required this.message});

  final ActionCardState state;
  final String message;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (icon, color) = switch (state) {
      ActionCardState.done => (DeviceActionIcons.done, p.textPrimary),
      ActionCardState.failed => (DeviceActionIcons.failed, p.error),
      _ => (DeviceActionIcons.cancelled, p.textTertiary),
    };
    return Row(
      children: [
        AppIcon(icon, size: AppIconSize.sm, color: color),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            message,
            style: context.text.bodySmall.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}
