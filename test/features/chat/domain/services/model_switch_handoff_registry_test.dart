import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/services/model_switch_handoff_registry.dart';
import 'package:test/test.dart';

void main() {
  group('ModelSwitchHandoffRegistry', () {
    late DateTime now;
    late int clockCalls;
    late ModelSwitchHandoffRegistry registry;

    setUp(() {
      now = DateTime.utc(2026, 7, 31, 8, 30);
      clockCalls = 0;
      registry = ModelSwitchHandoffRegistry(
        clock: () {
          clockCalls += 1;
          return now;
        },
      );
    });

    test('does not retain a handoff when the builder has no context', () {
      final conversation = _conversation(
        id: 'empty',
        title: ' ',
        withGoal: false,
      );

      final brief = registry.schedule(
        conversation: conversation,
        messages: const [],
        previousModel: 'old-model',
        nextModel: 'new-model',
      );

      expect(brief, isNull);
      expect(registry.hasPendingFor('empty'), isFalse);
      expect(registry.take(_owner('empty', 1)), isNull);
    });

    test('a missing owner never creates or clears a pending handoff', () {
      final ownerBrief = registry.schedule(
        conversation: _conversation(id: 'owner-a'),
        messages: [_message('Owner A context')],
        previousModel: 'old-model',
        nextModel: 'new-model',
      );

      final unownedBrief = registry.schedule(
        conversation: null,
        messages: [_message('Unowned visible context')],
        previousModel: 'new-model',
        nextModel: 'newer-model',
      );

      expect(unownedBrief, isNull);
      expect(registry.hasPendingFor('owner-a'), isTrue);
      expect(registry.take(_owner('visible-b', 1)), isNull);
      expect(registry.take(_owner('owner-a', 1)), ownerBrief);
    });

    test('schedules and consumes a handoff exactly once', () {
      final brief = registry.schedule(
        conversation: _conversation(id: 'owner-a'),
        messages: [_message('Recent work')],
        previousModel: 'old-model',
        nextModel: 'new-model',
      );

      expect(brief, isNotNull);
      expect(registry.hasPendingFor('owner-a'), isTrue);
      expect(registry.take(_owner('owner-a', 7)), brief);
      expect(registry.hasPendingFor('owner-a'), isFalse);
      expect(registry.take(_owner('owner-a', 8)), isNull);
    });

    test('a different conversation cannot consume the pending handoff', () {
      final brief = registry.schedule(
        conversation: _conversation(id: 'owner-a'),
        messages: [_message('Owner A context')],
        previousModel: 'old-model',
        nextModel: 'new-model',
      );

      expect(registry.take(_owner('visible-b', 1)), isNull);
      expect(registry.hasPendingFor('owner-a'), isTrue);
      expect(registry.take(_owner('owner-a', 2)), brief);
    });

    test('rescheduling replaces only the same conversation handoff', () {
      registry.schedule(
        conversation: _conversation(id: 'owner-a'),
        messages: [_message('First owner A context')],
        previousModel: 'old-a',
        nextModel: 'new-a',
      );
      final ownerBBrief = registry.schedule(
        conversation: _conversation(id: 'owner-b'),
        messages: [_message('Owner B context')],
        previousModel: 'old-b',
        nextModel: 'new-b',
      );
      final replacement = registry.schedule(
        conversation: _conversation(id: 'owner-a'),
        messages: [_message('Replacement owner A context')],
        previousModel: 'new-a',
        nextModel: 'newer-a',
      );

      expect(registry.take(_owner('owner-a', 3)), replacement);
      expect(registry.take(_owner('owner-b', 4)), ownerBBrief);
    });

    test('a no-context reschedule clears only its conversation', () {
      registry.schedule(
        conversation: _conversation(id: 'owner-a'),
        messages: [_message('Owner A context')],
        previousModel: 'old-a',
        nextModel: 'new-a',
      );
      final ownerBBrief = registry.schedule(
        conversation: _conversation(id: 'owner-b'),
        messages: [_message('Owner B context')],
        previousModel: 'old-b',
        nextModel: 'new-b',
      );
      registry.requestPromptCompaction(_owner('owner-a', 1));

      registry.schedule(
        conversation: _conversation(id: 'owner-a', title: ' ', withGoal: false),
        messages: const [],
        previousModel: 'new-a',
        nextModel: 'newer-a',
      );

      expect(registry.take(_owner('owner-a', 1)), isNull);
      expect(registry.take(_owner('owner-b', 1)), ownerBBrief);
      expect(
        registry.consumePromptCompaction(
          owner: _owner('owner-a', 1),
          forceCompaction: false,
          hasModelSwitchHandoff: false,
        ),
        isTrue,
      );
    });

    test('clearPendingHandoff clears only that conversation handoff', () {
      registry.schedule(
        conversation: _conversation(id: 'owner-a'),
        messages: [_message('Owner A context')],
        previousModel: 'old-a',
        nextModel: 'new-a',
      );
      final ownerBBrief = registry.schedule(
        conversation: _conversation(id: 'owner-b'),
        messages: [_message('Owner B context')],
        previousModel: 'old-b',
        nextModel: 'new-b',
      );
      registry.requestPromptCompaction(_owner('owner-a', 1));
      registry.requestPromptCompaction(_owner('owner-b', 1));

      registry.clearPendingHandoff('owner-a');

      expect(registry.take(_owner('owner-a', 2)), isNull);
      expect(
        registry.consumePromptCompaction(
          owner: _owner('owner-a', 1),
          forceCompaction: false,
          hasModelSwitchHandoff: false,
        ),
        isTrue,
      );
      expect(registry.take(_owner('owner-b', 2)), ownerBBrief);
      expect(
        registry.consumePromptCompaction(
          owner: _owner('owner-b', 1),
          forceCompaction: false,
          hasModelSwitchHandoff: false,
        ),
        isTrue,
      );
    });

    test('discardPromptCompaction clears only the exact owner generation', () {
      final ownerA1 = _owner('owner-a', 1);
      final ownerA2 = _owner('owner-a', 2);
      final ownerB1 = _owner('owner-b', 1);
      final ownerABrief = registry.schedule(
        conversation: _conversation(id: 'owner-a'),
        messages: [_message('Owner A context')],
        previousModel: 'old-a',
        nextModel: 'new-a',
      );
      registry.requestPromptCompaction(ownerA1);
      registry.requestPromptCompaction(ownerA2);
      registry.requestPromptCompaction(ownerB1);

      expect(registry.discardPromptCompaction(ownerA1), isTrue);
      expect(registry.discardPromptCompaction(ownerA1), isFalse);
      expect(registry.take(ownerA2), ownerABrief);
      expect(
        registry.consumePromptCompaction(
          owner: ownerA1,
          forceCompaction: false,
          hasModelSwitchHandoff: false,
        ),
        isFalse,
      );
      expect(
        registry.consumePromptCompaction(
          owner: ownerA2,
          forceCompaction: false,
          hasModelSwitchHandoff: false,
        ),
        isTrue,
      );
      expect(
        registry.consumePromptCompaction(
          owner: ownerB1,
          forceCompaction: false,
          hasModelSwitchHandoff: false,
        ),
        isTrue,
      );
    });

    test('clearPromptCompactions preserves pending handoffs', () {
      final owner = _owner('owner-a', 1);
      final brief = registry.schedule(
        conversation: _conversation(id: 'owner-a'),
        messages: [_message('Owner A context')],
        previousModel: 'old-a',
        nextModel: 'new-a',
      );
      registry.requestPromptCompaction(owner);

      registry.clearPromptCompactions();

      expect(
        registry.consumePromptCompaction(
          owner: owner,
          forceCompaction: false,
          hasModelSwitchHandoff: false,
        ),
        isFalse,
      );
      expect(registry.take(owner), brief);
    });

    test('clearPendingHandoffs preserves compaction requests', () {
      final ownerA = _owner('owner-a', 1);
      final ownerB = _owner('owner-b', 1);
      for (final conversationId in ['owner-a', 'owner-b']) {
        registry.schedule(
          conversation: _conversation(id: conversationId),
          messages: [_message('$conversationId context')],
          previousModel: 'old-model',
          nextModel: 'new-model',
        );
      }
      registry.requestPromptCompaction(ownerA);

      registry.clearPendingHandoffs();

      expect(registry.take(ownerA), isNull);
      expect(registry.take(ownerB), isNull);
      expect(
        registry.consumePromptCompaction(
          owner: ownerA,
          forceCompaction: false,
          hasModelSwitchHandoff: false,
        ),
        isTrue,
      );
    });

    test('clearAll removes handoffs and owner compaction requests', () {
      registry.schedule(
        conversation: _conversation(id: 'owner-a'),
        messages: [_message('Owner A context')],
        previousModel: 'old-a',
        nextModel: 'new-a',
      );
      registry.requestPromptCompaction(_owner('owner-a', 1));

      registry.clearAll();

      expect(registry.take(_owner('owner-a', 1)), isNull);
      expect(
        registry.consumePromptCompaction(
          owner: _owner('owner-a', 1),
          forceCompaction: false,
          hasModelSwitchHandoff: false,
        ),
        isFalse,
      );
    });

    test('owner compaction requests are generation scoped and one-shot', () {
      final requestedOwner = _owner('owner-a', 3);
      expect(registry.requestPromptCompaction(requestedOwner), isTrue);
      expect(registry.requestPromptCompaction(requestedOwner), isFalse);

      expect(
        registry.consumePromptCompaction(
          owner: _owner('owner-a', 4),
          forceCompaction: false,
          hasModelSwitchHandoff: false,
        ),
        isFalse,
      );
      expect(
        registry.consumePromptCompaction(
          owner: requestedOwner,
          forceCompaction: false,
          hasModelSwitchHandoff: false,
        ),
        isTrue,
      );
      expect(
        registry.consumePromptCompaction(
          owner: requestedOwner,
          forceCompaction: false,
          hasModelSwitchHandoff: false,
        ),
        isFalse,
      );
    });

    test('explicit forcing preserves a queued generation request', () {
      final owner = _owner('owner-a', 5);
      final unqueuedOwner = _owner('owner-b', 5);
      registry.requestPromptCompaction(owner);

      expect(
        registry.consumePromptCompaction(
          owner: owner,
          forceCompaction: true,
          hasModelSwitchHandoff: false,
        ),
        isTrue,
      );
      expect(
        registry.consumePromptCompaction(
          owner: owner,
          forceCompaction: false,
          hasModelSwitchHandoff: false,
        ),
        isTrue,
      );
      expect(
        registry.consumePromptCompaction(
          owner: unqueuedOwner,
          forceCompaction: true,
          hasModelSwitchHandoff: false,
        ),
        isTrue,
      );
      expect(
        registry.consumePromptCompaction(
          owner: unqueuedOwner,
          forceCompaction: false,
          hasModelSwitchHandoff: false,
        ),
        isFalse,
      );
    });

    test('a model handoff forces compaction without retaining a flag', () {
      final owner = _owner('owner-a', 6);

      expect(
        registry.consumePromptCompaction(
          owner: owner,
          forceCompaction: false,
          hasModelSwitchHandoff: true,
        ),
        isTrue,
      );
      expect(
        registry.consumePromptCompaction(
          owner: owner,
          forceCompaction: false,
          hasModelSwitchHandoff: false,
        ),
        isFalse,
      );
    });

    test('creates the exact timestamped system handoff message', () {
      final message = registry.createPromptMessage('Preserve this context.');

      expect(
        message,
        Message(
          id: 'system_model_handoff',
          content: 'Preserve this context.',
          role: MessageRole.system,
          timestamp: now,
        ),
      );
      expect(clockCalls, 1);
    });

    test('does not read the clock when no handoff message is needed', () {
      expect(registry.createPromptMessage(null), isNull);
      expect(clockCalls, 0);
    });

    test('builds from an immutable snapshot of the message collection', () {
      final messages = [_message('Snapshot content')];

      final brief = registry.schedule(
        conversation: _conversation(id: 'owner-a'),
        messages: messages,
        previousModel: 'old-model',
        nextModel: 'new-model',
      );
      messages
        ..clear()
        ..add(_message('Later visible-thread content'));

      expect(brief, contains('Snapshot content'));
      expect(brief, isNot(contains('Later visible-thread content')));
      expect(registry.take(_owner('owner-a', 1)), brief);
    });
  });
}

Conversation _conversation({
  required String id,
  String title = 'Model switch work',
  bool withGoal = true,
}) {
  final timestamp = DateTime.utc(2026, 7, 31);
  return Conversation(
    id: id,
    title: title,
    messages: const [],
    createdAt: timestamp,
    updatedAt: timestamp,
    workspaceMode: WorkspaceMode.coding,
    goal: withGoal
        ? ConversationGoal(
            id: 'goal-$id',
            objective: 'Continue work for $id',
            createdAt: timestamp,
            updatedAt: timestamp,
          )
        : null,
  );
}

Message _message(String content) => Message(
  id: 'message-${content.hashCode}',
  content: content,
  role: MessageRole.user,
  timestamp: DateTime.utc(2026, 7, 31),
);

ChatTurnOwner _owner(String conversationId, int generation) => ChatTurnOwner(
  conversationId: conversationId,
  interactionGeneration: generation,
);
