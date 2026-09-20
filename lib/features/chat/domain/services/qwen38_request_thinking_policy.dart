import '../entities/model_usage_role.dart';

/// Applies explicit template thinking preferences and Qwen3.8 defaults.
final class Qwen38RequestThinkingPolicy {
  const Qwen38RequestThinkingPolicy({
    this.reasoningEffort,
    this.enableThinking,
    this.acceptsChatTemplateKwargs = false,
  });

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

  /// Null preserves the model-specific automatic behavior.
  final bool? enableThinking;

  /// Whether the endpoint was marked as accepting `chat_template_kwargs`
  /// (`LlmEndpoint.chatTemplateKwargsEnabled`).
  ///
  /// This, and the role, are the whole of the suppression decision -- the model
  /// name is not consulted. Only the reasoning-effort mapping stays behind
  /// [isQwen38Model], because those branches encode one template's vocabulary
  /// and would be wrong to apply to a family that does not share it.
  final bool acceptsChatTemplateKwargs;

  static bool suppressesThinking(ModelUsageRole role) =>
      _structuredUtilityRoles.contains(role);

  /// Whether [model] is a Qwen3.8 build this policy governs.
  ///
  /// Matched by family, because the exact-name equality this replaces
  /// (`model == ApiConstants.qwen38VisionModel`) switched the whole policy off
  /// for every other Qwen3.8 build -- including the suppression above, which is
  /// a fact about the request rather than about the model name. A local
  /// llama.cpp serving `Qwen3.8-Flash-Next-Q2` got no `enable_thinking: false`
  /// on any utility call: observed 2026-09-17, where a 400-token
  /// `goalSuggestion` spent all 400 reasoning, hit `finish=length` inside an
  /// unclosed think block, and returned nothing usable after 21s. The same
  /// endpoint's memory extraction was fine only because it happened to be
  /// pinned to the one model name this compared against.
  ///
  /// Kept only for the reasoning-effort mapping. Suppression no longer asks:
  /// see [acceptsChatTemplateKwargs].
  ///
  /// The prefix stays narrow on purpose: `chat_template_kwargs` is a llama.cpp
  /// template control, and a hosted endpoint that has never heard of it must
  /// keep receiving requests without it.
  static bool isQwen38Model(String model) =>
      model.trim().toLowerCase().startsWith('qwen3.8');

  Qwen38RequestOverrides? resolve({
    required String model,
    required int? maxTokens,
    ModelUsageRole role = ModelUsageRole.unknown,
  }) {
    // Role-based suppression, decided without reference to the model.
    //
    // The role says the answer is machine-parsed JSON on a small budget, which
    // is true of that request whatever is serving it; the endpoint's opt-in
    // says only whether the field may go on the wire. No model name takes part,
    // so a family this policy has never heard of gets the same suppression as
    // the one it is named after. `reasoning_effort` is dropped with it, because
    // a call that must not reason should not be carrying an effort either.
    if (acceptsChatTemplateKwargs && suppressesThinking(role)) {
      return Qwen38RequestOverrides(
        maxTokens: maxTokens,
        chatTemplateKwargs: const {'enable_thinking': false},
      );
    }

    if (!isQwen38Model(model)) {
      // An explicit enableThinking is the person's own instruction, so it is
      // honoured on any model, as it was before the opt-in existed.
      return enableThinking == null
          ? null
          : Qwen38RequestOverrides(
              maxTokens: maxTokens,
              chatTemplateKwargs: {'enable_thinking': enableThinking!},
              preserveReasoningEffort: true,
            );
    }

    if (enableThinking == false) {
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
        chatTemplateKwargs: {'enable_thinking': enableThinking ?? false},
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
    this.preserveReasoningEffort = false,
  });

  final bool preserveReasoningEffort;
  final int? maxTokens;
  final Map<String, dynamic> chatTemplateKwargs;

  Map<String, dynamic> applyTo(Map<String, dynamic> body) {
    final result = Map<String, dynamic>.of(body)..remove('max_tokens');
    if (maxTokens != null) {
      result['max_tokens'] = maxTokens;
    }
    if (!preserveReasoningEffort) result.remove('reasoning_effort');
    result['chat_template_kwargs'] = {
      if (body['chat_template_kwargs'] is Map)
        ...Map<String, dynamic>.from(body['chat_template_kwargs'] as Map),
      ...chatTemplateKwargs,
    };
    return result;
  }
}
