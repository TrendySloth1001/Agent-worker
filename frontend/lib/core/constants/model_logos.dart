import 'app_icons.dart';
import 'brand_logos.dart';

/// The real logo of the family a model belongs to (who made it), whichever
/// provider serves it: `groq:openai/gpt-oss-120b` and `ollama:gpt-oss:20b`
/// both draw OpenAI, `nvidia:meta/llama-…` draws Meta. A model of an
/// unknown family falls back to its provider's logo, then to the neutral
/// models glyph; never a lookalike.
abstract final class ModelLogos {
  /// Model-name patterns, checked first and in order. Each name must start
  /// at the beginning or after a separator, so `o3` does not match `glm-o3x`.
  static final _families = <(RegExp, AppIconData)>[
    (
      _name(r'gpt|chatgpt|o[1-9](?![0-9a-z])|whisper|dall-e|codex'),
      BrandLogos.openai,
    ),
    (_name('gemma'), BrandLogos.gemma),
    (_name('llama'), BrandLogos.meta),
    (_name('qwen|qwq'), BrandLogos.qwen),
    (_name('nemotron'), BrandLogos.nvidia),
    (_name('chatglm|glm'), BrandLogos.glm),
    (_name('deepseek'), BrandLogos.deepseek),
    (_name('kimi|moonshot'), BrandLogos.kimi),
    (
      _name('mistral|mixtral|ministral|magistral|codestral|devstral|pixtral'),
      BrandLogos.mistral,
    ),
    (_name('phi'), BrandLogos.microsoft),
  ];

  /// Publisher namespaces (`meta/…`, `z-ai/…`) for a model whose name
  /// alone says nothing.
  static const _vendors = <String, AppIconData>{
    'openai': BrandLogos.openai,
    'meta': BrandLogos.meta,
    'meta-llama': BrandLogos.meta,
    'qwen': BrandLogos.qwen,
    'alibaba': BrandLogos.qwen,
    'nvidia': BrandLogos.nvidia,
    'z-ai': BrandLogos.glm,
    'zai-org': BrandLogos.glm,
    'thudm': BrandLogos.glm,
    'zhipu': BrandLogos.glm,
    'deepseek': BrandLogos.deepseek,
    'deepseek-ai': BrandLogos.deepseek,
    'moonshotai': BrandLogos.kimi,
    'mistralai': BrandLogos.mistral,
    'microsoft': BrandLogos.microsoft,
  };

  static RegExp _name(String alts) => RegExp('(?:^|[/:._-])(?:$alts)');

  /// Splits `provider:vendor/model` into the provider (when the prefix is
  /// a known one) and the rest.
  static ({String? provider, String model}) _split(String id) {
    final i = id.indexOf(':');
    if (i > 0 && AppIcons.knownProvider(id.substring(0, i)) != null) {
      return (provider: id.substring(0, i), model: id.substring(i + 1));
    }
    return (provider: null, model: id);
  }

  /// The family logo for [id], or null when the family is unknown.
  static AppIconData? familyOf(String id) {
    final model = _split(id.trim().toLowerCase()).model;
    if (model.isEmpty) return null;
    for (final (pattern, logo) in _families) {
      if (pattern.hasMatch(model)) return logo;
    }
    final slash = model.indexOf('/');
    return slash > 0 ? _vendors[model.substring(0, slash)] : null;
  }

  /// Family logo, else the provider's logo ([provider], or the id's own
  /// `provider:` prefix), else the neutral models glyph.
  static AppIconData forModelId(String? id, {String? provider}) {
    final raw = (id ?? '').trim().toLowerCase();
    return familyOf(raw) ??
        AppIcons.provider(provider ?? _split(raw).provider ?? '');
  }
}
