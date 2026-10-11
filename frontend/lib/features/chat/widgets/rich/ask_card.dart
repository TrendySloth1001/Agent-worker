import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/rich_cards.dart';
import '../../../../core/haptics.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../chat_actions.dart';

class AskData {
  const AskData({
    required this.question,
    required this.options,
    required this.multi,
    required this.other,
  });

  final String question;
  final List<String> options;
  final bool multi, other;
}

/// Parses a ```ask block; null when the question or options are unusable.
AskData? parseAsk(String src) {
  var question = '';
  var multi = false, other = false;
  final options = <String>[];
  for (final raw in src.replaceAll('\r\n', '\n').split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('- ') || line.startsWith('* ')) {
      final o = line.substring(2).trim();
      if (o.isNotEmpty) options.add(o);
      continue;
    }
    final idx = line.indexOf(':');
    if (idx <= 0) continue;
    final key = line.substring(0, idx).trim().toLowerCase();
    final value = line.substring(idx + 1).trim();
    switch (key) {
      case 'question':
        question = value;
      case 'multi':
        multi = value.toLowerCase() == 'true';
      case 'other':
        other = value.toLowerCase() == 'true';
    }
  }
  if (question.isEmpty || options.length < AskStrings.minOptions) return null;
  return AskData(
    question: question,
    options: options.take(AskStrings.maxOptions).toList(),
    multi: multi,
    other: other,
  );
}

/// Placeholder while an ```ask or ```flow block is still streaming.
class RichPlaceholder extends StatelessWidget {
  const RichPlaceholder({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: p.codeBackground,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: p.border, width: AppBorder.thin),
      ),
      child: Text(label, style: context.text.caption),
    );
  }
}

/// ```ask block: a clarifying question with tappable answers. Sends the pick
/// as the user's next message; only the latest reply's card is active.
class AskCard extends StatefulWidget {
  const AskCard({super.key, required this.data});

  final AskData data;

  @override
  State<AskCard> createState() => _AskCardState();
}

class _AskCardState extends State<AskCard> {
  final Set<String> _picked = {};
  final _otherCtl = TextEditingController();
  bool _otherOpen = false;
  String? _sent;

  @override
  void dispose() {
    _otherCtl.dispose();
    super.dispose();
  }

  void _submit(String answer) {
    final actions = ChatActions.of(context);
    if (actions == null) return;
    Haptics.send();
    setState(() => _sent = answer);
    actions.send(answer);
  }

  void _tap(String option) {
    Haptics.tap();
    if (widget.data.multi) {
      setState(() {
        if (!_picked.remove(option)) _picked.add(option);
      });
    } else {
      _submit(option);
    }
  }

  void _toggleOther() {
    Haptics.tap();
    setState(() => _otherOpen = !_otherOpen);
  }

  void _sendMulti() {
    final answers = [
      for (final o in widget.data.options)
        if (_picked.contains(o)) o,
    ];
    final other = _otherCtl.text.trim();
    if (_otherOpen && other.isNotEmpty) answers.add(other);
    if (answers.isEmpty) return;
    _submit(answers.join(AskStrings.separator));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final d = widget.data;
    final actions = ChatActions.of(context);
    final reply = ReplyScope.of(context);
    final following = reply == null ? null : actions?.answerFor(reply);
    final answer = _sent ?? following;
    final isLatest =
        actions != null &&
        reply != null &&
        identical(reply, actions.latest) &&
        !actions.sending;
    final active = answer == null && isLatest;
    final chosen = answer == null
        ? const <String>{}
        : answer.split(AskStrings.separator).map((e) => e.trim()).toSet();
    final otherAnswer =
        answer != null && chosen.any((c) => !d.options.contains(c));

    return Container(
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: p.codeBackground,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: p.border, width: AppBorder.thin),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AppIcon(AskIcons.question, size: AppIconSize.sm, color: p.accent),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  answer != null ? AskStrings.answered : AskStrings.question,
                  style: t.caption,
                ),
              ),
              if (d.multi && active)
                Text(AskStrings.multiHint, style: t.caption),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(d.question, style: t.body.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: AppSpacing.md),
          for (final o in d.options)
            _OptionRow(
              label: o,
              multi: d.multi,
              selected: answer != null
                  ? chosen.contains(o)
                  : _picked.contains(o),
              enabled: active,
              onTap: () => _tap(o),
            ),
          if (d.other)
            _OptionRow(
              label: AskStrings.other,
              multi: d.multi,
              selected: answer != null ? otherAnswer : _otherOpen,
              enabled: active,
              onTap: _toggleOther,
            ),
          if (active && d.other && _otherOpen)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: TextField(
                controller: _otherCtl,
                maxLength: AskStrings.otherMax,
                maxLines: AskSizes.fieldMaxLines,
                minLines: 1,
                style: t.bodySmall.copyWith(color: p.textPrimary),
                cursorColor: p.accent,
                onChanged: (_) => setState(() {}),
                onSubmitted: d.multi
                    ? null
                    : (v) => v.trim().isEmpty ? null : _submit(v.trim()),
                textInputAction: d.multi
                    ? TextInputAction.newline
                    : TextInputAction.send,
                decoration: InputDecoration(
                  isDense: true,
                  counterText: '',
                  hintText: AskStrings.otherHint,
                  hintStyle: t.bodySmall.copyWith(color: p.textTertiary),
                  contentPadding: const EdgeInsets.all(AppSpacing.md),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    borderSide: BorderSide(color: p.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    borderSide: BorderSide(color: p.accent),
                  ),
                ),
              ),
            ),
          if (active && (d.multi || (d.other && _otherOpen))) ...[
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerRight,
              child: _SendButton(
                enabled: d.multi
                    ? _picked.isNotEmpty ||
                          (_otherOpen && _otherCtl.text.trim().isNotEmpty)
                    : _otherCtl.text.trim().isNotEmpty,
                onTap: d.multi
                    ? _sendMulti
                    : () => _submit(_otherCtl.text.trim()),
              ),
            ),
          ],
          if (answer != null && otherAnswer)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                chosen
                    .where((c) => !d.options.contains(c))
                    .join(AskStrings.separator),
                style: t.bodySmall.copyWith(color: p.accent),
              ),
            ),
        ],
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Opacity(
      opacity: enabled ? 1 : RichSizes.disabledAlpha,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        behavior: HitTestBehavior.opaque,
        child: Container(
          constraints: const BoxConstraints(minHeight: RichSizes.actionMinTap),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: p.accent,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Text(
            AskStrings.send,
            style: context.text.caption.copyWith(color: p.textInverse),
          ),
        ),
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.label,
    required this.multi,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool multi, selected, enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final dim = !enabled && !selected;
    final mark = Container(
      width: AskSizes.mark,
      height: AskSizes.mark,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: multi ? BoxShape.rectangle : BoxShape.circle,
        borderRadius: multi ? BorderRadius.circular(AppRadius.sm) : null,
        border: Border.all(
          color: selected ? p.accent : p.borderStrong,
          width: AppBorder.thin,
        ),
      ),
      child: selected
          ? Container(
              width: AskSizes.markDot,
              height: AskSizes.markDot,
              decoration: BoxDecoration(
                color: p.accent,
                shape: multi ? BoxShape.rectangle : BoxShape.circle,
                borderRadius: multi ? BorderRadius.circular(1) : null,
              ),
            )
          : null,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Opacity(
        opacity: dim ? RichSizes.disabledAlpha : 1,
        child: GestureDetector(
          onTap: enabled ? onTap : null,
          behavior: HitTestBehavior.opaque,
          child: Container(
            constraints: const BoxConstraints(
              minHeight: AskSizes.optionMinHeight,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(
                color: selected ? p.accent : p.border,
                width: AppBorder.thin,
              ),
            ),
            child: Row(
              children: [
                mark,
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    label,
                    style: t.bodySmall.copyWith(color: p.textPrimary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
