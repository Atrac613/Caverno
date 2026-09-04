import 'dart:async';

import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:caverno/features/chat/presentation/providers/thread_scoped_chat_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// ANA0 PR 4: the slot the confirm surface will fill.
///
/// A pending approval that is not in ThreadScopedChatState is dropped on the
/// next thread switch, and its turn then waits on a completer nobody can
/// answer. That is the failure the whole class exists for, so a new slot is
/// worth pinning against it rather than trusting six parallel field lists to
/// have been updated together.
final _owner = ChatTurnOwner(
  conversationId: 'thread-a',
  interactionGeneration: 3,
);

PendingAssumptionConfirmation _pending({String id = 'confirm-1'}) =>
    PendingAssumptionConfirmation(
      owner: _owner,
      id: id,
      itemId: 'constraint:stable-entity-ids',
      kind: ConversationContractItemKind.constraint,
      itemText: 'Existing entities have stable UUIDs',
      clarificationQuestion: 'Do existing entities have stable UUIDs?',
      toolName: 'write_file',
      completer: Completer<bool>(),
    );

void main() {
  group('the thread keeps its assumption confirmation', () {
    test('a confirmation raised on a background thread survives the stash', () {
      final pending = _pending();
      final byThread = <String, ThreadScopedChatState>{};

      ThreadScopedChatState.remember(
        byThread,
        'thread-a',
        ChatState.initial().copyWith(pendingAssumptionConfirmation: pending),
      );

      expect(
        byThread['thread-a'],
        isNotNull,
        reason:
            'A thread holding only this approval still has content worth '
            'restoring; an omitted field would make the stash look empty.',
      );
      expect(
        ThreadScopedChatState.awaitingApproval(byThread),
        contains('thread-a'),
        reason: 'The sidebar must say the thread is waiting, not spinning.',
      );

      final restored = ThreadScopedChatState.take(
        byThread,
        'thread-a',
      ).applyTo(ChatState.initial());

      expect(
        identical(restored.pendingAssumptionConfirmation, pending),
        isTrue,
      );
    });

    test('an unanswered confirmation is cancelled as unconfirmed', () {
      final pending = _pending();

      pending.completeCancellation();

      expect(
        pending.completer.future,
        completion(isFalse),
        reason:
            'Only the user may dispose of a material assumption. A turn '
            'that expires must leave it blocking, never silently confirmed.',
      );
    });
  });

  group('clearing the answered confirmation', () {
    test('clears the slot it is showing in', () {
      final pending = _pending();
      final state = ChatState.initial().copyWith(
        pendingAssumptionConfirmation: pending,
      );

      expect(
        PendingToolApprovalProjection.clear(
          state,
          pending,
        ).pendingAssumptionConfirmation,
        isNull,
      );
    });

    test('leaves a successor in place when a stale answer arrives', () {
      final answered = _pending();
      final successor = _pending(id: 'confirm-2');
      final state = ChatState.initial().copyWith(
        pendingAssumptionConfirmation: successor,
      );

      expect(
        identical(
          PendingToolApprovalProjection.clear(
            state,
            answered,
          ).pendingAssumptionConfirmation,
          successor,
        ),
        isTrue,
        reason:
            'The identity check is what makes a late answer safe; without '
            'it the second assumption loses its surface.',
      );
    });
  });

  group('answered by id from outside its thread', () {
    test('the registry finds and takes it while another thread is visible', () {
      final pending = _pending();
      final registry = PendingToolApprovalRegistry()..register(pending);

      expect(
        registry.find<PendingAssumptionConfirmation>('confirm-1'),
        isNotNull,
        reason:
            'A blocked background turn is only unblockable because the '
            'registry answers by id rather than through the visible thread.',
      );
      expect(
        registry.take<PendingAssumptionConfirmation>(
          owner: _owner,
          id: 'confirm-1',
        ),
        isNotNull,
      );
      expect(registry.isEmpty, isTrue);
    });
  });
}
