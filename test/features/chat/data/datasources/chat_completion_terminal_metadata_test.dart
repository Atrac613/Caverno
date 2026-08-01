import 'package:caverno/features/chat/domain/entities/chat_completion_terminal_metadata.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('TokenUsage exposes zero defaults and exact counts', () {
    expect(TokenUsage.zero.promptTokens, 0);
    expect(TokenUsage.zero.completionTokens, 0);
    expect(TokenUsage.zero.totalTokens, 0);

    const usage = TokenUsage(
      promptTokens: 3,
      completionTokens: 5,
      totalTokens: 8,
    );
    expect(usage.promptTokens, 3);
    expect(usage.completionTokens, 5);
    expect(usage.totalTokens, 8);
  });

  test('terminal metadata exposes empty defaults and exact response facts', () {
    expect(ChatCompletionTerminalMetadata.empty.finishReason, isNull);
    expect(ChatCompletionTerminalMetadata.empty.usage, same(TokenUsage.zero));

    const metadata = ChatCompletionTerminalMetadata(
      finishReason: 'length',
      usage: TokenUsage(
        promptTokens: 13,
        completionTokens: 21,
        totalTokens: 34,
      ),
    );
    expect(metadata.finishReason, 'length');
    expect(metadata.usage.promptTokens, 13);
    expect(metadata.usage.completionTokens, 21);
    expect(metadata.usage.totalTokens, 34);
  });
}
