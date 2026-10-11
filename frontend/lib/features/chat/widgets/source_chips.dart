import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/app_scope.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_palette.dart';
import '../../../data/chat_api.dart';
import '../../../data/chat_event.dart';
import '../../../data/knowledge_api.dart';
import 'markdown/citation_chip.dart';
import '../../../core/widgets/browser_picker.dart';
import 'open_url.dart';
import '../../../core/constants/app_icons.dart';
import '../../../core/widgets/app_icon.dart';

/// Every source as a chip with its site logo. Cited ones get a red outline.
class SourceChips extends StatelessWidget {
  const SourceChips({super.key, required this.citations, required this.used});

  final List<Citation> citations;
  final Set<String> used;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppSizes.sourceChipHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: citations.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xs),
        itemBuilder: (context, i) => _SourceChip(
          citation: citations[i],
          used: used.contains(citations[i].id),
        ),
      ),
    );
  }
}

class _SourceChip extends StatelessWidget {
  const _SourceChip({required this.citation, required this.used});

  final Citation citation;
  final bool used;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    return GestureDetector(
      onTap: () => showSourceCard(context, citation, used: used),
      child: Container(
        constraints: const BoxConstraints(
          maxWidth: AppSizes.sourceChipMaxWidth,
        ),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: used ? p.accent : p.border,
            width: AppBorder.thin,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SiteFavicon(citation: citation, size: AppSizes.favicon),
            const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
            Flexible(
              child: Text(
                citeShortName(citation),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.caption.copyWith(color: p.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Expanded card for a source: logo, title, link and snippet, a VISIT
/// button that asks which browser to use (unless a default is saved), and
/// copy / open with / save actions.
Future<void> showSourceCard(
  BuildContext context,
  Citation citation, {
  bool used = false,
}) {
  Haptics.tap();
  final p = context.palette;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: p.surface,
    shape: RoundedRectangleBorder(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppRadius.lg),
      ),
      side: BorderSide(color: p.border),
    ),
    builder: (_) => _SourceCard(citation: citation, used: used, host: context),
  );
}

class _SourceCard extends StatefulWidget {
  const _SourceCard({
    required this.citation,
    required this.used,
    required this.host,
  });

  final Citation citation;
  final bool used;

  /// Context under the sheet, used for notices and opening links after the
  /// sheet closes.
  final BuildContext host;

  @override
  State<_SourceCard> createState() => _SourceCardState();
}

class _SourceCardState extends State<_SourceCard> {
  Citation get _c => widget.citation;

  bool get _isNote => _c.url.startsWith('note:') || _c.url.isEmpty;
  bool get _isFile => _c.url.startsWith('file:');
  bool get _isWeb => !_c.isKb && !_isFile && !_isNote;

  void _toast(String text) => ScaffoldMessenger.of(
    widget.host,
  ).showSnackBar(SnackBar(content: Text(text)));

  void _visit() {
    Haptics.tap();
    Navigator.pop(context);
    visitUrl(widget.host, _c.url);
  }

  void _openWith() {
    Navigator.pop(context);
    openUrlWith(widget.host, _c.url);
  }

  Future<void> _changeDefault() async {
    await showBrowserPicker(context, forSettings: true);
    if (mounted) setState(() {});
  }

  Future<void> _copy() async {
    Navigator.pop(context);
    await Clipboard.setData(ClipboardData(text: _c.url));
    _toast(AppStrings.copyLink);
  }

  Future<void> _save() async {
    final baseUrl = AppScope.of(context).baseUrl;
    Navigator.pop(context);
    try {
      await KnowledgeApi(baseUrl).add(_c.url, type: 'web', limit: 1);
      Haptics.received();
      _toast(AppStrings.savedToKnowledge);
    } on ApiException catch (e) {
      // A duplicate means it is already in the knowledge base.
      if (e.status == 409) {
        _toast(AppStrings.savedToKnowledge);
      } else {
        Haptics.error();
        _toast(e.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    final settings = AppScope.of(context).settings;
    final browser = settings.browserPackage.isEmpty
        ? ''
        : (settings.browserLabel.isEmpty
              ? settings.browserPackage
              : settings.browserLabel);
    final kind = _c.isKb
        ? SourceStrings.fromKnowledge
        : _isFile
        ? SourceStrings.document
        : citeDomain(_c).toUpperCase();
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenPadding,
            AppSpacing.lg,
            AppSpacing.screenPadding,
            AppSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  SiteFavicon(citation: _c, size: AppSizes.sourceCardFavicon),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      kind,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.caption.copyWith(color: p.textSecondary),
                    ),
                  ),
                  Text(
                    '[${_c.id}]',
                    style: t.caption.copyWith(
                      color: widget.used ? p.accent : p.textTertiary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                _c.title.isEmpty ? _c.url : _c.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: t.title,
              ),
              if (_isWeb) ...[
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  _c.url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.caption,
                ),
              ],
              if (widget.used) ...[
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    AppIcon(
                      AppIcons.check,
                      size: AppIconSize.xs,
                      color: p.accent,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      SourceStrings.cited,
                      style: t.caption.copyWith(color: p.accent),
                    ),
                  ],
                ),
              ],
              if (_c.snippet.trim().isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: p.background,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: p.border, width: AppBorder.thin),
                  ),
                  child: Text(
                    _c.snippet.trim(),
                    maxLines: AppSizes.sourceCardSnippetLines,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodySmall,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              if (_isNote)
                Text(SourceStrings.noLink, style: t.bodySmall)
              else ...[
                _VisitButton(onTap: _visit),
                if (_isWeb) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _BrowserLine(browser: browser, onChange: _changeDefault),
                ],
              ],
              const SizedBox(height: AppSpacing.md),
              Divider(color: p.border, height: AppBorder.thin),
              if (_isWeb)
                _ActionRow(
                  icon: AppIcons.browser,
                  label: BrowserStrings.openWith,
                  onTap: _openWith,
                ),
              if (!_isNote)
                _ActionRow(
                  icon: AppIcons.link,
                  label: AppStrings.copyLinkAction,
                  onTap: _copy,
                ),
              if (_isWeb)
                _ActionRow(
                  icon: AppIcons.knowledge,
                  label: AppStrings.saveToKnowledge,
                  onTap: _save,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-width accent VISIT button.
class _VisitButton extends StatelessWidget {
  const _VisitButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      label: SourceStrings.visit,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: AppSizes.buttonHeight,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: p.accent,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(
                AppIcons.visit,
                size: AppIconSize.md,
                color: p.textInverse,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                SourceStrings.visit,
                style: context.text.button.copyWith(color: p.textInverse),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "OPENS IN CHROME · CHANGE" or "ASKS WHICH BROWSER EACH TIME · SET DEFAULT".
class _BrowserLine extends StatelessWidget {
  const _BrowserLine({required this.browser, required this.onChange});

  final String browser;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.text;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AppIcon(AppIcons.browser, size: AppIconSize.xs, color: p.textTertiary),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            browser.isEmpty
                ? SourceStrings.asksBrowser
                : '${SourceStrings.opensIn} ${browser.toUpperCase()}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.caption,
          ),
        ),
        Text(' · ', style: t.caption),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            Haptics.tap();
            onChange();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Text(
              browser.isEmpty ? SourceStrings.setDefault : SourceStrings.change,
              style: t.caption.copyWith(color: p.textPrimary),
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final AppIconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Haptics.tap();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenPadding,
        ),
        child: SizedBox(
          height: AppSizes.rowHeight,
          child: Row(
            children: [
              AppIcon(
                icon,
                size: AppIconSize.md,
                color: context.palette.textSecondary,
              ),
              const SizedBox(width: AppSpacing.md),
              Text(label, style: context.text.label),
            ],
          ),
        ),
      ),
    );
  }
}
