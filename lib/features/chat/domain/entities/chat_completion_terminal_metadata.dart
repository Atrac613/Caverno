/// Token usage reported when a chat completion reaches a terminal state.
final class TokenUsage {
  const TokenUsage({
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.totalTokens = 0,
  });

  final int promptTokens;
  final int completionTokens;
  final int totalTokens;

  static const zero = TokenUsage();
}

/// Request-local metadata captured when a plain content stream terminates.
final class ChatCompletionTerminalMetadata {
  const ChatCompletionTerminalMetadata({
    this.finishReason,
    this.usage = TokenUsage.zero,
  });

  final String? finishReason;
  final TokenUsage usage;

  static const empty = ChatCompletionTerminalMetadata();
}
