import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

import '../../../core/constants/app_strings.dart';
import '../../../core/constants/share_export.dart';
import '../../../data/chat_message.dart';
import 'chat_export.dart';
import 'markdown_pdf_writer.dart';

/// A chat as a PDF: light page, Space Grotesk text, Space Mono labels and
/// code. Markdown is laid out natively; widget blocks show their source.
Future<Uint8List> buildChatPdf(ExportChat chat) async {
  final fonts = await PdfFonts.load();
  final doc = pw.Document(title: chat.title, creator: AppStrings.appName);
  final w = _ChatPdfWriter(fonts);
  doc.addPage(
    pw.MultiPage(
      maxPages: PdfSizes.maxPages,
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      theme: w.theme,
      pageFormat: MarkdownPdfWriter.pageFormat,
      footer: w.footer,
      build: (_) => w.chat(chat),
    ),
  );
  return doc.save();
}

/// Messages with a role line each, on top of the shared markdown writer.
class _ChatPdfWriter extends MarkdownPdfWriter {
  _ChatPdfWriter(super.f);

  List<pw.Widget> chat(ExportChat chat) => [
    pw.Text(
      chat.title,
      style: body.copyWith(
        fontWeight: MarkdownPdfWriter.bold,
        fontSize: PdfSizes.title,
      ),
    ),
    pw.SizedBox(height: PdfSizes.blockGap),
    pw.Text(
      ShareStrings.exportedLine(chat.date, AppStrings.appName).toUpperCase(),
      style: caption,
    ),
    pw.SizedBox(height: PdfSizes.blockGap),
    pw.Divider(color: border, thickness: PdfSizes.border),
    for (final m in chat.messages) ...message(m, chat.roleName(m)),
  ];

  List<pw.Widget> message(ChatMessage m, String role) {
    final isUser = m.role == Role.user;
    final blocks = markdown(m.content);
    return [
      pw.SizedBox(height: PdfSizes.messageGap),
      pw.Row(
        children: [
          pw.Container(
            width: PdfSizes.bullet / 2,
            height: PdfSizes.bullet / 2,
            decoration: pw.BoxDecoration(
              shape: pw.BoxShape.circle,
              color: isUser ? tertiary : primary,
            ),
          ),
          pw.SizedBox(width: PdfSizes.blockGap),
          pw.Text(
            role.toUpperCase(),
            style: caption.copyWith(color: secondary, fontSize: PdfSizes.role),
          ),
        ],
      ),
      pw.SizedBox(height: PdfSizes.blockGap),
      if (m.attachments.isNotEmpty) ...[
        pw.Text(
          '${ShareStrings.attachments.toUpperCase()}: '
          '${m.attachments.map((a) => a.name).join(', ')}',
          style: caption,
        ),
        pw.SizedBox(height: PdfSizes.blockGap),
      ],
      // Top level, not in a column: only top-level text and code can
      // break across pages.
      ...blocks,
      if (m.citations.isNotEmpty) ...sources(m.citations),
    ];
  }
}
