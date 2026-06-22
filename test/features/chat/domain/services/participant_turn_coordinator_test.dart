import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/conversation_participant.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/services/participant_turn_coordinator.dart';

void main() {
  const coordinator = ParticipantTurnCoordinator();

  ConversationParticipant participant({
    required String id,
    required int order,
    String endpointId = '',
    String displayName = '',
    String roleLabel = '',
    String roleSystemPrompt = '',
    bool enabled = true,
  }) {
    return ConversationParticipant(
      id: id,
      order: order,
      endpointId: endpointId,
      displayName: displayName,
      roleLabel: roleLabel,
      roleSystemPrompt: roleSystemPrompt,
      enabled: enabled,
    );
  }

  Message message({
    required String id,
    required String content,
    required MessageRole role,
    String? participantId,
    String? participantDisplayName,
    String? participantRoleLabel,
  }) {
    return Message(
      id: id,
      content: content,
      role: role,
      participantId: participantId,
      participantDisplayName: participantDisplayName,
      participantRoleLabel: participantRoleLabel,
      timestamp: DateTime(2026, 6, 23, 12),
    );
  }

  test('materializes a primary participant when only remote members exist', () {
    final normalized = coordinator.normalizeParticipants(
      primaryModel: 'primary-model',
      participants: [
        participant(
          id: 'pc2',
          order: 1,
          endpointId: 'pc2',
          displayName: 'PC2',
          roleLabel: 'Senior Engineer',
        ),
      ],
    );

    expect(normalized, hasLength(2));
    expect(
      normalized.first.id,
      ParticipantTurnCoordinator.primaryParticipantId,
    );
    expect(normalized.first.endpointId, isEmpty);
    expect(normalized.first.model, 'primary-model');
    expect(normalized.first.roleLabel, 'Facilitator');
    expect(normalized.last.id, 'pc2');
  });

  test('does not add another primary participant when one already exists', () {
    final normalized = coordinator.normalizeParticipants(
      primaryModel: 'primary-model',
      participants: [
        participant(id: 'pc1', order: 0),
        participant(id: 'pc2', order: 1, endpointId: 'pc2'),
      ],
    );

    expect(normalized.map((item) => item.id), ['pc1', 'pc2']);
  });

  test('round robin advances through one single-round pass', () {
    final participants = [
      participant(id: 'pc1', order: 0),
      participant(id: 'pc2', order: 1, endpointId: 'pc2'),
    ];
    const config = ParticipantTurnConfig();

    final first = coordinator.nextSpeaker(
      participants: participants,
      config: config,
    );
    expect(first.participant?.id, 'pc1');
    expect(first.roundNumber, 1);
    expect(first.completed, isFalse);

    final second = coordinator.nextSpeaker(
      participants: participants,
      config: config,
      cursor: first.cursor,
    );
    expect(second.participant?.id, 'pc2');
    expect(second.completed, isTrue);

    final done = coordinator.nextSpeaker(
      participants: participants,
      config: config,
      cursor: second.cursor,
    );
    expect(done.participant, isNull);
    expect(done.completed, isTrue);
  });

  test('multi-round cursor can pause and continue after a soft stop', () {
    final participants = [
      participant(id: 'pc1', order: 0),
      participant(id: 'pc2', order: 1, endpointId: 'pc2'),
    ];
    const config = ParticipantTurnConfig(
      depth: ParticipantTurnDepth.multiRound,
      maxRounds: 2,
    );

    final first = coordinator.nextSpeaker(
      participants: participants,
      config: config,
    );
    final paused = coordinator.nextSpeaker(
      participants: participants,
      config: config,
      cursor: first.cursor,
      stopRequested: true,
    );
    expect(paused.participant, isNull);
    expect(paused.paused, isTrue);
    expect(paused.completed, isFalse);

    final continued = coordinator.nextSpeaker(
      participants: participants,
      config: config,
      cursor: paused.cursor,
    );
    expect(continued.participant?.id, 'pc2');
    expect(continued.roundNumber, 1);

    final roundTwoFirst = coordinator.nextSpeaker(
      participants: participants,
      config: config,
      cursor: continued.cursor,
    );
    expect(roundTwoFirst.participant?.id, 'pc1');
    expect(roundTwoFirst.roundNumber, 2);
  });

  test(
    'participant view renders own turns as assistant and others as user',
    () {
      final pc1 = participant(
        id: 'pc1',
        order: 0,
        displayName: 'Primary',
        roleLabel: 'Facilitator',
        roleSystemPrompt: 'Keep the discussion moving.',
      );
      final pc2 = participant(
        id: 'pc2',
        order: 1,
        endpointId: 'pc2',
        displayName: 'PC2',
        roleLabel: 'Senior Engineer',
        roleSystemPrompt: 'Respond as a senior engineer.',
      );
      final view = coordinator.buildMessagesForParticipant(
        target: pc2,
        participants: [pc1, pc2],
        transcript: [
          message(
            id: 'u1',
            content: 'Design this feature',
            role: MessageRole.user,
          ),
          message(
            id: 'a1',
            content: 'I will facilitate.',
            role: MessageRole.assistant,
            participantId: 'pc1',
            participantDisplayName: 'Primary',
            participantRoleLabel: 'Facilitator',
          ),
          message(
            id: 'a2',
            content: 'Here is the engineering view.',
            role: MessageRole.assistant,
            participantId: 'pc2',
          ),
        ],
      );

      expect(view.first.role, MessageRole.system);
      expect(view.first.content, 'Respond as a senior engineer.');
      expect(view[1].role, MessageRole.user);
      expect(view[1].content, '[User]: Design this feature');
      expect(view[2].role, MessageRole.user);
      expect(view[2].content, '[Primary · Facilitator]: I will facilitate.');
      expect(view[3].role, MessageRole.assistant);
      expect(view[3].content, 'Here is the engineering view.');
    },
  );

  test('primary participant treats legacy assistant turns as its own', () {
    final pc1 = participant(id: 'pc1', order: 0);
    final view = coordinator.buildMessagesForParticipant(
      target: pc1,
      participants: [pc1],
      includeRolePrompt: false,
      transcript: [
        message(
          id: 'legacy',
          content: 'Existing assistant answer',
          role: MessageRole.assistant,
        ),
      ],
    );

    expect(view.single.role, MessageRole.assistant);
    expect(view.single.content, 'Existing assistant answer');
  });
}
