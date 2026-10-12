import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/app_scope.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/share_export.dart';
import '../../../core/haptics.dart';
import '../../../data/chat_event.dart';
import '../../../data/chat_message.dart';
import '../../../data/conversations_api.dart';
import 'chat_pdf.dart';
import 'share_sheet.dart';

/// Reply markdown in a form that reads well outside the app: citation tags
/// become links, icon markers go, image markers become a short note.
String portableMarkdown(String md, List<Citation> citations) {
  final byId = {for (final c in citations) c.id: c};
  return md
      .replaceAll(_iconRe, '')
      .replaceAllMapped(_imageRe, (m) => '*[${m[2] ?? m[1]}]*')
      .replaceAllMapped(_citeRe, (m) {
        final c = byId[m[1]];
        if (c == null) return '';
        return c.url.isEmpty ? '[${m[1]}]' : '[${m[1]}](${c.url})';
      })
      .trim();
}

/// Plain text for SHARE TEXT: markdown marks dropped, links spelled out.
String plainText(String md) {
  final out = <String>[];
  for (final line in md.split('\n')) {
    if (_fenceLineRe.hasMatch(line)) continue;
    out.add(
      line
          .replaceAll(_iconRe, '')
          .replaceAllMapped(_imageRe, (m) => '[${m[2] ?? m[1]}]')
          .replaceAll(_citeRe, '')
          .replaceFirst(_headingMarkRe, '')
          .replaceFirst(_quoteMarkRe, '')
          .replaceAllMapped(_linkRe, (m) => '${m[1]} (${m[2]})')
          .replaceAll(_emphasisRe, ''),
    );
  }
  return out.join('\n').replaceAll(_blankRunRe, '\n\n').trim();
}

/// "Sources" list for the end of a reply, or '' when it has none.
String sourcesMarkdown(List<Citation> citations, {bool plain = false}) {
  if (citations.isEmpty) return '';
  final b = StringBuffer(plain ? '${ShareStrings.sources}:\n' : '');
  if (!plain) b.writeln('**${ShareStrings.sources}**\n');
  for (final c in citations) {
    final title = c.title.isEmpty ? c.site : c.title;
    final where = c.url.isNotEmpty
        ? (plain ? ' ${c.url}' : '')
        : ' (${ShareStrings.knowledgeBase})';
    final name = plain || c.url.isEmpty ? title : '[$title](${c.url})';
    b.writeln('- [${c.id}] $name$where');
  }
  return b.toString().trim();
}

/// One reply as markdown with its sources.
String replyMarkdown(ChatMessage m) => [
  portableMarkdown(m.content, m.citations),
  sourcesMarkdown(m.citations),
].where((s) => s.isNotEmpty).join('\n\n');

/// One reply as plain text with its sources.
String replyText(ChatMessage m) => [
  plainText(m.content),
  sourcesMarkdown(m.citations, plain: true),
].where((s) => s.isNotEmpty).join('\n\n');

/// A whole chat as a markdown document.
String chatMarkdown(ExportChat chat) {
  final b = StringBuffer()
    ..writeln('# ${chat.title}')
    ..writeln()
    ..writeln(ShareStrings.exportedLine(chat.date, AppStrings.appName));
  for (final m in chat.messages) {
    b
      ..writeln()
      ..writeln('---')
      ..writeln()
      ..writeln('## ${chat.roleName(m)}')
      ..writeln();
    if (m.attachments.isNotEmpty) {
      final names = m.attachments.map((a) => '`${a.name}`').join(', ');
      b
        ..writeln('*${ShareStrings.attachments}:* $names')
        ..writeln();
    }
    final body = m.role == Role.assistant
        ? _demoteHeadings(replyMarkdown(m))
        : m.content.trim();
    if (body.isNotEmpty) b.writeln(body);
  }
  return b.toString();
}

/// Reply headings sit under the message's own `##` heading: `#` becomes
/// `###` and so on, outside code fences.
String _demoteHeadings(String md) {
  var fenced = false;
  return md
      .split('\n')
      .map((line) {
        if (_fenceLineRe.hasMatch(line)) fenced = !fenced;
        if (fenced || !_headingMarkRe.hasMatch(line)) return line;
        final hashes = line.trimLeft().indexOf(' ');
        if (hashes + 2 > 6) return line;
        return '##${line.trimLeft()}';
      })
      .join('\n');
}

/// Everything an export needs, independent of where the chat came from.
class ExportChat {
  ExportChat({
    required String? title,
    required List<ChatMessage> messages,
    required this.modelName,
  }) : title = (title == null || title.trim().isEmpty)
           ? ShareStrings.untitled
           : title.trim(),
       date = DateTime.now(),
       messages = [
         for (final m in messages)
           if (!m.isError &&
               !m.isStreaming &&
               (m.content.trim().isNotEmpty || m.attachments.isNotEmpty))
             m,
       ];

  final String title;
  final DateTime date;
  final List<ChatMessage> messages;
  final String Function(String? modelId) modelName;

  String roleName(ChatMessage m) => switch (m.role) {
    Role.user => ShareStrings.you,
    Role.context => ShareStrings.context,
    Role.assistant => modelName(m.modelId),
  };

  /// "sodium-limits.pdf"; falls back to "chat".
  String fileName(String extension) {
    var slug = title
        .toLowerCase()
        .replaceAll(_slugRe, '-')
        .replaceAll(_dashesRe, '-')
        .replaceAll(_edgeDashRe, '');
    if (slug.length > ShareSizes.fileNameMax) {
      slug = slug
          .substring(0, ShareSizes.fileNameMax)
          .replaceAll(_edgeDashRe, '');
    }
    return '${slug.isEmpty ? ShareStrings.fileFallback : slug}.$extension';
  }
}

enum ExportFormat { markdown, pdf }

/// Asks for a format, then builds the file and opens the share sheet.
/// [load] supplies the messages (from memory or the server).
Future<void> exportChat(
  BuildContext context, {
  required String? title,
  required Future<List<ChatMessage>> Function() load,
  required String Function(String? modelId) modelName,
}) async {
  final format = await showShareSheet<ExportFormat>(
    context,
    title: ShareStrings.exportTitle,
    options: const [
      (ExportFormat.markdown, ShareIcons.markdown, ShareStrings.markdown),
      (ExportFormat.pdf, ShareIcons.pdf, ShareStrings.pdf),
    ],
  );
  if (format == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  void toast(String s) => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(s)));
  toast(ShareStrings.exporting);
  try {
    final chat = ExportChat(
      title: title,
      messages: await load(),
      modelName: modelName,
    );
    if (chat.messages.isEmpty) {
      Haptics.error();
      toast(ShareStrings.nothingToExport);
      return;
    }
    final (bytes, ext, mime) = switch (format) {
      ExportFormat.markdown => (
        Uint8List.fromList(utf8.encode(chatMarkdown(chat))),
        ShareStrings.mdExtension,
        ShareStrings.mdMime,
      ),
      ExportFormat.pdf => (
        await buildChatPdf(chat),
        ShareStrings.pdfExtension,
        ShareStrings.pdfMime,
      ),
    };
    messenger.hideCurrentSnackBar();
    await shareBytes(bytes, name: chat.fileName(ext), mime: mime);
  } catch (_) {
    Haptics.error();
    toast(ShareStrings.exportFailed);
  }
}

/// Export for a chat in history: the open chat comes from memory (it may
/// hold unsaved replies), others from the server.
Future<void> exportSavedChat(
  BuildContext context, {
  required String id,
  required String? title,
  required String? openId,
  required List<ChatMessage> openMessages,
  required String Function(String? modelId) modelName,
}) {
  final api = ConversationsApi(AppScope.of(context).baseUrl);
  return exportChat(
    context,
    title: title,
    modelName: modelName,
    load: () async {
      if (id == openId) return List.of(openMessages);
      final (_, messages) = await api.get(id);
      return messages;
    },
  );
}

/// Writes [bytes] to a temp file and opens the system share sheet.
Future<void> shareBytes(
  Uint8List bytes, {
  required String name,
  required String mime,
  String? text,
}) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}${Platform.pathSeparator}$name');
  await file.writeAsBytes(bytes, flush: true);
  Haptics.received();
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: mime, name: name)],
      text: text,
    ),
  );
}

/// Opens the system share sheet with [text].
Future<void> shareText(String text, {String? subject}) async {
  Haptics.received();
  await SharePlus.instance.share(ShareParams(text: text, subject: subject));
}

final _citeRe = RegExp(r'\[([KWDGC]\d{1,2})\](?!\()');
final _iconRe = RegExp(r'\{\{icon:[^}\n]*\}\} ?');
final _imageRe = RegExp(r'\{\{image:([^}|]{1,120})(?:\|([^}]{1,160}))?\}\}');
final _fenceLineRe = RegExp(r'^\s*(`{3,}|~{3,})');
final _headingMarkRe = RegExp(r'^\s{0,3}#{1,6}\s+');
final _quoteMarkRe = RegExp(r'^\s{0,3}>\s?(\[![A-Za-z]+\]\s*)?');
final _linkRe = RegExp(r'\[([^\]\n]+)\]\(([^)\s]+)\)');
final _emphasisRe = RegExp(r'\*\*|__|(?<![\w*])\*(?!\s)|`|==');
final _blankRunRe = RegExp(r'\n{3,}');
final _slugRe = RegExp(r'[^a-z0-9]+');
final _dashesRe = RegExp(r'-{2,}');
final _edgeDashRe = RegExp(r'^-+|-+$');
