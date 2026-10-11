/// Replies should use icons, not emoji. Any emoji a model still writes is
/// swapped for the matching Hugeicons inline icon, or removed when there is
/// no good match. Code (fenced blocks and `inline code`) is left untouched.
library;

const _icons = <String, String>{
  '✅': 'checkmark-circle-02',
  '✔': 'tick-02',
  '☑': 'checkmark-square-02',
  '❌': 'cancel-circle',
  '✖': 'cancel-01',
  '⚠': 'alert-02',
  '🚨': 'alert-diamond',
  '❗': 'alert-circle',
  '❓': 'help-circle',
  '❔': 'help-circle',
  'ℹ': 'information-circle',
  '💡': 'idea-01',
  '🚀': 'rocket-01',
  '🔥': 'fire',
  '⭐': 'star',
  '🌟': 'star',
  '✨': 'magic-wand-01',
  '🎯': 'target-02',
  '📌': 'pin',
  '📍': 'location-01',
  '🔧': 'wrench-01',
  '🛠': 'tools',
  '⚙': 'settings-02',
  '🔩': 'wrench-01',
  '🔨': 'hammer',
  '🧰': 'tools',
  '📝': 'note-edit',
  '✏': 'pencil-edit-01',
  '📄': 'file-01',
  '📃': 'file-01',
  '📑': 'files-01',
  '📁': 'folder-01',
  '📂': 'folder-open',
  '🗂': 'folder-library',
  '📊': 'chart-histogram',
  '📈': 'chart-increase',
  '📉': 'chart-decrease',
  '📦': 'package',
  '🐛': 'bug-01',
  '🔒': 'lock',
  '🔓': 'square-unlock-01',
  '🔑': 'key-01',
  '🛡': 'shield-01',
  '🔐': 'lock-password',
  '🌐': 'globe',
  '🔗': 'link-01',
  '📧': 'mail-01',
  '✉': 'mail-01',
  '📨': 'mail-send-01',
  '💬': 'bubble-chat',
  '🗨': 'bubble-chat',
  '📞': 'call',
  '📱': 'smart-phone-01',
  '💻': 'laptop',
  '🖥': 'computer',
  '⌨': 'keyboard',
  '🖱': 'mouse-01',
  '🧠': 'ai-brain-01',
  '🤖': 'robot-01',
  '👤': 'user',
  '👥': 'user-multiple',
  '👉': 'arrow-right-01',
  '👈': 'arrow-left-01',
  '➡': 'arrow-right-01',
  '⬅': 'arrow-left-01',
  '⬆': 'arrow-up-01',
  '⬇': 'arrow-down-01',
  '🔄': 'refresh',
  '🔁': 'repeat',
  '⏱': 'timer-01',
  '⏰': 'alarm-clock',
  '🕒': 'clock-01',
  '⌛': 'hourglass',
  '⏳': 'hourglass',
  '📅': 'calendar-03',
  '🗓': 'calendar-03',
  '💰': 'money-01',
  '💵': 'money-01',
  '💳': 'credit-card',
  '🧪': 'test-tube',
  '🔬': 'microscope',
  '🔍': 'search-01',
  '🔎': 'search-01',
  '📚': 'books-01',
  '📖': 'book-open-01',
  '🎓': 'mortarboard-01',
  '🏗': 'building-03',
  '🏠': 'home-01',
  '🌍': 'earth',
  '☁': 'cloud',
  '🗄': 'database-01',
  '💾': 'floppy-disk',
  '🧩': 'puzzle',
  '🎨': 'paint-board',
  '🖼': 'image-01',
  '📷': 'camera-01',
  '🎥': 'video-01',
  '🎬': 'video-01',
  '🎵': 'music-note-01',
  '🔔': 'notification-01',
  '📣': 'megaphone-01',
  '📢': 'megaphone-01',
  '👍': 'thumbs-up',
  '👎': 'thumbs-down',
  '🏆': 'award-01',
  '🥇': 'medal-first-place',
  '🎉': 'party',
  '⚡': 'flash',
  '🔋': 'battery-full',
  '🧹': 'clean',
  '🗑': 'delete-02',
  '➕': 'add-circle',
  '➖': 'remove-circle',
  '🆕': 'new-releases',
  '🔴': 'circle',
  '🟢': 'circle',
  '🟡': 'circle',
  '✋': 'hand-pointing-left-01',
  '🙏': 'favourite',
  '❤': 'favourite',
  '💯': 'checkmark-badge-01',
};

/// Pictographs that are ordinary text symbols, not emoji, in technical writing.
const _keep = {'©', '®', '™', '↔', '↕', '↖', '↗', '↘', '↙', '‼', '⁉', '〰', '〽'};

// The lint checks the pattern without `unicode: true`, where \p{...} is
// invalid; it is valid (and tested) with the flag below.
final _emojiRe = RegExp(
  // ignore: valid_regexps
  r'(?:\p{Extended_Pictographic}|[\u{1F1E6}-\u{1F1FF}]{2})'
  r'(?:\u{FE0F}|\u{20E3}|[\u{1F3FB}-\u{1F3FF}]|\u{200D}\p{Extended_Pictographic})*',
  unicode: true,
);

/// Keycap emoji like 2️⃣ or #️⃣: kept as the plain character.
final _keycapRe = RegExp('([0-9#*])\uFE0F?\u20E3');

String _swap(String text) => text
    .replaceAllMapped(_keycapRe, (m) => '${m[1]}.')
    .replaceAllMapped(_emojiRe, (m) {
      final base = String.fromCharCode(m[0]!.runes.first);
      if (_keep.contains(base)) return m[0]!;
      final name = _icons[base];
      return name == null ? '' : '{{icon:hugeicons:$name}}';
    });

String emojiToIcons(String markdown) {
  if (!_emojiRe.hasMatch(markdown)) return markdown;
  final out = StringBuffer();
  var inFence = false;
  final lines = markdown.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.trimLeft().startsWith('```') ||
        line.trimLeft().startsWith('~~~')) {
      inFence = !inFence;
      out.write(line);
    } else if (inFence) {
      out.write(line);
    } else {
      // Only outside `inline code` spans.
      final parts = line.split('`');
      for (var k = 0; k < parts.length; k++) {
        if (k > 0) out.write('`');
        out.write(k.isEven ? _swap(parts[k]) : parts[k]);
      }
    }
    if (i < lines.length - 1) out.write('\n');
  }
  // An emoji that led a line leaves "- {{icon..}}  text"; tidy double spaces.
  return out.toString().replaceAllMapped(
    RegExp(r'(\S) {2,}(?=\S)'),
    (m) => '${m[1]} ',
  );
}
