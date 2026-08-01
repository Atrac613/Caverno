import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/conversation_participant.dart';
import 'package:caverno/features/chat/domain/services/participant_turn_coordinator.dart';
import 'package:caverno/features/chat/presentation/providers/participant_turn_control_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final ownerA = ChatTurnOwner(
    conversationId: 'thread-a',
    interactionGeneration: 7,
  );
  final ownerB = ChatTurnOwner(
    conversationId: 'thread-b',
    interactionGeneration: 7,
  );

  ParticipantTurnPauseSnapshot pauseSnapshot({
    String participantId = 'participant-a',
    int roundIndex = 1,
  }) => ParticipantTurnPauseSnapshot(
    cursor: ParticipantTurnCursor(roundIndex: roundIndex, participantIndex: 1),
    participants: [
      ConversationParticipant(id: participantId, displayName: participantId),
    ],
    config: const ParticipantTurnConfig(
      depth: ParticipantTurnDepth.multiRound,
      maxRounds: 3,
    ),
    preferredParticipantId: 'preferred-$participantId',
    lastSpeakerParticipantId: 'last-$participantId',
  );

  test('requires active owners and isolates stop and pause state', () {
    final registry = ParticipantTurnControlRegistry();
    final snapshotA = pauseSnapshot();

    expect(registry.isEmpty, isTrue);
    expect(registry.length, 0);
    expect(registry.owners, isEmpty);
    expect(registry.contains(ownerA), isFalse);
    expect(registry.requestStop(ownerA), isFalse);
    expect(registry.stopRequested(ownerA), isFalse);
    expect(registry.pause(ownerA, snapshotA), isFalse);
    expect(registry.isPaused(ownerA), isFalse);
    expect(registry.resume(ownerA), isNull);
    expect(registry.consumeCursor(ownerA), isNull);
    expect(registry.clear(ownerA), isFalse);

    expect(registry.begin(ownerA), isTrue);
    expect(registry.begin(ownerB), isTrue);
    expect(registry.begin(ownerA), isFalse);
    expect(registry.contains(ownerA), isTrue);
    expect(registry.length, 2);
    expect(registry.isEmpty, isFalse);
    expect(() => registry.owners.add(ownerA), throwsUnsupportedError);

    expect(registry.requestStop(ownerA), isTrue);
    expect(registry.requestStop(ownerA), isTrue);
    expect(registry.stopRequested(ownerA), isTrue);
    expect(registry.stopRequested(ownerB), isFalse);

    expect(registry.pause(ownerA, snapshotA), isTrue);
    expect(registry.stopRequested(ownerA), isFalse);
    expect(registry.isPaused(ownerA), isTrue);
    expect(registry.isPaused(ownerB), isFalse);
    expect(registry.requestStop(ownerA), isFalse);
    expect(registry.pausedOwnerForConversation('thread-a'), ownerA);
    expect(registry.pausedOwnerForConversation('missing'), isNull);

    final resumed = registry.resume(ownerA);
    expect(resumed, same(snapshotA));
    expect(resumed!.participants.single.id, 'participant-a');
    expect(
      () => resumed.participants.add(
        const ConversationParticipant(id: 'late-participant'),
      ),
      throwsUnsupportedError,
    );
    expect(resumed.config.maxRounds, 3);
    expect(resumed.preferredParticipantId, 'preferred-participant-a');
    expect(resumed.lastSpeakerParticipantId, 'last-participant-a');
    expect(registry.resume(ownerA), isNull);
    expect(registry.consumeCursor(ownerB), isNull);
    expect(registry.consumeCursor(ownerA)?.roundIndex, 1);
    expect(registry.consumeCursor(ownerA), isNull);
    expect(registry.isPaused(ownerA), isFalse);

    expect(registry.requestStop(ownerA), isTrue);
    expect(registry.clear(ownerA), isTrue);
    expect(registry.stopRequested(ownerA), isFalse);
    expect(registry.contains(ownerB), isTrue);
  });

  test('two paused owners resume and consume independently', () {
    final registry = ParticipantTurnControlRegistry();
    final newerOwnerA = ChatTurnOwner(
      conversationId: ownerA.conversationId,
      interactionGeneration: 8,
    );
    final snapshotA = pauseSnapshot();
    final newerSnapshotA = pauseSnapshot(
      participantId: 'participant-a-newer',
      roundIndex: 2,
    );
    final snapshotB = pauseSnapshot(
      participantId: 'participant-b',
      roundIndex: 3,
    );

    expect(registry.begin(ownerA), isTrue);
    expect(registry.begin(newerOwnerA), isTrue);
    expect(registry.begin(ownerB), isTrue);
    expect(registry.pause(ownerA, snapshotA), isTrue);
    expect(registry.pause(newerOwnerA, newerSnapshotA), isTrue);
    expect(registry.pause(ownerB, snapshotB), isTrue);
    expect(
      registry.pausedOwnerForConversation(ownerA.conversationId),
      newerOwnerA,
    );
    expect(registry.pausedOwnerForConversation(ownerB.conversationId), ownerB);

    expect(registry.resume(ownerB), same(snapshotB));
    expect(registry.resume(ownerB), isNull);
    expect(registry.clear(ownerB), isTrue);
    expect(registry.resume(ownerB), same(snapshotB));
    expect(registry.consumeCursor(ownerB)?.roundIndex, 3);
    expect(registry.isPaused(ownerB), isFalse);

    expect(registry.resume(newerOwnerA), same(newerSnapshotA));
    expect(registry.consumeCursor(newerOwnerA)?.roundIndex, 2);
    expect(registry.isPaused(ownerA), isTrue);
    expect(registry.resume(ownerA), same(snapshotA));
    expect(registry.consumeCursor(ownerA)?.roundIndex, 1);
  });

  test('dispose is owner-local and poisons retired generations', () {
    final registry = ParticipantTurnControlRegistry();
    final newerOwnerA = ChatTurnOwner(
      conversationId: ownerA.conversationId,
      interactionGeneration: 8,
    );
    final newerOwnerB = ChatTurnOwner(
      conversationId: ownerB.conversationId,
      interactionGeneration: 8,
    );
    final snapshot = pauseSnapshot();

    expect(registry.begin(ownerA), isTrue);
    expect(registry.begin(ownerB), isTrue);
    expect(registry.dispose(ownerA), isTrue);
    expect(registry.dispose(ownerA), isFalse);
    expect(registry.begin(ownerA), isFalse);
    expect(registry.requestStop(ownerA), isFalse);
    expect(registry.pause(ownerA, snapshot), isFalse);
    expect(registry.resume(ownerA), isNull);
    expect(registry.consumeCursor(ownerA), isNull);
    expect(registry.clear(ownerA), isFalse);
    expect(registry.contains(ownerB), isTrue);

    expect(registry.begin(newerOwnerA), isTrue);
    expect(registry.dispose(newerOwnerA), isTrue);
    expect(registry.dispose(ownerA), isFalse);
    expect(registry.begin(newerOwnerA), isFalse);

    expect(registry.dispose(newerOwnerB), isFalse);
    expect(registry.begin(ownerB), isFalse);
    expect(registry.begin(newerOwnerB), isFalse);
    expect(registry.dispose(ownerB), isTrue);
    expect(registry.isEmpty, isTrue);
  });
}
