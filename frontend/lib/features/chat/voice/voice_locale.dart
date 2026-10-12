import '../../../core/constants/voice.dart';

final _tag = RegExp(r'^[a-z]{2,3}([-_][A-Za-z]{2,4})?$');

/// The BCP-47 tag to dictate in: the reply language when it is set (a name
/// such as "Hindi" or a tag such as "hi-IN"), else the device locale.
String voiceLocaleFor({required String language, required String device}) {
  final dev = device.replaceAll('_', '-');
  final wanted = language.trim();
  if (wanted.isEmpty) return dev;
  var tag = wanted;
  if (!_tag.hasMatch(wanted)) {
    final known = VoiceConfig.languageTags[wanted.toLowerCase()];
    if (known == null) return dev;
    tag = known;
  }
  tag = tag.replaceAll('_', '-');
  // A bare language ("en") takes the device's region when it is the same language.
  if (!tag.contains('-') && _lang(dev) == _lang(tag)) return dev;
  return tag;
}

String _lang(String tag) => tag.split(RegExp('[-_]')).first.toLowerCase();

/// The id in [available] (as the recognizer lists them) that best fits [tag]:
/// exact, then the same language, else null (use the recognizer's default).
String? pickRecognizerLocale(String tag, Iterable<String> available) {
  String norm(String s) => s.replaceAll('_', '-').toLowerCase();
  final want = norm(tag);
  for (final id in available) {
    if (norm(id) == want) return id;
  }
  final lang = _lang(tag);
  for (final id in available) {
    if (_lang(id) == lang) return id;
  }
  return null;
}
