import 'package:hugeicons/hugeicons.dart';

/// Editing a sent message in place.
abstract final class EditStrings {
  static const edit = 'EDIT';
  static const editHint = 'LATER MESSAGES ARE REPLACED';
  static const busyHint = 'WAIT FOR THE REPLY TO FINISH';
  static const editing = 'EDIT MESSAGE';
  static const cancel = 'CANCEL';
  static const send = 'SEND';
  static const inputHint = 'Message';
  static const busy = 'Wait for the reply to finish.';
}

/// Sharing a reply and exporting a chat.
abstract final class ShareStrings {
  static const share = 'SHARE';
  static const shareTitle = 'SHARE REPLY';
  static const asImage = 'SHARE AS IMAGE';
  static const copyMarkdown = 'COPY AS MARKDOWN';
  static const shareText = 'SHARE TEXT';
  static const copied = 'Copied as Markdown.';
  static const imageFailed = 'Could not create the image.';
  static const continues = 'CONTINUES IN THE APP';
  static const rendering = 'RENDERING';

  static const export = 'EXPORT';
  static const exportTitle = 'EXPORT CHAT';
  static const markdown = 'MARKDOWN (.md)';
  static const pdf = 'PDF';
  static const exporting = 'EXPORTING';
  static const exportFailed = 'Could not export this chat.';
  static const nothingToExport = 'Nothing to export yet.';

  // Document text (Markdown and PDF), sentence case.
  static const untitled = 'Untitled chat';
  static const you = 'You';
  static const context = 'Context';
  static const sources = 'Sources';
  static const attachments = 'Attachments';
  static const knowledgeBase = 'knowledge base';
  static const exported = 'Exported';
  static const separator = ' · ';
  static const fileFallback = 'chat';
  static const mdExtension = 'md';
  static const pdfExtension = 'pdf';
  static const pngExtension = 'png';
  static const mdMime = 'text/markdown';
  static const pdfMime = 'application/pdf';
  static const pngMime = 'image/png';
  static const replyFile = 'reply';

  /// "2026-10-11 14:03".
  static String stamp(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} '
        '${two(d.hour)}:${two(d.minute)}';
  }

  /// "Exported 2026-10-11 14:03 · sparky".
  static String exportedLine(DateTime d, String app) =>
      '$exported ${stamp(d)}$separator$app';

  /// "PAGE 2 / 5".
  static String page(int n, int total) => 'PAGE $n / $total';
}

/// Icons for sharing and export.
abstract final class ShareIcons {
  static const share = HugeIcons.strokeRoundedShare08;
  static const image = HugeIcons.strokeRoundedImage02;
  static const text = HugeIcons.strokeRoundedTextAlignLeft;
  static const export = HugeIcons.strokeRoundedFileExport;
  static const markdown = HugeIcons.strokeRoundedFileCode;
  static const pdf = HugeIcons.strokeRoundedPdf02;
}

/// The reply image and the inline editor.
abstract final class ShareSizes {
  /// Taller replies are cut off with a fade.
  static const imageMaxHeight = 2200.0;
  static const imageFade = 72.0;

  /// Sharp enough for a phone screen without huge files.
  static const imagePixelRatio = 2.5;

  /// Time for images and fonts in the reply to load before capture.
  static const settle = Duration(milliseconds: 700);

  static const editorMaxLines = 10;
  static const editorButtonHeight = 32.0;
  static const editorChipMaxWidth = 180.0;

  /// File names keep this many characters of the chat title.
  static const fileNameMax = 48;
}

/// PDF layout, in points.
abstract final class PdfSizes {
  static const margin = 48.0;
  static const title = 20.0;
  static const h1 = 16.0;
  static const h2 = 14.0;
  static const h3 = 12.0;
  static const body = 10.5;
  static const code = 8.5;
  static const caption = 7.5;
  static const role = 8.0;
  static const lineSpacing = 3.0;
  static const blockGap = 6.0;
  static const messageGap = 18.0;
  static const indent = 14.0;
  static const bullet = 10.0;
  static const boxPadding = 8.0;
  static const border = 0.6;
  static const quoteBar = 2.0;
  static const cellPadding = 4.0;
  static const letterSpacing = 0.8;
  static const table = 9.5;
  static const inlineCodeScale = 0.88;

  /// Long chats run to many pages; the package stops at 20 by default.
  static const maxPages = 1000;

  static const fontRegular = 'assets/pdf/SpaceGrotesk-Regular.ttf';
  static const fontBold = 'assets/pdf/SpaceGrotesk-Bold.ttf';
  static const fontMono = 'assets/fonts/SpaceMono-Regular.ttf';
  static const fontMonoBold = 'assets/fonts/SpaceMono-Bold.ttf';
}
