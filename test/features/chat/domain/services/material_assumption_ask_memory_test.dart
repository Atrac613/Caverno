import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/services/material_assumption_ask_memory.dart';
import 'package:test/test.dart';

ChatTurnOwner _owner(String conversationId, int generation) => ChatTurnOwner(
  conversationId: conversationId,
  interactionGeneration: generation,
);

const _itemId = 'constraint:cf71bf56';

void main() {
  group('one turn remembers what it asked', () {
    test('a scope handed out twice is the same scope', () {
      final memory = MaterialAssumptionAskMemory();
      final owner = _owner('conv-a', 1);

      memory.scopeFor(owner).markAsked(_itemId);

      expect(
        memory.scopeFor(owner).hasAsked(_itemId),
        isTrue,
        reason:
            'The tool loop asks for the scope once per iteration, so two '
            'lookups inside one turn must not produce two memories.',
      );
    });

    test('an item nobody asked about is not remembered', () {
      final memory = MaterialAssumptionAskMemory();

      expect(memory.scopeFor(_owner('conv-a', 1)).hasAsked(_itemId), isFalse);
    });
  });

  group('nothing crosses a turn or a thread', () {
    test('the next turn in the same conversation asks again', () {
      final memory = MaterialAssumptionAskMemory();
      memory.scopeFor(_owner('conv-a', 1)).markAsked(_itemId);

      expect(
        memory.scopeFor(_owner('conv-a', 2)).hasAsked(_itemId),
        isFalse,
        reason:
            'A dismissal is scoped to the turn it was made in; going back to '
            'one belongs to a persistent surface, not to a silent carry-over.',
      );
    });

    test('a concurrent thread keeps its own memory', () {
      final memory = MaterialAssumptionAskMemory();
      memory.scopeFor(_owner('conv-a', 1)).markAsked(_itemId);

      expect(
        memory.scopeFor(_owner('conv-b', 1)).hasAsked(_itemId),
        isFalse,
        reason:
            'Two threads share an interaction generation counter; keying on '
            'it alone would let one thread answer for another.',
      );
    });
  });

  group('teardown', () {
    test('removing an owner forgets only that turn', () {
      final memory = MaterialAssumptionAskMemory();
      final kept = _owner('conv-b', 1);
      memory.scopeFor(_owner('conv-a', 1)).markAsked(_itemId);
      memory.scopeFor(kept).markAsked(_itemId);

      expect(memory.removeOwner(_owner('conv-a', 1)), isTrue);
      expect(memory.scopeFor(_owner('conv-a', 1)).hasAsked(_itemId), isFalse);
      expect(memory.scopeFor(kept).hasAsked(_itemId), isTrue);
    });

    test('removing an owner that never asked reports nothing removed', () {
      expect(
        MaterialAssumptionAskMemory().removeOwner(_owner('conv-a', 1)),
        isFalse,
      );
    });

    test('clearing a conversation drops every turn it owns', () {
      final memory = MaterialAssumptionAskMemory();
      final other = _owner('conv-b', 1);
      memory.scopeFor(_owner('conv-a', 1)).markAsked(_itemId);
      memory.scopeFor(_owner('conv-a', 2)).markAsked(_itemId);
      memory.scopeFor(other).markAsked(_itemId);

      memory.clearConversation('conv-a');

      expect(memory.scopeFor(_owner('conv-a', 1)).hasAsked(_itemId), isFalse);
      expect(memory.scopeFor(_owner('conv-a', 2)).hasAsked(_itemId), isFalse);
      expect(memory.scopeFor(other).hasAsked(_itemId), isTrue);
    });

    test('clear drops everything', () {
      final memory = MaterialAssumptionAskMemory();
      memory.scopeFor(_owner('conv-a', 1)).markAsked(_itemId);
      memory.scopeFor(_owner('conv-b', 1)).markAsked(_itemId);

      memory.clear();

      expect(memory.scopeFor(_owner('conv-a', 1)).hasAsked(_itemId), isFalse);
      expect(memory.scopeFor(_owner('conv-b', 1)).hasAsked(_itemId), isFalse);
    });
  });
}
