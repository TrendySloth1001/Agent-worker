import 'package:app/core/models/model_names.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('readable names from raw model ids', () {
    expect(
      prettyModelName('meta-llama/llama-4-scout-17b-16e-instruct'),
      'Llama 4 Scout 17B',
    );
    expect(prettyModelName('llama-3.3-70b-versatile'), 'Llama 3.3 70B');
    expect(prettyModelName('openai/gpt-oss-120b'), 'GPT OSS 120B');
    expect(prettyModelName('qwen/qwen3-32b'), 'Qwen3 32B');
    expect(prettyModelName('gemma3:27b'), 'Gemma3');
    expect(prettyModelName('deepseek-r1:free'), 'DeepSeek R1');
    expect(
      prettyModelName('meta/llama-3.2-11b-vision-instruct'),
      'Llama 3.2 11B Vision',
    );
    expect(prettyModelName('z-ai/glm-4.5-air:free'), 'GLM 4.5 Air');
    expect(
      prettyModelName('nvidia/nemotron-3-super-2025-09-30'),
      'Nemotron 3 Super',
    );
  });

  test('never a raw id, empty for nothing', () {
    expect(prettyModelName(''), '');
    for (final id in ['a/b-c', 'x/y-instruct', 'org/model:free']) {
      final n = prettyModelName(id);
      expect(n.contains('/'), isFalse);
      expect(n.contains(':'), isFalse);
    }
  });
}
