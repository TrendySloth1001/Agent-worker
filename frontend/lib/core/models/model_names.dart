/// A readable name for a model id the server's list doesn't cover, e.g.
/// `meta-llama/llama-4-scout-17b-16e-instruct` → "Llama 4 Scout 17B".
/// Never the raw id: provider prefixes, variants and date stamps are dropped.
String prettyModelName(String id) {
  var s = id.trim();
  if (s.isEmpty) return '';
  s = s.split('/').last; // provider/org prefix
  s = s.split(':').first; // ":free", ":cloud", ollama tags
  s = s.replaceAll(RegExp(r'[-_.]?\d{4}-?\d{2}-?\d{2}$'), ''); // dates
  final words = s
      .split(RegExp(r'[-_\s]+'))
      .where((w) => w.isNotEmpty && !_drop.contains(w.toLowerCase()))
      .where((w) => !RegExp(r'^\d+e$', caseSensitive: false).hasMatch(w))
      .map(_word)
      .toList();
  return words.take(_maxWords).join(' ');
}

const _maxWords = 4;

/// Variant noise that says nothing to a user.
const _drop = {
  'instruct',
  'it',
  'chat',
  'preview',
  'latest',
  'versatile',
  'hf',
  'fp8',
  'awq',
  'gguf',
  'turbo',
};

const _brands = {
  'llama': 'Llama',
  'gpt': 'GPT',
  'oss': 'OSS',
  'qwen': 'Qwen',
  'qwen3': 'Qwen3',
  'qwq': 'QwQ',
  'glm': 'GLM',
  'gemma': 'Gemma',
  'gemini': 'Gemini',
  'nemotron': 'Nemotron',
  'deepseek': 'DeepSeek',
  'mistral': 'Mistral',
  'mixtral': 'Mixtral',
  'kimi': 'Kimi',
  'claude': 'Claude',
  'phi': 'Phi',
  'vl': 'VL',
  'r1': 'R1',
  'v3': 'V3',
};

String _word(String w) {
  final lower = w.toLowerCase();
  final brand = _brands[lower];
  if (brand != null) return brand;
  // Sizes: 70b → 70B, 1.5b → 1.5B, 8x7b → 8x7B.
  if (RegExp(r'^[\d.x]+[bmk]$').hasMatch(lower)) {
    return lower.substring(0, lower.length - 1) +
        lower[lower.length - 1].toUpperCase();
  }
  if (RegExp(r'^\d').hasMatch(w)) return w;
  return w[0].toUpperCase() + w.substring(1);
}
