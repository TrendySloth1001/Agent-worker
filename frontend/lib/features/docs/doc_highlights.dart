import 'package:flutter/material.dart';

import '../../core/constants/app_sizes.dart';
import '../../core/constants/docs.dart';
import '../../core/haptics.dart';
import '../../core/theme/app_palette.dart';
import '../../core/widgets/app_icon.dart';
import '../../data/doc_models.dart';

// Highlights: text-quote anchors (quote + prefix/suffix) drawn by wrapping
// the quote in `==…==`, the reply markdown's existing highlight syntax.

final _tag = RegExp(r'\[[KWDG]\d{1,3}\](?!\()');
final _fence = RegExp(r'^\s*(```|~~~)');
final _markers = RegExp(r'[*_`]');
final _ws = RegExp(r'\s+');

/// Selected text as plain words: inline widgets (citation chips) leave
/// object-replacement characters behind; whitespace collapses.
String normalizeQuote(String raw) =>
    raw.replaceAll('￼', ' ').replaceAll(_ws, ' ').trim();

/// Markdown reduced to the words a reader sees, for anchoring.
String plainOf(String markdown) => markdown
    .replaceAll(_tag, '')
    .replaceAll(RegExp(r'\{\{[^}]*\}\}'), '')
    .replaceAll(
      RegExp(r'^\s{0,3}(#{1,6}|>|[-*+]|\d+[.)])\s+', multiLine: true),
      '',
    )
    .replaceAll(_markers, '')
    .replaceAll('==', '')
    .replaceAll(_ws, ' ')
    .trim();

/// A highlight for [quote] in [section], with up to
/// [DocConfig.anchorContext] characters of context on each side.
DocHighlight anchorHighlight(DocSection section, String quote, {String? note}) {
  final q = normalizeQuote(quote);
  final plain = plainOf(section.markdown);
  final at = plain.indexOf(q);
  const n = DocConfig.anchorContext;
  return DocHighlight(
    id: '',
    sectionId: section.id,
    quote: q,
    prefix: at < 0 ? '' : plain.substring((at - n).clamp(0, at), at),
    suffix: at < 0
        ? ''
        : plain.substring(
            at + q.length,
            (at + q.length + n).clamp(0, plain.length),
          ),
    color: DocConfig.highlightColor,
    note: note,
  );
}

/// [markdown] with each quote wrapped in `==…==`. Quotes may cross inline
/// marks (`**`, `_`, backticks) and citation tags, not lines or code
/// fences. A quote that cannot be found (or would break formatting) is
/// left out: its highlight is orphaned, the text is untouched.
String applyHighlights(String markdown, Iterable<String> quotes) {
  final list =
      quotes.map(normalizeQuote).where((q) => q.isNotEmpty).toSet().toList()
        ..sort((a, b) => b.length.compareTo(a.length));
  if (list.isEmpty) return markdown;
  final lines = markdown.split('\n');
  for (final quote in list) {
    final words = quote.split(' ');
    final pattern = RegExp(
      words.map(RegExp.escape).join(r'(?:[ \t]|[*_`]|\[[KWDG]\d{1,3}\])+'),
    );
    var fenced = false;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (_fence.hasMatch(line)) {
        fenced = !fenced;
        continue;
      }
      if (fenced) continue;
      final m = pattern.firstMatch(line);
      if (m == null) continue;
      final wrapped = _wrap(m[0]!);
      if (wrapped == null) break;
      lines[i] = line.replaceRange(m.start, m.end, wrapped);
      break;
    }
  }
  return lines.join('\n');
}

/// Marks the text runs of [matched], keeping citation tags outside the
/// marks. Null when inline marks inside are unbalanced.
String? _wrap(String matched) {
  for (final mark in ['**', '__', '`']) {
    if (mark.allMatches(matched).length.isOdd) return null;
  }
  final singles = matched.replaceAll('**', '').replaceAll('__', '');
  if (RegExp('[*_]').allMatches(singles).length.isOdd) return null;
  if (matched.contains('=')) return null;
  final out = StringBuffer();
  var last = 0;
  void text(String run) {
    final core = run.replaceAll(_markers, '');
    final lead = core.length - core.trimLeft().length;
    final trimmed = core.trim();
    if (trimmed.isEmpty) {
      out.write(core);
      return;
    }
    out.write(core.substring(0, lead));
    out.write(_chunks(trimmed).map((c) => '==$c==').join(' '));
    if (core.trimRight().length < core.length) out.write(' ');
  }

  for (final t in _tag.allMatches(matched)) {
    text(matched.substring(last, t.start));
    out.write(t[0]);
    last = t.end;
  }
  text(matched.substring(last));
  return out.toString();
}

/// Splits at spaces so each piece fits the `==…==` syntax.
List<String> _chunks(String s) {
  if (s.length <= DocConfig.markMaxChars) return [s];
  final out = <String>[];
  var rest = s;
  while (rest.length > DocConfig.markMaxChars) {
    var cut = rest.lastIndexOf(' ', DocConfig.markMaxChars);
    if (cut <= 0) cut = DocConfig.markMaxChars;
    out.add(rest.substring(0, cut).trim());
    rest = rest.substring(cut).trim();
  }
  if (rest.isNotEmpty) out.add(rest);
  return out;
}

/// What the reader picked from the selection menu.
enum DocSelectionAction { highlight, note, ask, copyCite }

/// Selectable section text with HIGHLIGHT, NOTE, ASK AI and COPY WITH
/// CITATION added to the system selection menu.
class DocSelectionArea extends StatefulWidget {
  const DocSelectionArea({
    super.key,
    required this.onAction,
    required this.child,
  });

  final void Function(DocSelectionAction action, String quote) onAction;
  final Widget child;

  @override
  State<DocSelectionArea> createState() => _DocSelectionAreaState();
}

class _DocSelectionAreaState extends State<DocSelectionArea> {
  String _selected = '';

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      onSelectionChanged: (content) => _selected = content?.plainText ?? '',
      contextMenuBuilder: (context, state) {
        final quote = normalizeQuote(_selected);
        ContextMenuButtonItem item(DocSelectionAction a, String label) =>
            ContextMenuButtonItem(
              label: label,
              onPressed: () {
                Haptics.tap();
                state.hideToolbar();
                state.clearSelection();
                widget.onAction(a, quote);
              },
            );
        return AdaptiveTextSelectionToolbar.buttonItems(
          anchors: state.contextMenuAnchors,
          buttonItems: [
            if (quote.isNotEmpty) ...[
              item(DocSelectionAction.highlight, DocStrings.highlight),
              item(DocSelectionAction.note, DocStrings.note),
              item(DocSelectionAction.ask, DocStrings.askAi),
              item(DocSelectionAction.copyCite, DocStrings.copyCite),
            ],
            ...state.contextMenuButtonItems,
          ],
        );
      },
      child: widget.child,
    );
  }
}

/// Notes and highlights of one section, as margin markers under it: a
/// numbered dot, the quote, the note. Tap to remove.
class DocMarginNotes extends StatelessWidget {
  const DocMarginNotes({
    super.key,
    required this.highlights,
    required this.onRemove,
  });

  final List<DocHighlight> highlights;
  final ValueChanged<DocHighlight> onRemove;

  @override
  Widget build(BuildContext context) {
    final notes = [
      for (final h in highlights)
        if (h.hasNote) h,
    ];
    if (notes.isEmpty) return const SizedBox.shrink();
    final p = context.palette;
    final t = context.text;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, h) in notes.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: DocSizes.noteMarker,
                    height: DocSizes.noteMarker,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: p.accent,
                        width: AppBorder.thin,
                      ),
                    ),
                    child: Text(
                      '${i + 1}',
                      style: t.caption.copyWith(color: p.accent, height: 1),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '“${h.quote}”',
                          maxLines: DocSizes.notePreviewLines,
                          overflow: TextOverflow.ellipsis,
                          style: t.bodySmall.copyWith(
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          h.note!,
                          style: t.bodySmall.copyWith(color: p.textPrimary),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      Haptics.tap();
                      onRemove(h);
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xs),
                      child: AppIcon(
                        DocIcons.close,
                        size: AppIconSize.sm,
                        color: p.textTertiary,
                        semanticLabel: DocStrings.removeHighlight,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
