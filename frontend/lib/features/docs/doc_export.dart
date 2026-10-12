import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/constants/app_strings.dart';
import '../../core/constants/docs.dart';
import '../../core/constants/share_export.dart';
import '../../core/haptics.dart';
import '../../data/chat_event.dart';
import '../../data/doc_models.dart';
import '../../data/docs_api.dart';
import '../chat/share/chat_export.dart';
import '../chat/share/markdown_pdf_writer.dart';
import '../chat/share/share_sheet.dart';
import '../chat/widgets/markdown/citation_chip.dart';
import 'doc_section_menu.dart';

/// Section markdown without a leading `## Heading` the server may have
/// inserted (the reader and exports draw the heading themselves).
String sectionBody(DocSection s) {
  final lines = s.markdown.trimLeft().split('\n');
  if (lines.isEmpty) return '';
  final first = lines.first.trim();
  final m = RegExp(r'^#{1,3}\s+(.*)$').firstMatch(first);
  if (m != null &&
      m[1]!.trim().toLowerCase() == s.heading.trim().toLowerCase()) {
    return lines.skip(1).join('\n').trimLeft();
  }
  return s.markdown;
}

/// "14 MIN READ · 3,420 WORDS · 18 SOURCES · DONE".
String _metaLine(Doc doc) => DocStrings.meta(
  words: doc.wordCount,
  sources: doc.references.length,
  status: doc.status,
);

/// Source number (1-based, first-use order) by citation id.
Map<String, int> citeNumbers(Doc doc) => {
  for (final (i, c) in doc.references.indexed) c.id: i + 1,
};

final _citeRun = RegExp(
  r'[ \t]*\[[KWDGC]\d{1,3}\](?!\()(?:[ \t,]*\[[KWDGC]\d{1,3}\](?!\())*',
);
final _citeTag = RegExp(r'\[([KWDGC]\d{1,3})\]');

/// Citation tags as source numbers. With [links] they are superscript
/// links to the numbered references list (`<sup>[1](#ref-1)</sup>`),
/// otherwise plain `[1,2]`. Adjacent tags share one mark, unknown ids go.
String numberCitations(
  String text,
  Map<String, int> numbers, {
  required bool links,
}) => text.replaceAllMapped(_citeRun, (m) {
  final nums = {
    for (final t in _citeTag.allMatches(m[0]!))
      if (numbers[t[1]] != null) numbers[t[1]]!,
  }.toList()..sort();
  if (nums.isEmpty) return '';
  return links
      ? '<sup>${nums.map((n) => '[$n](#ref-$n)').join(',')}</sup>'
      : ' [${nums.join(',')}]';
});

/// "github · Title url": the site name leads each reference.
String _referenceLine(Citation c, {bool links = true}) {
  final title = c.title.isEmpty ? c.site : c.title;
  final name = citeShortName(c);
  if (c.isKb || c.url.isEmpty) {
    return '$name · $title. ${DocStrings.knowledgeBase}.';
  }
  return links ? '**$name** · $title <${c.url}>' : '$name · $title ${c.url}';
}

/// The whole document as portable Markdown: title, abstract, sections
/// (citation tags become links), References and Glossary.
String docMarkdown(Doc doc, {DateTime? now}) {
  final date = now ?? DateTime.now();
  final title = doc.title.trim().isEmpty ? DocStrings.untitled : doc.title;
  final numbers = citeNumbers(doc);
  String cite(String md) => numberCitations(md, numbers, links: true);
  final b = StringBuffer()
    ..writeln('# $title')
    ..writeln();
  if (doc.subtitle.trim().isNotEmpty) {
    b
      ..writeln('*${doc.subtitle.trim()}*')
      ..writeln();
  }
  b
    ..writeln(_metaLine(doc))
    ..writeln()
    ..writeln(ShareStrings.exportedLine(date, AppStrings.appName))
    ..writeln();
  if (doc.summary.trim().isNotEmpty) {
    b
      ..writeln('## ${DocStrings.abstractTitle}')
      ..writeln()
      ..writeln(cite(doc.summary.trim()))
      ..writeln();
  }
  for (final s in doc.body) {
    final body = sectionBody(s).trim();
    b
      ..writeln('## ${s.heading}')
      ..writeln();
    if (body.isNotEmpty) {
      b
        ..writeln(portableMarkdown(cite(body), doc.sources))
        ..writeln();
    }
  }
  final refs = doc.references;
  if (refs.isNotEmpty) {
    b
      ..writeln('## ${DocStrings.references}')
      ..writeln();
    for (final (i, c) in refs.indexed) {
      b.writeln('${i + 1}. <a id="ref-${i + 1}"></a>${_referenceLine(c)}');
    }
    b.writeln();
  }
  if (doc.glossary.isNotEmpty) {
    b
      ..writeln('## ${DocStrings.glossaryTitle}')
      ..writeln();
    for (final g in doc.glossary) {
      b.writeln('- **${g.term}**: ${g.definition}');
    }
    b.writeln();
  }
  return b.toString().trimRight();
}

/// The document as a PDF: cover, contents, sections, References.
Future<Uint8List> buildDocPdf(Doc doc, {DateTime? now}) async {
  final fonts = await PdfFonts.load();
  final title = doc.title.trim().isEmpty ? DocStrings.untitled : doc.title;
  final pdf = pw.Document(title: title, creator: AppStrings.appName);
  final w = MarkdownPdfWriter(fonts);
  final date = now ?? DateTime.now();
  final h = w.body.copyWith(fontWeight: MarkdownPdfWriter.bold);
  final refs = doc.references;
  final sections = doc.body;
  final numbers = citeNumbers(doc);
  String cite(String md) => numberCitations(md, numbers, links: false);

  List<pw.Widget> heading(String text, double size) => [
    pw.SizedBox(height: PdfSizes.messageGap),
    pw.Text(text, style: h.copyWith(fontSize: size)),
    pw.SizedBox(height: PdfSizes.blockGap),
  ];

  pdf.addPage(
    pw.MultiPage(
      maxPages: PdfSizes.maxPages,
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      theme: w.theme,
      pageFormat: MarkdownPdfWriter.pageFormat,
      footer: w.footer,
      build: (_) => [
        // Cover.
        pw.SizedBox(height: PdfSizes.messageGap * 4),
        pw.Text(DocStrings.card, style: w.caption.copyWith(color: w.accent)),
        pw.SizedBox(height: PdfSizes.blockGap * 2),
        pw.Text(title, style: h.copyWith(fontSize: PdfSizes.title * 1.6)),
        if (doc.subtitle.trim().isNotEmpty) ...[
          pw.SizedBox(height: PdfSizes.blockGap * 2),
          pw.Text(
            doc.subtitle.trim(),
            style: w.body.copyWith(color: w.secondary, fontSize: PdfSizes.h2),
          ),
        ],
        pw.SizedBox(height: PdfSizes.messageGap),
        pw.Divider(color: w.border, thickness: PdfSizes.border),
        pw.Text(_metaLine(doc), style: w.caption),
        pw.SizedBox(height: PdfSizes.blockGap),
        pw.Text(
          ShareStrings.exportedLine(date, AppStrings.appName).toUpperCase(),
          style: w.caption,
        ),
        if (doc.summary.trim().isNotEmpty) ...[
          pw.SizedBox(height: PdfSizes.messageGap),
          pw.Text(DocStrings.abstractLabel, style: w.caption),
          pw.SizedBox(height: PdfSizes.blockGap),
          ...w.markdown(cite(doc.summary.trim())),
        ],
        // Contents.
        pw.NewPage(),
        ...heading(DocStrings.contentsPdf, PdfSizes.h1),
        for (final (i, s) in sections.indexed)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: PdfSizes.blockGap / 2),
            child: pw.Row(
              children: [
                pw.SizedBox(
                  width: PdfSizes.indent * 2,
                  child: pw.Text(DocStrings.sectionNo(i + 1), style: w.caption),
                ),
                pw.Expanded(child: pw.Text(s.heading, style: w.body)),
              ],
            ),
          ),
        if (refs.isNotEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(left: PdfSizes.indent * 2),
            child: pw.Text(DocStrings.references, style: w.body),
          ),
        // Body.
        pw.NewPage(),
        for (final (i, s) in sections.indexed) ...[
          ...heading(
            '${DocStrings.sectionNo(i + 1)}  ${s.heading}',
            PdfSizes.h1,
          ),
          ...w.markdown(cite(sectionBody(s))),
        ],
        if (refs.isNotEmpty) ...[
          ...heading(DocStrings.references, PdfSizes.h1),
          for (final (i, c) in refs.indexed)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: PdfSizes.blockGap / 2),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.SizedBox(
                    width: PdfSizes.indent * 2.5,
                    child: pw.Text('${i + 1}', style: w.caption),
                  ),
                  pw.Expanded(
                    child: pw.RichText(
                      text: pw.TextSpan(
                        style: w.body.copyWith(fontSize: PdfSizes.table),
                        children: [
                          pw.TextSpan(
                            text: _referenceLine(c, links: false),
                            annotation: c.url.isEmpty
                                ? null
                                : pw.AnnotationUrl(c.url),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
        if (doc.glossary.isNotEmpty) ...[
          ...heading(DocStrings.glossaryTitle, PdfSizes.h1),
          for (final g in doc.glossary)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: PdfSizes.blockGap / 2),
              child: pw.RichText(
                text: pw.TextSpan(
                  style: w.body,
                  children: [
                    pw.TextSpan(text: '${g.term}: ', style: h),
                    pw.TextSpan(text: g.definition),
                  ],
                ),
              ),
            ),
        ],
      ],
    ),
  );
  return pdf.save();
}

/// "my-report.pdf"; falls back to "document".
String docFileName(Doc doc, String extension) {
  var slug = doc.title
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (slug.length > ShareSizes.fileNameMax) {
    slug = slug
        .substring(0, ShareSizes.fileNameMax)
        .replaceAll(RegExp(r'-+$'), '');
  }
  return '${slug.isEmpty ? DocStrings.fileFallback : slug}.$extension';
}

enum DocExportFormat { pdf, markdown, docx }

/// EXPORT: PDF built on device, Markdown, or DOCX from the server.
Future<void> exportDoc(BuildContext context, Doc doc, {DocsApi? api}) async {
  Haptics.tap();
  final format = await showShareSheet<DocExportFormat>(
    context,
    title: DocStrings.exportTitle,
    options: const [
      (DocExportFormat.pdf, ShareIcons.pdf, DocStrings.pdf),
      (DocExportFormat.markdown, ShareIcons.markdown, DocStrings.markdown),
      (DocExportFormat.docx, DocIcons.docx, DocStrings.docx),
    ],
  );
  if (format == null || !context.mounted) return;
  docToast(context, DocStrings.exporting);
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final (bytes, ext, mime) = switch (format) {
      DocExportFormat.pdf => (
        await buildDocPdf(doc),
        ShareStrings.pdfExtension,
        ShareStrings.pdfMime,
      ),
      DocExportFormat.markdown => (
        Uint8List.fromList(utf8.encode(docMarkdown(doc))),
        ShareStrings.mdExtension,
        ShareStrings.mdMime,
      ),
      DocExportFormat.docx => (
        await (api ?? DocsApi()).export(doc.id, ShareStrings.docxExtension),
        ShareStrings.docxExtension,
        ShareStrings.docxMime,
      ),
    };
    messenger?.hideCurrentSnackBar();
    await shareBytes(bytes, name: docFileName(doc, ext), mime: mime);
  } catch (_) {
    Haptics.error();
    if (context.mounted) docToast(context, DocStrings.exportFailed);
  }
}
