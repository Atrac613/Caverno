import '../../../../core/constants/api_constants.dart';

/// Wire-level request overrides for Qwen3.8's llama.cpp chat template.
final class Qwen38RequestThinkingPolicy {
  const Qwen38RequestThinkingPolicy({this.reasoningEffort});

  static const int mediumMinimumMaxTokens = 1536;

  final String? reasoningEffort;

  Qwen38RequestOverrides? resolve({
    required String model,
    required int? maxTokens,
  }) {
    if (model.trim() != ApiConstants.qwen38VisionModel) {
      return null;
    }

    final normalizedEffort = reasoningEffort?.trim().toLowerCase();
    return switch (normalizedEffort) {
      'low' => Qwen38RequestOverrides(
        maxTokens: maxTokens,
        chatTemplateKwargs: const {
          'enable_thinking': true,
          'reasoning_effort': 'low',
        },
      ),
      'medium' || 'high' => Qwen38RequestOverrides(
        maxTokens: _atLeastMediumBudget(maxTokens),
        chatTemplateKwargs: const {
          'enable_thinking': true,
          'reasoning_effort': 'medium',
        },
      ),
      _ => Qwen38RequestOverrides(
        maxTokens: maxTokens,
        chatTemplateKwargs: const {'enable_thinking': false},
      ),
    };
  }

  static int _atLeastMediumBudget(int? maxTokens) {
    if (maxTokens == null || maxTokens < mediumMinimumMaxTokens) {
      return mediumMinimumMaxTokens;
    }
    return maxTokens;
  }
}

final class Qwen38RequestOverrides {
  const Qwen38RequestOverrides({
    required this.maxTokens,
    required this.chatTemplateKwargs,
  });

  final int? maxTokens;
  final Map<String, dynamic> chatTemplateKwargs;

  Map<String, dynamic> applyTo(Map<String, dynamic> body) {
    final result = Map<String, dynamic>.of(body)
      ..remove('reasoning_effort')
      ..remove('max_tokens');
    if (maxTokens != null) {
      result['max_tokens'] = maxTokens;
    }
    result['chat_template_kwargs'] = chatTemplateKwargs;
    return result;
  }
}
