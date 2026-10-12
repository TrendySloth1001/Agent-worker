import 'package:flutter/material.dart';

import '../../../../core/app_scope.dart';
import '../../../../core/haptics.dart';
import '../../../../data/assist_api.dart';
import '../../../../data/chat_api.dart';
import '../../../../core/constants/app_icons.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/rich_cards.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/widgets/app_icon.dart';
import 'rich_frame.dart';
import 'rich_parsers.dart';
import '../../../../core/widgets/m3_kit_extras.dart';

/// ```email block: header rows, body, inline editing, AI rewrite and
/// copy / open-in-mail actions. Edits live in this card's state.
class EmailCard extends StatefulWidget {
  const EmailCard({super.key, required this.draft});

  final EmailDraft draft;

  @override
  State<EmailCard> createState() => _EmailCardState();
}

class _EmailCardState extends State<EmailCard> {
  late EmailDraft _draft = widget.draft;
  EmailDraft? _undo;
  bool _editing = false;
  bool _busy = false;
  bool _touched = false;

  final _to = TextEditingController();
  final _cc = TextEditingController();
  final _subject = TextEditingController();
  final _bodyCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fill(_draft);
  }

  @override
  void didUpdateWidget(EmailCard old) {
    super.didUpdateWidget(old);
    // Streaming re-parses the block; only follow it until the user edits.
    if (!_touched && widget.draft.full != old.draft.full) {
      _draft = widget.draft;
      _fill(_draft);
    }
  }

  @override
  void dispose() {
    _to.dispose();
    _cc.dispose();
    _subject.dispose();
    _bodyCtl.dispose();
    super.dispose();
  }

  void _fill(EmailDraft d) {
    _to.text = d.to;
    _cc.text = d.cc;
    _subject.text = d.subject;
    _bodyCtl.text = d.body;
  }

  void _onFieldChanged() {
    setState(() {
      _touched = true;
      _draft = EmailDraft(
        to: _to.text.trim(),
        cc: _cc.text.trim(),
        bcc: _draft.bcc,
        subject: _subject.text.trim(),
        body: _bodyCtl.text,
      );
    });
  }

  void _replace(EmailDraft next) {
    _undo = _draft;
    _draft = next;
    _touched = true;
    _fill(next);
  }

  Future<bool> _toggleEdit() async {
    setState(() => _editing = !_editing);
    return true;
  }

  Future<bool> _undoLast() async {
    final prev = _undo;
    if (prev == null) return false;
    setState(() {
      _draft = prev;
      _undo = null;
      _fill(prev);
    });
    return true;
  }

  String? get _missingSignature {
    final sig = AppScope.of(context).settings.signature.trim();
    if (sig.isEmpty) return null;
    return _draft.body.trimRight().endsWith(sig) ? null : sig;
  }

  Future<bool> _addSignature() async {
    final sig = _missingSignature;
    if (sig == null) return false;
    final d = _draft;
    setState(() {
      _replace(
        EmailDraft(
          to: d.to,
          cc: d.cc,
          bcc: d.bcc,
          subject: d.subject,
          body: d.body.trimRight().isEmpty
              ? sig
              : '${d.body.trimRight()}\n\n$sig',
        ),
      );
    });
    return true;
  }

  Future<void> _rewrite(String action, {String? instruction}) async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    final profile = AppScope.of(context).settings.profileJson();
    setState(() => _busy = true);
    try {
      final next = await AssistApi.rewriteEmail(
        draft: _draft,
        action: action,
        instruction: instruction,
        profile: profile,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _replace(next);
      });
      Haptics.received();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      Haptics.error();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e is ApiException ? e.message : RichStrings.rewriteFailed,
          ),
        ),
      );
    }
  }

  Future<void> _custom() async {
    if (_busy) return;
    final text = await showM3Sheet<String>(
      context,
      builder: (_) => const _InstructionSheet(),
    );
    if (text == null || text.trim().isEmpty || !mounted) return;
    await _rewrite('custom', instruction: text.trim());
  }

  Uri get _mailto {
    final draft = _draft;
    String enc(String s) => Uri.encodeComponent(s);
    final to = draft.to
        .split(RegExp(r'[,;]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .map(enc)
        .join(',');
    final params = <String>[
      if (draft.cc.isNotEmpty)
        '${RichLinks.mailCc}=${enc(draft.cc.replaceAll(';', ','))}',
      if (draft.bcc.isNotEmpty)
        '${RichLinks.mailBcc}=${enc(draft.bcc.replaceAll(';', ','))}',
      if (draft.subject.isNotEmpty)
        '${RichLinks.mailSubject}=${enc(draft.subject)}',
      if (draft.body.isNotEmpty) '${RichLinks.mailBody}=${enc(draft.body)}',
    ];
    return Uri.parse(
      '${RichLinks.mailto}:$to${params.isEmpty ? '' : '?${params.join('&')}'}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final draft = _draft;
    final sig = _missingSignature;
    return RichCard(
      title: RichStrings.emailDraft,
      leading: AppIcon(
        RichIcons.mail,
        size: AppIconSize.sm,
        color: p.textTertiary,
      ),
      actions: [
        RichAction.copy(text: draft.full),
        if (draft.body.isNotEmpty)
          RichAction.copy(text: draft.body, label: RichStrings.copyBody),
        RichAction.open(
          icon: RichIcons.send,
          brandIcon: RichIcons.gmail,
          label: RichStrings.openInMail,
          uri: _mailto,
        ),
        RichAction(
          key: ValueKey(_editing),
          icon: _editing ? RichIcons.done : RichIcons.edit,
          label: _editing ? RichStrings.done : RichStrings.edit,
          enabled: !_busy,
          onTap: _toggleEdit,
        ),
        if (_undo != null)
          RichAction(
            icon: RichIcons.undo,
            label: RichStrings.undo,
            enabled: !_busy,
            onTap: _undoLast,
          ),
        if (sig != null)
          RichAction(
            icon: RichIcons.signature,
            label: RichStrings.addSignature,
            enabled: !_busy,
            onTap: _addSignature,
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: RichSizes.progressHeight,
            child: _busy
                ? LinearProgressIndicator(
                    minHeight: RichSizes.progressHeight,
                    color: p.accent,
                    backgroundColor: p.border,
                  )
                : null,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _editing ? _editFields(context) : _viewRows(context),
            ),
          ),
          _rewriteRow(context),
        ],
      ),
    );
  }

  List<Widget> _viewRows(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final draft = _draft;
    return [
      if (draft.to.isNotEmpty) _row(context, RichStrings.to, draft.to),
      if (draft.cc.isNotEmpty) _row(context, RichStrings.cc, draft.cc),
      if (draft.bcc.isNotEmpty) _row(context, RichStrings.bcc, draft.bcc),
      _row(
        context,
        RichStrings.subject,
        draft.subject.isEmpty ? RichStrings.noSubject : draft.subject,
      ),
      if (draft.body.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.md),
        Divider(
          height: AppBorder.thin,
          thickness: AppBorder.thin,
          color: p.border,
        ),
        const SizedBox(height: AppSpacing.md),
        SelectableText(
          draft.body,
          style: t.bodySmall.copyWith(color: p.textPrimary),
        ),
        const SizedBox(height: AppSpacing.md),
        _stats(context),
      ],
    ];
  }

  List<Widget> _editFields(BuildContext context) {
    return [
      _field(context, RichStrings.to, _to, TextInputType.emailAddress),
      _field(context, RichStrings.cc, _cc, TextInputType.emailAddress),
      _field(context, RichStrings.subject, _subject, TextInputType.text),
      const SizedBox(height: AppSpacing.xs),
      _field(context, null, _bodyCtl, TextInputType.multiline, multiline: true),
      const SizedBox(height: AppSpacing.xs),
      _stats(context),
    ];
  }

  Widget _stats(BuildContext context) {
    final words = RegExp(r'\S+').allMatches(_draft.body).length;
    final minutes = words == 0
        ? 0
        : (words / RichStrings.wordsPerMinute).ceil().clamp(1, 999);
    return Text(RichStrings.stats(words, minutes), style: context.text.caption);
  }

  Widget _field(
    BuildContext context,
    String? label,
    TextEditingController controller,
    TextInputType type, {
    bool multiline = false,
  }) {
    final p = context.palette;
    final t = context.text;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      borderSide: BorderSide(color: p.border, width: AppBorder.thin),
    );
    final field = TextField(
      controller: controller,
      enabled: !_busy,
      keyboardType: type,
      minLines: multiline ? 4 : 1,
      maxLines: multiline ? RichSizes.fieldMaxLines : 1,
      textCapitalization: multiline
          ? TextCapitalization.sentences
          : TextCapitalization.none,
      onChanged: (_) => _onFieldChanged(),
      cursorColor: p.accent,
      style: t.bodySmall.copyWith(color: p.textPrimary),
      decoration: InputDecoration(
        isDense: true,
        filled: false,
        hintText: multiline ? RichStrings.bodyHint : null,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.sm,
        ),
        border: border,
        enabledBorder: border,
        disabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: BorderSide(color: p.textPrimary, width: AppBorder.thin),
        ),
      ),
    );
    if (label == null) return field;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: RichSizes.fieldLabelWidth,
            child: Text(label, style: t.caption),
          ),
          Expanded(child: field),
        ],
      ),
    );
  }

  Widget _rewriteRow(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    Widget chip(AppIconData icon, String label, Future<void> Function() run) =>
        RichAction(
          icon: icon,
          label: label,
          enabled: !_busy,
          onTap: () async {
            await run();
            return true;
          },
        );
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: p.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              _busy ? RichStrings.rewriting : RichStrings.aiRewrite,
              style: t.caption.copyWith(
                color: _busy ? p.accent : p.textTertiary,
              ),
            ),
          ),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.xs,
            children: [
              chip(
                RichIcons.shorter,
                RichStrings.shorter,
                () => _rewrite('shorter'),
              ),
              chip(
                RichIcons.longer,
                RichStrings.longer,
                () => _rewrite('longer'),
              ),
              chip(
                RichIcons.formal,
                RichStrings.formal,
                () => _rewrite('formal'),
              ),
              chip(
                RichIcons.friendly,
                RichStrings.friendly,
                () => _rewrite('friendly'),
              ),
              chip(
                RichIcons.fix,
                RichStrings.fixGrammar,
                () => _rewrite('fix'),
              ),
              chip(RichIcons.custom, RichStrings.custom, _custom),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    final t = context.text;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: t.caption),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: t.caption.copyWith(color: context.palette.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _InstructionSheet extends StatefulWidget {
  const _InstructionSheet();

  @override
  State<_InstructionSheet> createState() => _InstructionSheetState();
}

class _InstructionSheetState extends State<_InstructionSheet> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _submit() {
    if (_input.text.trim().isEmpty) return;
    Navigator.pop(context, _input.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.screenPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(RichStrings.customTitle, style: t.caption),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _input,
                autofocus: true,
                style: t.body,
                maxLength: RichStrings.customMax,
                minLines: 2,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
                cursorColor: p.accent,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  hintText: RichStrings.customHint,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerRight,
                child: RichAction(
                  icon: RichIcons.custom,
                  label: RichStrings.customGo,
                  enabled: _input.text.trim().isNotEmpty,
                  onTap: () async {
                    _submit();
                    return true;
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
