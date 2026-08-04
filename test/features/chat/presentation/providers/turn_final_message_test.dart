import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/presentation/providers/turn_final_message.dart';
import 'package:test/test.dart';

void main() {
  group('TurnFinalMessage.resolve', () {
    test('keeps visible assistant text', () {
      final result = TurnFinalMessage.resolve(
        lastMessage: _assistant('Visible response'),
        contentToolFallback: 'fallback',
      );

      expect(result.useContentToolFallback, isFalse);
      expect(result.dropLastAssistant, isFalse);
    });

    test('uses a fallback for a bare memory update', () {
      final result = TurnFinalMessage.resolve(
        lastMessage: _assistant(
          '<tool_use>{"name":"memory_update","status":"updated"}</tool_use>',
        ),
        contentToolFallback: 'Recovered response',
      );

      expect(result.useContentToolFallback, isTrue);
      expect(result.dropLastAssistant, isFalse);
      expect(result.fallbackContent, 'Recovered response');
    });

    test('keeps a non-memory tool call as visible content', () {
      final result = TurnFinalMessage.resolve(
        lastMessage: _assistant(
          '<tool_call>{"name":"read_file","arguments":{}}</tool_call>',
        ),
        contentToolFallback: null,
      );

      expect(result.useContentToolFallback, isFalse);
      expect(result.dropLastAssistant, isFalse);
    });

    test('drops an empty assistant when no fallback exists', () {
      final result = TurnFinalMessage.resolve(
        lastMessage: _assistant('  '),
        contentToolFallback: null,
      );

      expect(result.useContentToolFallback, isFalse);
      expect(result.dropLastAssistant, isTrue);
    });

    test('does not drop an empty user message', () {
      final result = TurnFinalMessage.resolve(
        lastMessage: _message('', MessageRole.user),
        contentToolFallback: null,
      );

      expect(result.useContentToolFallback, isFalse);
      expect(result.dropLastAssistant, isFalse);
    });
  });
}

Message _assistant(String content) => _message(content, MessageRole.assistant);

Message _message(String content, MessageRole role) => Message(
  id: 'message-1',
  content: content,
  role: role,
  timestamp: DateTime.utc(2026),
);
