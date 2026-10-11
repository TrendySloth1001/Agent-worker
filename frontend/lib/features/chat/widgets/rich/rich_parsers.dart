// Parsers for the structured fenced blocks. Each returns null when the text
// is not recognisable, so the caller can fall back to a plain code block.

class EmailDraft {
  const EmailDraft({
    required this.to,
    required this.cc,
    required this.bcc,
    required this.subject,
    required this.body,
  });

  final String to, cc, bcc, subject, body;

  /// Plain-text form for the clipboard.
  String get full {
    final b = StringBuffer();
    if (to.isNotEmpty) b.writeln('To: $to');
    if (cc.isNotEmpty) b.writeln('Cc: $cc');
    if (bcc.isNotEmpty) b.writeln('Bcc: $bcc');
    if (subject.isNotEmpty) b.writeln('Subject: $subject');
    b.writeln();
    b.write(body);
    return b.toString();
  }
}

class MessageDraft {
  const MessageDraft({
    required this.to,
    required this.platform,
    required this.text,
  });

  final String to, platform, text;
}

class SpecCardData {
  const SpecCardData({
    required this.title,
    required this.subtitle,
    required this.iconSet,
    required this.iconName,
    required this.rows,
  });

  final String title, subtitle;
  final String? iconSet, iconName;
  final List<(String, String)> rows;
}

final _headerLine = RegExp(r'^\s*([A-Za-z][A-Za-z -]{0,20}?)\s*:\s?(.*)$');
final _iconId = RegExp(
  r'^([a-z0-9]+(?:-[a-z0-9]+)*):([a-z0-9]+(?:-[a-z0-9]+)*)$',
);

/// Reads leading `Key: value` lines whose key is in [keys]. Returns the
/// headers and the remaining text (leading blank lines dropped).
(Map<String, String>, String) _splitHeaders(String src, Set<String> keys) {
  final lines = src.replaceAll('\r\n', '\n').split('\n');
  final headers = <String, String>{};
  var i = 0;
  while (i < lines.length) {
    final m = _headerLine.firstMatch(lines[i]);
    final key = m?[1]?.toLowerCase().trim();
    if (m == null || key == null || !keys.contains(key)) break;
    headers[key] = (m[2] ?? '').trim();
    i++;
  }
  while (i < lines.length && lines[i].trim().isEmpty) {
    i++;
  }
  return (headers, lines.sublist(i).join('\n').trimRight());
}

EmailDraft? parseEmail(String src) {
  final (h, body) = _splitHeaders(src, {'to', 'cc', 'bcc', 'subject'});
  if (h.isEmpty) return null;
  final to = h['to'] ?? '';
  final subject = h['subject'] ?? '';
  if (to.isEmpty && subject.isEmpty && body.isEmpty) return null;
  return EmailDraft(
    to: to,
    cc: h['cc'] ?? '',
    bcc: h['bcc'] ?? '',
    subject: subject,
    body: plainEmailText(body),
  );
}

MessageDraft? parseMessage(String src) {
  final (h, text) = _splitHeaders(src, {'to', 'platform'});
  if (text.isEmpty) return null;
  return MessageDraft(
    to: h['to'] ?? '',
    platform: (h['platform'] ?? '').toLowerCase(),
    text: text,
  );
}

SpecCardData? parseSpecCard(String src) {
  String title = '', subtitle = '', icon = '';
  final rows = <(String, String)>[];
  for (final line in src.replaceAll('\r\n', '\n').split('\n')) {
    final idx = line.indexOf(':');
    if (idx <= 0) continue;
    final key = line.substring(0, idx).trim();
    final value = line.substring(idx + 1).trim();
    switch (key.toLowerCase()) {
      case 'title':
        title = value;
      case 'subtitle':
        subtitle = value;
      case 'icon':
        icon = value;
      default:
        if (key.isNotEmpty && value.isNotEmpty) rows.add((key, value));
    }
  }
  if (title.isEmpty) return null;
  final m = _iconId.firstMatch(icon);
  return SpecCardData(
    title: title,
    subtitle: subtitle,
    iconSet: m?[1],
    iconName: m?[2],
    rows: rows,
  );
}

enum DiffKind { added, removed, hunk, meta, context }

/// [inHunk] is true once a `@@` header was seen, after which `---` / `+++`
/// are ordinary changed lines.
DiffKind diffKind(String line, {required bool inHunk}) {
  if (!inHunk &&
      (line.startsWith('+++ ') ||
          line.startsWith('--- ') ||
          line.startsWith('diff ') ||
          line.startsWith('index '))) {
    return DiffKind.meta;
  }
  if (line.startsWith('@@')) return DiffKind.hunk;
  if (line.startsWith('+')) return DiffKind.added;
  if (line.startsWith('-')) return DiffKind.removed;
  return DiffKind.context;
}

/// Mail apps show plain text, so markdown the model used is turned into
/// its plain-text equivalent: bold/italic markers and backticks are dropped,
/// list dashes become bullets, headings lose their hashes.
String plainEmailText(String body) => body
    .split('\n')
    .map(
      (line) => line
          .replaceFirstMapped(RegExp(r'^(\s*)[-*+]\s+'), (m) => '${m[1]}• ')
          .replaceFirst(RegExp(r'^#{1,6}\s+'), '')
          .replaceAllMapped(RegExp(r'(\*\*|__)(.+?)\1'), (m) => m[2]!)
          .replaceAllMapped(RegExp(r'`([^`]+)`'), (m) => m[1]!),
    )
    .join('\n');
