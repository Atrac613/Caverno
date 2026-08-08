import 'token_usage.dart';

export 'token_usage.dart';

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
