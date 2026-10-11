import 'dart:ui' show Color;

import 'package:flutter/services.dart' show rootBundle;
import 'package:markdown/markdown.dart' as md;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/constants/app_strings.dart';
import '../../../core/constants/share_export.dart';
import '../../../core/theme/app_palette.dart';
import '../../../data/chat_event.dart';

/// The PDF faces: Space Grotesk for text, Space Mono for labels and code.
class PdfFonts {
  PdfFonts(this.regular, this.bold, this.mono, this.monoBold);

  final pw.Font regular, bold, mono, monoBold;

  static Future<PdfFonts> load() async {
    Future<pw.Font> f(String path) async =>
        pw.Font.ttf(await rootBundle.load(path));
    final all = await Future.wait([
      f(PdfSizes.fontRegular),
      f(PdfSizes.fontBold),
      f(PdfSizes.fontMono),
      f(PdfSizes.fontMonoBold),
    ]);
    return PdfFonts(all[0], all[1], all[2], all[3]);
  }
}

PdfColor pdfColor(Color c) => PdfColor.fromInt(c.toARGB32());

/// Turns markdown into PDF widgets: headings, paragraphs, lists, tables,
/// quotes and code, plus a sources list. Shared by chat and document export.
/// The page is always light, so colors come from the light palette.
class MarkdownPdfWriter {
  MarkdownPdfWriter(this.f);

  final PdfFonts f;
  static const _p = AppPalette.light;

  late final primary = pdfColor(_p.textPrimary);
  late final secondary = pdfColor(_p.textSecondary);
  late final tertiary = pdfColor(_p.textTertiary);
  late final border = pdfColor(_p.border);
  late final codeFill = pdfColor(_p.codeBackground);
  late final accent = pdfColor(_p.accent);

  late final body = pw.TextStyle(
    fontNormal: f.regular,
    fontBold: f.bold,
    fontItalic: f.regular,
    fontBoldItalic: f.bold,
    fontSize: PdfSizes.body,
    lineSpacing: PdfSizes.lineSpacing,
    color: primary,
  );
  late final caption = pw.TextStyle(
    fontNormal: f.mono,
    fontBold: f.monoBold,
    fontItalic: f.mono,
    fontBoldItalic: f.monoBold,
    fontSize: PdfSizes.caption,
    letterSpacing: PdfSizes.letterSpacing,
    color: tertiary,
  );
  late final code = pw.TextStyle(
    fontNormal: f.mono,
    fontBold: f.monoBold,
    fontItalic: f.mono,
    fontBoldItalic: f.monoBold,
    fontSize: PdfSizes.code,
    lineSpacing: PdfSizes.lineSpacing,
    color: primary,
  );

  static const bold = pw.FontWeight.bold;

  /// [style] in Space Mono, keeping size, color and weight.
  pw.TextStyle mono(pw.TextStyle style) => style.copyWith(
    fontNormal: f.mono,
    fontBold: f.monoBold,
    fontItalic: f.mono,
    fontBoldItalic: f.monoBold,
  );

  /// Page theme with the document fonts (text falls back to Space Mono).
  pw.ThemeData get theme => pw.ThemeData.withFont(
    base: f.regular,
    bold: f.bold,
    italic: f.regular,
    boldItalic: f.bold,
    fontFallback: [f.mono],
  );

  /// A4 with the export margins.
  static final pageFormat = PdfPageFormat.a4.copyWith(
    marginLeft: PdfSizes.margin,
    marginRight: PdfSizes.margin,
    marginTop: PdfSizes.margin,
    marginBottom: PdfSizes.margin,
  );

  /// "SPARKY ........ PAGE 2 / 5" under every page.
  pw.Widget footer(pw.Context context) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: PdfSizes.messageGap),
    child: pw.Row(
      children: [
        pw.Text(AppStrings.appName.toUpperCase(), style: caption),
        pw.Spacer(),
        pw.Text(
          ShareStrings.page(context.pageNumber, context.pagesCount),
          style: caption,
        ),
      ],
    ),
  );

  List<pw.Widget> sources(List<Citation> citations) => [
    pw.SizedBox(height: PdfSizes.blockGap),
    pw.Text(ShareStrings.sources.toUpperCase(), style: caption),
    pw.SizedBox(height: PdfSizes.blockGap / 2),
    for (final c in citations)
      pw.RichText(
        overflow: pw.TextOverflow.span,
        text: pw.TextSpan(
          style: caption.copyWith(color: secondary, letterSpacing: 0),
          children: [
            pw.TextSpan(text: '[${c.id}] '),
            pw.TextSpan(
              text: c.title.isEmpty ? c.site : c.title,
              style: body.copyWith(fontSize: PdfSizes.caption, color: primary),
            ),
            if (c.url.isEmpty)
              pw.TextSpan(text: ' (${ShareStrings.knowledgeBase})')
            else
              pw.TextSpan(
                text: '  ${c.url}',
                annotation: pw.AnnotationUrl(c.url),
              ),
          ],
        ),
      ),
  ];

  pw.Widget _column(List<pw.Widget> children) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: children,
  );

  /// Block widgets for a markdown body.
  List<pw.Widget> markdown(String source) {
    final nodes = md.Document(
      extensionSet: md.ExtensionSet.gitHubFlavored,
      encodeHtml: false,
    ).parse(_prepare(source));
    return _blocks(nodes);
  }

  List<pw.Widget> _blocks(List<md.Node> nodes, {int depth = 0}) {
    final out = <pw.Widget>[];
    for (final n in nodes) {
      final w = n is md.Element && n.tag == 'pre'
          ? _code(n)
          : [?_block(n, depth)];
      if (w.isEmpty) continue;
      if (out.isNotEmpty) out.add(pw.SizedBox(height: PdfSizes.blockGap));
      out.addAll(w);
    }
    return out;
  }

  pw.Widget? _block(md.Node n, int depth) {
    if (n is md.Text) {
      final t = n.text.trim();
      return t.isEmpty ? null : _rich([pw.TextSpan(text: t)], body);
    }
    if (n is! md.Element) return null;
    final children = n.children ?? const <md.Node>[];
    switch (n.tag) {
      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        final size = switch (n.tag) {
          'h1' => PdfSizes.h1,
          'h2' => PdfSizes.h2,
          _ => PdfSizes.h3,
        };
        return pw.Padding(
          padding: const pw.EdgeInsets.only(top: PdfSizes.blockGap),
          child: _rich(
            _inline(children, body.copyWith(fontWeight: bold, fontSize: size)),
            body.copyWith(fontWeight: bold, fontSize: size),
          ),
        );
      case 'p':
        return _rich(_inline(children, body), body);
      case 'blockquote':
        return pw.Container(
          padding: const pw.EdgeInsets.only(left: PdfSizes.boxPadding),
          decoration: pw.BoxDecoration(
            border: pw.Border(
              left: pw.BorderSide(color: border, width: PdfSizes.quoteBar),
            ),
          ),
          child: _column(_blocks(children, depth: depth)),
        );
      case 'ul' || 'ol':
        return _list(n, depth);
      case 'hr':
        return pw.Divider(color: border, thickness: PdfSizes.border);
      case 'table':
        return _table(n);
      default:
        return _rich(_inline([n], body), body);
    }
  }

  pw.Widget _rich(List<pw.InlineSpan> spans, pw.TextStyle style) => pw.RichText(
    overflow: pw.TextOverflow.span,
    text: pw.TextSpan(style: style, children: spans),
  );

  /// Fenced code (widgets included) as source in a mono box, with its
  /// language as a caption. Kept flat so long code breaks across pages.
  List<pw.Widget> _code(md.Element pre) {
    final codeEl = pre.children?.whereType<md.Element>().firstOrNull;
    final lang = (codeEl?.attributes['class'] ?? '').replaceFirst(
      'language-',
      '',
    );
    final text = pre.textContent.replaceFirst(RegExp(r'\n$'), '');
    return [
      if (lang.isNotEmpty) ...[
        pw.Text(lang.toUpperCase(), style: caption),
        pw.SizedBox(height: PdfSizes.blockGap / 2),
      ],
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(PdfSizes.boxPadding),
        decoration: pw.BoxDecoration(
          color: codeFill,
          border: pw.Border.all(color: border, width: PdfSizes.border),
        ),
        child: pw.Text(text, style: code, overflow: pw.TextOverflow.span),
      ),
    ];
  }

  pw.Widget _list(md.Element list, int depth) {
    final ordered = list.tag == 'ol';
    var number = int.tryParse(list.attributes['start'] ?? '') ?? 1;
    final items = <pw.Widget>[];
    for (final li in (list.children ?? const []).whereType<md.Element>()) {
      final marker = ordered ? '${number++}.' : '•';
      final kids = li.children ?? const <md.Node>[];
      // Loose items wrap text in <p>; tight ones hold inline nodes.
      final inline = kids.where((k) => !_isBlock(k)).toList();
      final blocks = kids.where(_isBlock).toList();
      items.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: PdfSizes.blockGap / 2),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(
                width: PdfSizes.indent,
                child: pw.Text(marker, style: body.copyWith(color: secondary)),
              ),
              pw.Expanded(
                child: _column([
                  if (inline.isNotEmpty) _rich(_inline(inline, body), body),
                  ..._blocks(blocks, depth: depth + 1),
                ]),
              ),
            ],
          ),
        ),
      );
    }
    return _column(items);
  }

  static bool _isBlock(md.Node n) =>
      n is md.Element &&
      const {
        'p',
        'ul',
        'ol',
        'pre',
        'blockquote',
        'table',
        'hr',
        'h1',
        'h2',
        'h3',
        'h4',
        'h5',
        'h6',
      }.contains(n.tag);

  pw.Widget _table(md.Element table) {
    final rows = <pw.TableRow>[];
    void addRows(md.Element section, {required bool header}) {
      for (final tr in (section.children ?? const []).whereType<md.Element>()) {
        rows.add(
          pw.TableRow(
            decoration: header ? pw.BoxDecoration(color: codeFill) : null,
            children: [
              for (final cell
                  in (tr.children ?? const []).whereType<md.Element>())
                pw.Padding(
                  padding: const pw.EdgeInsets.all(PdfSizes.cellPadding),
                  child: pw.RichText(
                    text: pw.TextSpan(
                      children: _inline(
                        cell.children ?? const [],
                        body.copyWith(
                          fontSize: PdfSizes.table,
                          fontWeight: header ? bold : null,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      }
    }

    for (final section
        in (table.children ?? const []).whereType<md.Element>()) {
      addRows(section, header: section.tag == 'thead');
    }
    return pw.Table(
      border: pw.TableBorder.all(color: border, width: PdfSizes.border),
      children: rows,
    );
  }

  List<pw.InlineSpan> _inline(List<md.Node> nodes, pw.TextStyle style) {
    final out = <pw.InlineSpan>[];
    for (final n in nodes) {
      if (n is md.Text) {
        out.add(pw.TextSpan(text: n.text, style: style));
        continue;
      }
      if (n is! md.Element) continue;
      final kids = n.children ?? const <md.Node>[];
      switch (n.tag) {
        case 'strong':
          out.addAll(_inline(kids, style.copyWith(fontWeight: bold)));
        case 'em':
          out.addAll(_inline(kids, style.copyWith(color: secondary)));
        case 'del':
          out.addAll(
            _inline(
              kids,
              style.copyWith(decoration: pw.TextDecoration.lineThrough),
            ),
          );
        case 'code':
          out.add(
            pw.TextSpan(
              text: n.textContent,
              style: mono(style).copyWith(
                fontSize:
                    (style.fontSize ?? PdfSizes.body) *
                    PdfSizes.inlineCodeScale,
                background: pw.BoxDecoration(color: codeFill),
              ),
            ),
          );
        case 'a':
          final href = n.attributes['href'] ?? '';
          out.add(
            pw.TextSpan(
              children: _inline(
                kids,
                style.copyWith(
                  decoration: pw.TextDecoration.underline,
                  decorationColor: accent,
                ),
              ),
              annotation: href.isEmpty ? null : pw.AnnotationUrl(href),
            ),
          );
        case 'br':
          out.add(const pw.TextSpan(text: '\n'));
        case 'img':
          out.add(
            pw.TextSpan(
              text: '[${n.attributes['alt'] ?? ''}]',
              style: style.copyWith(color: secondary),
            ),
          );
        case 'input':
          final done = n.attributes['checked'] != null;
          out.add(
            pw.TextSpan(text: done ? '[x] ' : '[ ] ', style: mono(style)),
          );
        default:
          out.addAll(_inline(kids, style));
      }
    }
    return out;
  }

  /// App-only markers out: icons dropped, images and callouts as text.
  static String _prepare(String s) => s
      .replaceAll(_iconRe, '')
      .replaceAllMapped(_imageRe, (m) => '*[${m[2] ?? m[1]}]*')
      .replaceAllMapped(_calloutRe, (m) => '${m[1]}**${m[2]!.toUpperCase()}** ')
      .replaceAll(_markRe, '');

  static final _iconRe = RegExp(r'\{\{icon:[^}\n]*\}\} ?');
  static final _imageRe = RegExp(
    r'\{\{image:([^}|]{1,120})(?:\|([^}]{1,160}))?\}\}',
  );
  static final _calloutRe = RegExp(
    r'^(\s{0,3}>\s?)\[!([A-Za-z]+)\]\s*',
    multiLine: true,
  );
  static final _markRe = RegExp('==');
}
