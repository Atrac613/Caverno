/// Token usage reported when a chat completion reaches a terminal state.
///
/// Mirrors the full `Usage` payload of the OpenAI-compatible API, including the
/// `prompt_tokens_details` / `completion_tokens_details` breakdowns. Providers
/// that omit those objects (local llama.cpp, for one) leave the detail fields
/// at 0, so 0 means "not reported" rather than "measured as zero".
final class TokenUsage {
  const TokenUsage({
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.totalTokens = 0,
    this.cachedPromptTokens = 0,
    this.audioPromptTokens = 0,
    this.reasoningTokens = 0,
    this.audioCompletionTokens = 0,
    this.acceptedPredictionTokens = 0,
    this.rejectedPredictionTokens = 0,
  });

  final int promptTokens;
  final int completionTokens;
  final int totalTokens;

  /// Prompt tokens served from the provider's prompt cache.
  final int cachedPromptTokens;

  /// Audio tokens in the prompt.
  final int audioPromptTokens;

  /// Reasoning tokens billed as part of the completion.
  final int reasoningTokens;

  /// Audio tokens in the completion.
  final int audioCompletionTokens;

  /// Predicted-output tokens the model accepted.
  final int acceptedPredictionTokens;

  /// Predicted-output tokens the model rejected (still billed).
  final int rejectedPredictionTokens;

  /// True when the provider reported a prompt-token breakdown.
  bool get hasPromptDetails => cachedPromptTokens > 0 || audioPromptTokens > 0;

  /// True when the provider reported a completion-token breakdown.
  bool get hasCompletionDetails =>
      reasoningTokens > 0 ||
      audioCompletionTokens > 0 ||
      acceptedPredictionTokens > 0 ||
      rejectedPredictionTokens > 0;

  static const zero = TokenUsage();
}
