import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/presentation/providers/active_response_registry.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';

void main() {
  group('chatStateReportsConversationBusy', () {
    ChatState stateWith({
      Set<String> busy = const <String>{},
      bool isLoading = false,
      bool isGeneratingTaskProposal = false,
    }) {
      return ChatState.initial().copyWith(
        busyConversationIds: busy,
        isLoading: isLoading,
        isGeneratingTaskProposal: isGeneratingTaskProposal,
      );
    }

    test('a background thread stays busy while it is registered', () {
      expect(
        chatStateReportsConversationBusy(
          state: stateWith(busy: {'conversation-b'}),
          targetConversationId: 'conversation-b',
          visibleConversationId: 'conversation-a',
        ),
        isTrue,
      );
    });

    test('clearing the registry mirror stops the spinner', () {
      expect(
        chatStateReportsConversationBusy(
          state: stateWith(),
          targetConversationId: 'conversation-b',
          visibleConversationId: 'conversation-a',
        ),
        isFalse,
        reason:
            'a finished background thread must not keep animating once its '
            'entry left the state',
      );
    });

    test('the visible thread is busy while a plan proposal is drafting', () {
      expect(
        chatStateReportsConversationBusy(
          state: stateWith(isGeneratingTaskProposal: true),
          targetConversationId: 'conversation-a',
          visibleConversationId: 'conversation-a',
        ),
        isTrue,
        reason: 'plan drafting runs without registering an active response',
      );
    });

    test('an idle visible thread is not busy', () {
      expect(
        chatStateReportsConversationBusy(
          state: stateWith(),
          targetConversationId: 'conversation-a',
          visibleConversationId: 'conversation-a',
        ),
        isFalse,
      );
    });

    test('an empty id is never busy', () {
      expect(
        chatStateReportsConversationBusy(
          state: stateWith(busy: {'conversation-a'}, isLoading: true),
          targetConversationId: '   ',
          visibleConversationId: 'conversation-a',
        ),
        isFalse,
      );
    });
  });

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

    test('a released turn leaves no open registration behind', () {
      // The lifecycle gate: a registration outliving its turn is what a thread
      // switch shows instead of the persisted transcript, and what the
      // thread's spinner is derived from, so the thread is stranded until the
      // app restarts. Two threads running at once must both come back to zero.
      final registry = ActiveResponseRegistry();
      final first = registry.beginGeneration();
      registry.register(
        generation: first,
        targetConversationId: 'conversation-a',
        messages: [_message('a', MessageRole.user)],
      );
      final second = registry.beginGeneration();
      registry.register(
        generation: second,
        targetConversationId: 'conversation-b',
        messages: [_message('b', MessageRole.user)],
      );

      expect(registry.openRegistrationCount, 2);

      registry.clearGeneration(first);
      registry.clearGeneration(second);

      expect(registry.openRegistrationCount, isZero);
      expect(registry.activeConversationIds, isEmpty);
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
