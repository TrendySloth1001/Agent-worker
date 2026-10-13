import 'dart:io';

import 'package:app/core/constants/app_icons.dart';
import 'package:app/core/constants/brand_logos.dart';
import 'package:app/core/constants/model_logos.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every `provider:model` id the backend names (registry, fallbacks, vision,
/// Round Table...), read from its sources so a new model fails this test
/// until it has a logo.
List<String> _backendModelIds() {
  final src = Directory('../backend/src');
  if (!src.existsSync()) return const [];
  final id = RegExp(
    r'''["'`]((?:groq|nvidia|ollama|openrouter):[^"'`\s$]+)["'`]''',
  );
  final out = <String>{};
  for (final f in src.listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.ts')) continue;
    for (final m in id.allMatches(f.readAsStringSync())) {
      out.add(m.group(1)!);
    }
  }
  // Tools that ride on a provider, not models.
  out.removeWhere((s) => s == 'ollama:web_search');
  return out.toList()..sort();
}

void main() {
  test('model families map to their makers, whatever the provider', () {
    const cases = {
      'groq:openai/gpt-oss-120b': BrandLogos.openai,
      'groq:openai/gpt-oss-20b': BrandLogos.openai,
      'ollama:gpt-oss:120b': BrandLogos.openai,
      'nvidia:openai/gpt-oss-20b': BrandLogos.openai,
      'openrouter:openai/o3-mini': BrandLogos.openai,
      'ollama:gemma4:31b': BrandLogos.gemma,
      'openrouter:google/gemma-4-31b-it:free': BrandLogos.gemma,
      'nvidia:meta/llama-3.2-11b-vision-instruct': BrandLogos.meta,
      'groq:llama-3.3-70b-versatile': BrandLogos.meta,
      'openrouter:meta-llama/llama-4-scout:free': BrandLogos.meta,
      'groq:qwen/qwen3.8-27b': BrandLogos.qwen,
      'ollama:qwq:32b': BrandLogos.qwen,
      'nvidia:nvidia/nemotron-3-ultra-550b-a55b': BrandLogos.nvidia,
      'ollama:nemotron-3-nano:30b': BrandLogos.nvidia,
      'openrouter:nvidia/nemotron-3-super-120b-a12b:free': BrandLogos.nvidia,
      'nvidia:z-ai/glm-5.3-flash': BrandLogos.glm,
      'openrouter:thudm/chatglm3-6b': BrandLogos.glm,
      'openrouter:deepseek/deepseek-r1:free': BrandLogos.deepseek,
      'groq:moonshotai/kimi-k2-instruct': BrandLogos.kimi,
      'openrouter:mistralai/mistral-small-3.2': BrandLogos.mistral,
      'ollama:mixtral:8x7b': BrandLogos.mistral,
      'ollama:phi4:14b': BrandLogos.microsoft,
      'nvidia:microsoft/phi-4-mini-instruct': BrandLogos.microsoft,
      // Publisher namespace alone.
      'nvidia:mistralai/codegen-x': BrandLogos.mistral,
      // No provider prefix (telemetry rows carry the provider apart).
      'openai/gpt-oss-120b': BrandLogos.openai,
      'gemma4:31b': BrandLogos.gemma,
    };
    cases.forEach((id, logo) {
      expect(ModelLogos.forModelId(id), logo, reason: id);
    });
  });

  test('unknown families fall back to the provider, then a neutral glyph', () {
    expect(ModelLogos.familyOf('groq:acme/foo-7b'), isNull);
    expect(ModelLogos.forModelId('groq:acme/foo-7b'), BrandLogos.groq);
    expect(ModelLogos.forModelId('ollama:foo:7b'), BrandLogos.ollama);
    expect(
      ModelLogos.forModelId('foo-7b', provider: 'openrouter'),
      BrandLogos.openrouter,
    );
    expect(ModelLogos.forModelId('acme:foo'), AppIcons.models);
    expect(ModelLogos.forModelId(null), AppIcons.models);
    expect(ModelLogos.forModelId(''), AppIcons.models);
    // Names that merely contain a family stay unknown.
    expect(ModelLogos.familyOf('groq:acme/cosmogpt'), isNull);
    expect(ModelLogos.familyOf('groq:acme/sapphire'), isNull);
  });

  test('every backend model id has its family logo', () {
    final ids = _backendModelIds();
    if (ids.isEmpty) return markTestSkipped('backend sources not present');
    expect(ids, containsAll(['ollama:gemma4:31b', 'groq:openai/gpt-oss-120b']));
    for (final id in ids) {
      expect(ModelLogos.familyOf(id), isNotNull, reason: id);
    }
  });
}
