import '../../../../core/constants/api_constants.dart';
import '../entities/model_usage_role.dart';

/// Wire-level request overrides for Qwen3.8's llama.cpp chat template.
final class Qwen38RequestThinkingPolicy {
  const Qwen38RequestThinkingPolicy({this.reasoningEffort});

  static const int mediumMinimumMaxTokens = 1536;

  /// Roles whose answer is a machine-parsed JSON payload sent under a small
  /// utility budget ([SecondaryCallBudget]), not prose for the user.
  ///
  /// These must not think. Session d904b342 routed memory extraction to this
  /// model with the chat `reasoningEffort` of the moment: the medium branch
  /// raised the 1200-token budget to 1536, the model spent 2200-3800 characters
  /// of it reasoning, and 4 of 10 extractions were cut off mid-JSON — full
  /// latency (49-204s each, 977s of the session's wall clock), zero memory
  /// written. The JSON itself needs ~700 tokens, so the budget was never the
  /// problem; thinking inside it was.
  static const Set<ModelUsageRole> _structuredUtilityRoles = {
    ModelUsageRole.memoryExtraction,
    ModelUsageRole.approvalAutoReview,
    ModelUsageRole.goalSuggestion,
  };

  final String? reasoningEffort;

  static bool suppressesThinking(ModelUsageRole role) =>
      _structuredUtilityRoles.contains(role);

  Qwen38RequestOverrides? resolve({
    required String model,
    required int? maxTokens,
    ModelUsageRole role = ModelUsageRole.unknown,
  }) {
    if (model.trim() != ApiConstants.qwen38VisionModel) {
      return null;
    }

    if (suppressesThinking(role)) {
      return Qwen38RequestOverrides(
        maxTokens: maxTokens,
        chatTemplateKwargs: const {'enable_thinking': false},
      );
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
