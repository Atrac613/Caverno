import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/presentation/providers/active_response_registry.dart';

void main() {
  group('ActiveResponseRegistry', () {
    test('registers a response and mirrors the current generation', () {
      final registry = ActiveResponseRegistry();
      final generation = registry.beginGeneration();
      final messages = [_message('user-1', MessageRole.user)];

      registry.register(
        generation: generation,
        targetConversationId: 'conversation-a',
        messages: messages,
      );

      expect(registry.currentGeneration, generation);
      expect(registry.currentConversationId, 'conversation-a');
      expect(registry.currentMessages, messages);
      expect(
        registry.conversationIdForGeneration(generation),
        'conversation-a',
      );
      expect(registry.messagesForGeneration(generation), messages);
      expect(
        registry.isDetached(visibleConversationId: 'conversation-b'),
        isTrue,
      );
    });

    test('keeps the current mirror until another generation registers', () {
      final registry = ActiveResponseRegistry();
      final firstGeneration = registry.beginGeneration();
      registry.register(
        generation: firstGeneration,
        targetConversationId: 'conversation-a',
        messages: [_message('first', MessageRole.assistant)],
      );

      final secondGeneration = registry.beginGeneration();

      expect(registry.currentGeneration, secondGeneration);
      expect(
        registry.conversationIdForGeneration(firstGeneration),
        'conversation-a',
      );
      expect(
        registry.conversationIdForGeneration(secondGeneration),
        'conversation-a',
      );
    });

    test('returns the newest generation for a conversation', () {
      final registry = ActiveResponseRegistry();
      final firstGeneration = registry.beginGeneration();
      registry.register(
        generation: firstGeneration,
        targetConversationId: 'conversation-a',
        messages: [_message('first', MessageRole.assistant)],
      );
      final secondGeneration = registry.beginGeneration();
      registry.register(
        generation: secondGeneration,
        targetConversationId: 'conversation-a',
        messages: [_message('second', MessageRole.assistant)],
      );

      expect(
        registry.generationForConversation('conversation-a'),
        secondGeneration,
      );
    });

    test('clears current and generation-keyed entries independently', () {
      final registry = ActiveResponseRegistry();
      final firstGeneration = registry.beginGeneration();
      registry.register(
        generation: firstGeneration,
        targetConversationId: 'conversation-a',
        messages: [_message('first', MessageRole.assistant)],
      );
      final secondGeneration = registry.beginGeneration();
      registry.register(
        generation: secondGeneration,
        targetConversationId: 'conversation-b',
        messages: [_message('second', MessageRole.assistant)],
      );

      registry.clearGeneration(firstGeneration);

      expect(registry.generationForConversation('conversation-a'), isNull);
      expect(registry.currentConversationId, 'conversation-b');

      registry.clearGeneration(secondGeneration);

      expect(registry.currentConversationId, isNull);
      expect(registry.hasActiveResponse, isFalse);
    });

    test('ignores cache updates for unknown generations', () {
      final registry = ActiveResponseRegistry();

      registry.cacheMessages(42, [_message('orphan', MessageRole.assistant)]);

      expect(registry.messagesForGeneration(42), isNull);
      expect(registry.hasActiveResponse, isFalse);
    });
  });
}

Message _message(String id, MessageRole role) {
  return Message(id: id, content: id, role: role, timestamp: DateTime(2026));
}
