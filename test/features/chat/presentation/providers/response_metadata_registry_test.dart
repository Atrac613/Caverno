import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/presentation/providers/response_metadata_registry.dart';

ChatTurnOwner _owner(String conversationId, int generation) => ChatTurnOwner(
  conversationId: conversationId,
  interactionGeneration: generation,
);

void main() {
  group('ResponseMetadataRegistry', () {
    test('captures and consumes exact metadata once', () {
      final registry = ResponseMetadataRegistry();
      final owner = _owner('conversation-a', 1);
      const metadata = ChatCompletionTerminalMetadata(
        finishReason: 'length',
        usage: TokenUsage(
          promptTokens: 11,
          completionTokens: 7,
          totalTokens: 18,
        ),
      );

      expect(registry.isEmpty, isTrue);
      expect(registry.start(owner), isTrue);
      expect(registry.start(owner), isFalse);
      expect(registry.length, 1);
      expect(registry.owners, {owner});
      expect(registry.contains(owner), isTrue);
      expect(registry.capture(owner, metadata), isTrue);
      expect(registry.metadataFor(owner), same(metadata));

      final metrics = registry.consume(owner)!;
      expect(metrics.promptTokens, 11);
      expect(metrics.completionTokens, 7);
      expect(metrics.totalTokens, 18);
      expect(metrics.finishReason, 'length');
      expect(metrics.elapsedMilliseconds, greaterThanOrEqualTo(0));
      expect(registry.consume(owner), isNull);
      expect(registry.metadataFor(owner), isNull);
      expect(registry.isEmpty, isTrue);
    });

    test('keeps interleaved owner metadata isolated', () {
      final registry = ResponseMetadataRegistry();
      final ownerA = _owner('conversation-a', 4);
      final ownerB = _owner('conversation-b', 9);
      const metadataA = ChatCompletionTerminalMetadata(
        finishReason: 'stop-a',
        usage: TokenUsage(totalTokens: 3),
      );
      const metadataB = ChatCompletionTerminalMetadata(
        finishReason: 'stop-b',
        usage: TokenUsage(totalTokens: 99),
      );

      expect(registry.start(ownerA), isTrue);
      expect(registry.start(ownerB), isTrue);
      expect(registry.capture(ownerB, metadataB), isTrue);
      expect(registry.capture(ownerA, metadataA), isTrue);

      expect(registry.consume(ownerA)!.totalTokens, 3);
      expect(registry.metadataFor(ownerB), same(metadataB));
      expect(registry.consume(ownerB)!.totalTokens, 99);
    });

    test('converts and captures the exact completion result', () async {
      final registry = ResponseMetadataRegistry();
      final owner = _owner('conversation-a', 5);
      final result = ChatCompletionResult(
        content: 'done',
        finishReason: 'length',
        usage: const TokenUsage(
          promptTokens: 13,
          completionTokens: 8,
          totalTokens: 21,
        ),
      );

      final terminal = ResponseMetadataRegistry.terminalMetadataFor(result);
      expect(terminal.finishReason, 'length');
      expect(terminal.usage.totalTokens, 21);
      final streamedTerminal = await registry.terminalFor(Future.value(result));
      expect(streamedTerminal.finishReason, 'length');
      expect(streamedTerminal.usage.totalTokens, 21);

      expect(registry.start(owner), isTrue);
      expect(registry.captureResult(owner, result), isTrue);
      expect(registry.finishReasonFor(owner), 'length');
      expect(registry.consume(owner)!.totalTokens, 21);
    });

    test('terminal conversion preserves completion errors', () async {
      final registry = ResponseMetadataRegistry();
      final error = StateError('completion failed');

      await expectLater(
        registry.terminalFor(Future<ChatCompletionResult>.error(error)),
        throwsA(same(error)),
      );
    });

    test('latest capture wins within one tool-calling response window', () {
      final registry = ResponseMetadataRegistry();
      final owner = _owner('conversation-a', 8);
      expect(registry.start(owner), isTrue);
      expect(
        registry.capture(
          owner,
          const ChatCompletionTerminalMetadata(
            finishReason: 'tool_calls',
            usage: TokenUsage(totalTokens: 14),
          ),
        ),
        isTrue,
      );
      expect(
        registry.capture(
          owner,
          const ChatCompletionTerminalMetadata(
            finishReason: 'stop',
            usage: TokenUsage(totalTokens: 27),
          ),
        ),
        isTrue,
      );

      final metrics = registry.consume(owner)!;
      expect(metrics.finishReason, 'stop');
      expect(metrics.totalTokens, 27);
    });

    test(
      'error discard clears only its owner and permits another response',
      () {
        final registry = ResponseMetadataRegistry();
        final ownerA = _owner('conversation-a', 2);
        final ownerB = _owner('conversation-b', 2);
        expect(registry.start(ownerA), isTrue);
        expect(registry.start(ownerB), isTrue);
        expect(
          registry.capture(
            ownerB,
            const ChatCompletionTerminalMetadata(finishReason: 'stop'),
          ),
          isTrue,
        );

        expect(registry.discard(ownerA), isTrue);
        expect(registry.discard(ownerA), isFalse);
        expect(registry.contains(ownerB), isTrue);
        expect(registry.start(ownerA), isTrue);
        expect(registry.consume(ownerA), isNotNull);
        expect(registry.consume(ownerB)!.finishReason, 'stop');
      },
    );

    test('cancellation dispose rejects late metadata for only its owner', () {
      final registry = ResponseMetadataRegistry();
      final retired = _owner('conversation-a', 3);
      final later = _owner('conversation-a', 4);
      final other = _owner('conversation-b', 1);
      expect(registry.start(retired), isTrue);
      expect(registry.start(other), isTrue);

      expect(registry.dispose(retired), isTrue);
      expect(registry.dispose(retired), isFalse);
      expect(registry.start(retired), isFalse);
      expect(
        registry.capture(
          retired,
          const ChatCompletionTerminalMetadata(finishReason: 'late'),
        ),
        isFalse,
      );
      expect(registry.start(later), isTrue);
      expect(registry.contains(other), isTrue);
      expect(registry.dispose(later), isTrue);
      expect(registry.start(retired), isFalse);
      expect(registry.discard(other), isTrue);
    });

    test('consume without terminal metadata returns timer-only metrics', () {
      final registry = ResponseMetadataRegistry();
      final owner = _owner('conversation-a', 1);
      expect(registry.start(owner), isTrue);

      final metrics = registry.consume(owner)!;
      expect(metrics.promptTokens, 0);
      expect(metrics.completionTokens, 0);
      expect(metrics.totalTokens, 0);
      expect(metrics.finishReason, isNull);
    });
  });
}
