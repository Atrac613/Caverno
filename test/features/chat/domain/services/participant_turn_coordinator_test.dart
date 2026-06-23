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
    bool facilitatesTurns = false,
    bool enabled = true,
  }) {
    return ConversationParticipant(
      id: id,
      order: order,
      endpointId: endpointId,
      displayName: displayName,
      roleLabel: roleLabel,
      roleSystemPrompt: roleSystemPrompt,
      facilitatesTurns: facilitatesTurns,
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
    expect(normalized.first.facilitatesTurns, isTrue);
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

  test('preferred participant handoff can skip ahead in the current round', () {
    final participants = [
      participant(id: 'facilitator', order: 0, roleLabel: 'Facilitator'),
      participant(id: 'critic', order: 1, roleLabel: 'Critic'),
      participant(id: 'engineer', order: 2, roleLabel: 'Senior Engineer'),
    ];
    const config = ParticipantTurnConfig();

    final first = coordinator.nextSpeaker(
      participants: participants,
      config: config,
    );
    final delegated = coordinator.nextSpeaker(
      participants: participants,
      config: config,
      cursor: first.cursor,
      preferredParticipantId: 'engineer',
      lastSpeakerParticipantId: 'facilitator',
    );

    expect(first.participant?.id, 'facilitator');
    expect(delegated.participant?.id, 'engineer');
    expect(delegated.completed, isFalse);
  });

  test('facilitator without handoff returns the floor to the user', () {
    final participants = [
      participant(id: 'facilitator', order: 0, roleLabel: 'Facilitator'),
      participant(id: 'engineer', order: 1, roleLabel: 'Senior Engineer'),
    ];
    const config = ParticipantTurnConfig();

    final first = coordinator.nextSpeaker(
      participants: participants,
      config: config,
    );
    final second = coordinator.nextSpeaker(
      participants: participants,
      config: config,
      cursor: first.cursor,
      lastSpeakerParticipantId: 'facilitator',
    );

    expect(first.participant?.id, 'facilitator');
    expect(second.participant, isNull);
    expect(second.completed, isTrue);
  });

  test(
    'structured facilitator flag controls turns without role label matching',
    () {
      final participants = [
        participant(
          id: 'lead',
          order: 0,
          roleLabel: 'Conversation Lead',
          facilitatesTurns: true,
        ),
        participant(id: 'engineer', order: 1, roleLabel: 'Senior Engineer'),
      ];
      const config = ParticipantTurnConfig();

      final first = coordinator.nextSpeaker(
        participants: participants,
        config: config,
      );
      final second = coordinator.nextSpeaker(
        participants: participants,
        config: config,
        cursor: first.cursor,
        lastSpeakerParticipantId: 'lead',
      );

      expect(first.participant?.id, 'lead');
      expect(second.participant, isNull);
      expect(second.completed, isTrue);
    },
  );

  test('legacy facilitator role labels still control turns', () {
    final participants = [
      participant(id: 'legacy', order: 0, roleLabel: 'Moderator'),
      participant(id: 'engineer', order: 1, roleLabel: 'Senior Engineer'),
    ];
    const config = ParticipantTurnConfig();

    final first = coordinator.nextSpeaker(
      participants: participants,
      config: config,
    );
    final second = coordinator.nextSpeaker(
      participants: participants,
      config: config,
      cursor: first.cursor,
      lastSpeakerParticipantId: 'legacy',
    );

    expect(first.participant?.id, 'legacy');
    expect(second.participant, isNull);
    expect(second.completed, isTrue);
  });

  test(
    'non-facilitator handoff returns to facilitator in multi-round mode',
    () {
      final participants = [
        participant(id: 'facilitator', order: 0, roleLabel: 'Facilitator'),
        participant(id: 'engineer', order: 1, roleLabel: 'Senior Engineer'),
        participant(id: 'critic', order: 2, roleLabel: 'Critic'),
      ];
      const config = ParticipantTurnConfig(
        depth: ParticipantTurnDepth.multiRound,
        maxRounds: 2,
      );

      final first = coordinator.nextSpeaker(
        participants: participants,
        config: config,
      );
      final engineer = coordinator.nextSpeaker(
        participants: participants,
        config: config,
        cursor: first.cursor,
        preferredParticipantId: 'engineer',
        lastSpeakerParticipantId: 'facilitator',
      );
      final backToFacilitator = coordinator.nextSpeaker(
        participants: participants,
        config: config,
        cursor: engineer.cursor,
        preferredParticipantId: 'critic',
        lastSpeakerParticipantId: 'engineer',
      );

      expect(engineer.participant?.id, 'engineer');
      expect(backToFacilitator.participant?.id, 'facilitator');
      expect(backToFacilitator.roundNumber, 2);
    },
  );

  test('extracts handoff directive and resolves target participant', () {
    final facilitator = participant(
      id: 'facilitator',
      order: 0,
      displayName: 'Primary',
      roleLabel: 'Facilitator',
    );
    final engineer = participant(
      id: 'engineer',
      order: 1,
      displayName: 'PC2',
      roleLabel: 'Senior Engineer',
    );

    final handoff = coordinator.extractHandoffDirective(
      content:
          'The implementation details should be covered next.\n\n'
          'Handoff: Senior Engineer\n',
      participants: [facilitator, engineer],
      sourceParticipantId: facilitator.id,
    );

    expect(handoff, isNotNull);
    expect(
      handoff!.content,
      'The implementation details should be covered next.',
    );
    expect(handoff.targetLabel, 'Senior Engineer');
    expect(handoff.targetParticipantId, 'engineer');
  });

  test('handoff directive keeps the visible participant invitation', () {
    final facilitator = participant(
      id: 'facilitator',
      order: 0,
      displayName: 'Primary',
      roleLabel: 'Facilitator',
    );
    final engineer = participant(
      id: 'engineer',
      order: 1,
      displayName: 'PC2',
      roleLabel: 'Senior Engineer',
    );

    final handoff = coordinator.extractHandoffDirective(
      content:
          'This implementation needs a deeper review.\n'
          'Senior Engineer, what do you think about this risk?\n'
          'Handoff: Senior Engineer\n',
      participants: [facilitator, engineer],
      sourceParticipantId: facilitator.id,
    );

    expect(handoff, isNotNull);
    expect(
      handoff!.content,
      'This implementation needs a deeper review.\n'
      'Senior Engineer, what do you think about this risk?',
    );
    expect(handoff.targetLabel, 'Senior Engineer');
    expect(handoff.targetParticipantId, 'engineer');
  });

  test('facilitator user choice prompt suppresses mixed handoff routing', () {
    final facilitator = participant(
      id: 'facilitator',
      order: 0,
      displayName: 'Primary',
      roleLabel: 'Facilitator',
    );
    final engineer = participant(
      id: 'engineer',
      order: 1,
      displayName: 'PC2',
      roleLabel: 'Senior Engineer',
    );

    final handoff = coordinator.extractHandoffDirective(
      content:
          'Which scenario should we start with? Please choose one before we proceed.\n\n'
          'Senior Engineer, what implementation risk would you highlight?\n'
          'Handoff: Senior Engineer\n',
      participants: [facilitator, engineer],
      sourceParticipantId: facilitator.id,
    );

    expect(handoff, isNotNull);
    expect(
      handoff!.content,
      'Which scenario should we start with? Please choose one before we proceed.',
    );
    expect(handoff.targetLabel, 'Senior Engineer');
    expect(handoff.targetParticipantId, isNull);
  });

  test(
    'facilitator localized user choice drops mixed participant invitation',
    () {
      final facilitator = participant(
        id: 'facilitator',
        order: 0,
        displayName: 'Primary',
        roleLabel: 'Facilitator',
      );
      final engineer = participant(
        id: 'engineer',
        order: 1,
        displayName: 'PC2',
        roleLabel: 'Senior Engineer',
      );
      final userChoicePrompt = String.fromCharCodes([
        0x3069,
        0x306e,
        0x30c8,
        0x30d4,
        0x30c3,
        0x30af,
        0x304b,
        0x3089,
        0x59cb,
        0x3081,
        0x307e,
        0x3059,
        0x304b,
        0xff1f,
        0x6559,
        0x3048,
        0x3066,
        0x304f,
        0x3060,
        0x3055,
        0x3044,
        0x3002,
      ]);

      final handoff = coordinator.extractHandoffDirective(
        content:
            '$userChoicePrompt\n\n'
            'Senior Engineer, what implementation risk would you highlight?\n'
            'Handoff: Senior Engineer\n',
        participants: [facilitator, engineer],
        sourceParticipantId: facilitator.id,
      );

      expect(handoff, isNotNull);
      expect(handoff!.content, userChoicePrompt);
      expect(handoff.targetLabel, 'Senior Engineer');
      expect(handoff.targetParticipantId, isNull);
    },
  );

  test('facilitator localized persona invite routes handoff', () {
    final facilitator = participant(
      id: 'facilitator',
      order: 0,
      displayName: 'Primary',
      roleLabel: 'Facilitator',
    );
    final reviewer = participant(
      id: 'reviewer',
      order: 1,
      displayName: 'Reviewer',
      roleLabel: 'Reviewer',
    );
    final personaInvite = String.fromCharCodes([
      0x304a,
      0x3082,
      0x3057,
      0x308d,
      0x304a,
      0x3058,
      0x3055,
      0x3093,
      0x3001,
      0x3055,
      0x304b,
      0x306a,
      0x20,
      0x41,
      0x49,
      0x20,
      0x306b,
      0x3064,
      0x3044,
      0x3066,
      0x77e5,
      0x3063,
      0x3066,
      0x3044,
      0x308b,
      0x3053,
      0x3068,
      0x3092,
      0x6559,
      0x3048,
      0x3066,
      0x304f,
      0x3060,
      0x3055,
      0x3044,
      0x306d,
      0x3002,
    ]);

    final handoff = coordinator.extractHandoffDirective(
      content:
          'This point needs another participant.\n\n'
          '$personaInvite\n'
          'Handoff: Reviewer\n',
      participants: [facilitator, reviewer],
      sourceParticipantId: facilitator.id,
    );

    expect(handoff, isNotNull);
    expect(
      handoff!.content,
      'This point needs another participant.\n\n$personaInvite',
    );
    expect(handoff.targetLabel, 'Reviewer');
    expect(handoff.targetParticipantId, 'reviewer');
  });

  test('facilitator non-label question invite routes handoff', () {
    final facilitator = participant(
      id: 'facilitator',
      order: 0,
      displayName: 'Primary',
      roleLabel: 'Facilitator',
    );
    final reviewer = participant(
      id: 'reviewer',
      order: 1,
      displayName: 'Reviewer',
      roleLabel: 'Reviewer',
    );

    final handoff = coordinator.extractHandoffDirective(
      content:
          'This point needs another participant.\n\n'
          'Topic expert, what do you think about this claim?\n'
          'Handoff: Reviewer\n',
      participants: [facilitator, reviewer],
      sourceParticipantId: facilitator.id,
    );

    expect(handoff, isNotNull);
    expect(
      handoff!.content,
      'This point needs another participant.\n\n'
      'Topic expert, what do you think about this claim?',
    );
    expect(handoff.targetLabel, 'Reviewer');
    expect(handoff.targetParticipantId, 'reviewer');
  });

  test('facilitator implicit localized participant invite routes handoff', () {
    final facilitator = participant(
      id: 'facilitator',
      order: 0,
      displayName: 'Primary',
      roleLabel: 'Facilitator',
    );
    final critic = participant(
      id: 'critic',
      order: 1,
      displayName: 'Critic',
      roleLabel: 'Critic',
    );
    final localizedRequest = String.fromCharCodes([
      0x0043,
      0x0072,
      0x0069,
      0x0074,
      0x0069,
      0x0063,
      0x002c,
      0x0020,
      0x0066,
      0x0069,
      0x006e,
      0x0061,
      0x006c,
      0x0020,
      0x0061,
      0x006e,
      0x0061,
      0x006c,
      0x0079,
      0x0073,
      0x0069,
      0x0073,
      0x0020,
      0x306b,
      0x3064,
      0x3044,
      0x3066,
      0x610f,
      0x898b,
      0x3092,
      0x304a,
      0x805e,
      0x304b,
      0x305b,
      0x304f,
      0x3060,
      0x3055,
      0x3044,
      0x3002,
    ]);

    final handoff = coordinator.extractHandoffDirective(
      content:
          'We need a stricter review.\n\n'
          '$localizedRequest\n',
      participants: [facilitator, critic],
      sourceParticipantId: facilitator.id,
    );

    expect(handoff, isNotNull);
    expect(handoff!.content, 'We need a stricter review.\n\n$localizedRequest');
    expect(handoff.targetLabel, 'Critic');
    expect(handoff.targetParticipantId, 'critic');
  });

  test('facilitator question handoff strips marker without routing', () {
    final facilitator = participant(
      id: 'facilitator',
      order: 0,
      displayName: 'Primary',
      roleLabel: 'Facilitator',
    );
    final engineer = participant(
      id: 'engineer',
      order: 1,
      displayName: 'PC2',
      roleLabel: 'Senior Engineer',
    );

    final handoff = coordinator.extractHandoffDirective(
      content: 'Which area should we start with?\nHandoff: Senior Engineer\n',
      participants: [facilitator, engineer],
      sourceParticipantId: facilitator.id,
    );

    expect(handoff, isNotNull);
    expect(handoff!.content, 'Which area should we start with?');
    expect(handoff.targetLabel, 'Senior Engineer');
    expect(handoff.targetParticipantId, isNull);
  });

  test(
    'facilitator localized open topic prompt suppresses handoff routing',
    () {
      final facilitator = participant(
        id: 'facilitator',
        order: 0,
        displayName: 'Primary',
        roleLabel: 'Facilitator',
      );
      final reviewer = participant(
        id: 'reviewer',
        order: 1,
        displayName: 'Reviewer',
        roleLabel: 'Reviewer',
      );
      final openTopicPrompt = String.fromCharCodes([
        0x4eca,
        0x65e5,
        0x306f,
        0x3069,
        0x3093,
        0x306a,
        0x304a,
        0x8a71,
        0x3092,
        0x3057,
        0x307e,
        0x3057,
        0x3087,
        0x3046,
        0x304b,
        0xff1f,
        0x4f55,
        0x3067,
        0x3082,
        0x6c17,
        0x8efd,
        0x306b,
        0x8a71,
        0x3057,
        0x304b,
        0x3051,
        0x3066,
        0x304f,
        0x3060,
        0x3055,
        0x3044,
        0x306d,
        0x3002,
      ]);

      final handoff = coordinator.extractHandoffDirective(
        content: '$openTopicPrompt\nHandoff: Reviewer\n',
        participants: [facilitator, reviewer],
        sourceParticipantId: facilitator.id,
      );

      expect(handoff, isNotNull);
      expect(handoff!.content, openTopicPrompt);
      expect(handoff.targetLabel, 'Reviewer');
      expect(handoff.targetParticipantId, isNull);
    },
  );

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
      expect(view.first.content, contains('- Name: PC2'));
      expect(view.first.content, contains('- Role: Senior Engineer'));
      expect(
        view.first.content,
        contains('Other participants available in this conversation:'),
      );
      expect(view.first.content, contains('- Primary · Facilitator'));
      expect(view.first.content, contains('Respond as a senior engineer.'));
      expect(
        view.first.content,
        contains('A facilitator is managing the floor'),
      );
      expect(
        view.first.content,
        isNot(contains('Handoff: <participant name or role>')),
      );
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

  test('facilitator role prompt asks for delegation to specialists', () {
    final facilitator = participant(
      id: 'pc1',
      order: 0,
      displayName: 'Primary',
      roleLabel: 'Facilitator',
      roleSystemPrompt: 'Keep the discussion moving.',
    );
    final engineer = participant(
      id: 'pc2',
      order: 1,
      endpointId: 'pc2',
      displayName: 'PC2',
      roleLabel: 'Senior Engineer',
    );

    final prompt = coordinator.buildRolePromptForParticipant(
      target: facilitator,
      participants: [facilitator, engineer],
    );

    expect(prompt, contains('- Name: Primary'));
    expect(prompt, contains('- Role: Facilitator'));
    expect(prompt, contains('- PC2 · Senior Engineer'));
    expect(prompt, contains('manage the floor'));
    expect(prompt, contains('the floor returns to the user'));
    expect(prompt, contains('visible natural invitation'));
    expect(prompt, contains('so the user can see why the next speaker'));
    expect(prompt, contains('Do not include a handoff line'));
    expect(prompt, contains('requesting clarification'));
    expect(prompt, contains('Do not mix an unresolved user-facing choice'));
    expect(prompt, contains('Handoff: <participant name or role>'));
    expect(prompt, contains('Role-specific instructions:'));
    expect(prompt, contains('Keep the discussion moving.'));
  });

  test('structured facilitator flag selects facilitator role prompt', () {
    final lead = participant(
      id: 'pc1',
      order: 0,
      displayName: 'Lead',
      roleLabel: 'Conversation Lead',
      facilitatesTurns: true,
    );
    final engineer = participant(
      id: 'pc2',
      order: 1,
      endpointId: 'pc2',
      displayName: 'PC2',
      roleLabel: 'Senior Engineer',
    );

    final prompt = coordinator.buildRolePromptForParticipant(
      target: lead,
      participants: [lead, engineer],
    );

    expect(prompt, contains('- Role: Conversation Lead'));
    expect(prompt, contains('manage the floor'));
    expect(prompt, contains('Handoff: <participant name or role>'));
  });
}
