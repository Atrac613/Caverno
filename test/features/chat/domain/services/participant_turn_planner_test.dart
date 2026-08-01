import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/conversation_participant.dart';
import 'package:caverno/features/chat/domain/services/participant_turn_coordinator.dart';
import 'package:caverno/features/chat/domain/services/participant_turn_planner.dart';
import 'package:test/test.dart';

const _planner = ParticipantTurnPlanner();

void main() {
  group('ParticipantTurnPlanner', () {
    test('keeps an already normalized roster unchanged', () {
      final participants = [
        _participant('primary', order: 0),
        _participant('specialist', endpointId: 'remote', order: 1),
      ];

      final plan = _planner.start(
        owner: _owner('owner-a', 1),
        participants: participants,
        primaryModel: 'primary-model',
        config: const ParticipantTurnConfig(),
      );

      expect(plan.kind, ParticipantTurnStepKind.streamParticipant);
      expect(plan.participantsChanged, isFalse);
      expect(plan.state.participants, participants);
      expect(plan.participant!.id, 'primary');
      participants.clear();
      expect(plan.state.participants.map((participant) => participant.id), [
        'primary',
        'specialist',
      ]);
      expect(
        () => plan.state.participants.add(_participant('mutation')),
        throwsUnsupportedError,
      );
    });

    test('reports ordering-only normalization as a participant change', () {
      final plan = _planner.start(
        owner: _owner('owner-a', 1),
        participants: [
          _participant('second', endpointId: 'remote', order: 1),
          _participant('primary', order: 0),
        ],
        primaryModel: 'primary-model',
        config: const ParticipantTurnConfig(),
      );

      expect(plan.participantsChanged, isTrue);
      expect(plan.state.participants.map((participant) => participant.id), [
        'primary',
        'second',
      ]);
    });

    test('normalizes ordering and inserts a missing primary participant', () {
      final plan = _planner.start(
        owner: _owner('owner-a', 1),
        participants: [
          _participant('later', endpointId: 'remote-b', order: 2),
          _participant('first', endpointId: 'remote-a', order: 1),
        ],
        primaryModel: 'primary-model',
        config: const ParticipantTurnConfig(),
      );

      expect(plan.participantsChanged, isTrue);
      expect(plan.state.participants.map((participant) => participant.id), [
        'primary_assistant',
        'first',
        'later',
      ]);
      expect(plan.state.participants.first.model, 'primary-model');
      expect(plan.participant!.id, 'primary_assistant');
    });

    test('returns a distinct no-participants step for a disabled roster', () {
      final plan = _planner.start(
        owner: _owner('owner-a', 1),
        participants: [_participant('primary', enabled: false)],
        primaryModel: 'primary-model',
        config: const ParticipantTurnConfig(),
      );

      expect(plan.kind, ParticipantTurnStepKind.noParticipants);
      expect(plan.participant, isNull);
      expect(plan.runtime, isNull);
      expect(plan.exitReason, 'participant_turn_empty_roster');
    });

    test('streams a complete single round in participant order', () {
      var plan = _planner.start(
        owner: _owner('owner-a', 1),
        participants: [
          _participant('first', order: 0),
          _participant('second', endpointId: 'remote', order: 1),
        ],
        primaryModel: 'primary-model',
        config: const ParticipantTurnConfig(
          depth: ParticipantTurnDepth.singleRound,
          maxRounds: 99,
        ),
      );

      expect(plan.participant!.id, 'first');
      expect(plan.state.awaitingFinalTurn, isFalse);
      expect(plan.runtime!.maxRounds, 1);
      plan = _planner.advance(
        state: plan.state,
        completedContent: 'first response',
        stopRequested: false,
      );
      expect(plan.kind, ParticipantTurnStepKind.streamParticipant);
      expect(plan.participant!.id, 'second');
      expect(plan.state.awaitingFinalTurn, isTrue);
      plan = _planner.advance(
        state: plan.state,
        completedContent: 'second response',
        stopRequested: false,
      );
      expect(plan.kind, ParticipantTurnStepKind.complete);
      expect(plan.state.completedContent, 'second response');
      expect(plan.exitReason, 'participant_turn_completed');
    });

    test('clamps nonpositive multi-round limits to one round', () {
      var plan = _planner.start(
        owner: _owner('owner-a', 1),
        participants: [_participant('primary')],
        primaryModel: 'primary-model',
        config: const ParticipantTurnConfig(
          depth: ParticipantTurnDepth.multiRound,
          maxRounds: 0,
        ),
      );

      expect(plan.runtime!.multiRound, isTrue);
      expect(plan.runtime!.maxRounds, 1);
      expect(plan.runtime!.currentRound, 1);
      expect(plan.state.awaitingFinalTurn, isTrue);
      plan = _planner.advance(
        state: plan.state,
        completedContent: 'done',
        stopRequested: false,
      );
      expect(plan.kind, ParticipantTurnStepKind.complete);
    });

    test('uses a preferred handoff once and then resumes progression', () {
      final participants = [
        _participant('first', order: 0),
        _participant('second', endpointId: 'remote-2', order: 1),
        _participant('third', endpointId: 'remote-3', order: 2),
      ];
      var plan = _planner.start(
        owner: _owner('owner-a', 1),
        participants: participants,
        primaryModel: 'primary-model',
        config: const ParticipantTurnConfig(
          depth: ParticipantTurnDepth.multiRound,
          maxRounds: 2,
        ),
      );

      expect(plan.participant!.id, 'first');
      plan = _planner.advance(
        state: plan.state,
        completedContent: 'handoff',
        handoffParticipantId: 'third',
        stopRequested: false,
      );
      expect(plan.participant!.id, 'third');
      expect(plan.state.preferredParticipantId, isNull);
      plan = _planner.advance(
        state: plan.state,
        completedContent: 'third response',
        stopRequested: false,
      );
      expect(plan.participant!.id, 'first');
    });

    test('uses last-speaker state for facilitator progression', () {
      final facilitator = _participant(
        'facilitator',
        facilitatesTurns: true,
        order: 0,
      );
      final specialist = _participant(
        'specialist',
        endpointId: 'remote',
        order: 1,
      );
      var plan = _planner.start(
        owner: _owner('owner-a', 1),
        participants: [facilitator, specialist],
        primaryModel: 'primary-model',
        config: const ParticipantTurnConfig(
          depth: ParticipantTurnDepth.multiRound,
          maxRounds: 2,
        ),
      );

      expect(plan.participant!.id, 'facilitator');
      plan = _planner.advance(
        state: plan.state,
        completedContent: 'Specialist, please respond.',
        handoffParticipantId: 'specialist',
        stopRequested: false,
      );
      expect(plan.participant!.id, 'specialist');
      plan = _planner.advance(
        state: plan.state,
        completedContent: 'Specialist response',
        stopRequested: false,
      );
      expect(plan.participant!.id, 'facilitator');
    });

    test('pauses after a non-final turn when stop is requested', () {
      var plan = _planner.start(
        owner: _owner('owner-a', 1),
        participants: [
          _participant('first'),
          _participant('second', endpointId: 'remote', order: 1),
        ],
        primaryModel: 'primary-model',
        config: const ParticipantTurnConfig(
          depth: ParticipantTurnDepth.multiRound,
          maxRounds: 3,
        ),
      );

      plan = _planner.advance(
        state: plan.state,
        completedContent: 'first response',
        handoffParticipantId: 'second',
        stopRequested: true,
      );

      expect(plan.kind, ParticipantTurnStepKind.pause);
      expect(plan.state.preferredParticipantId, 'second');
      expect(plan.state.lastSpeakerParticipantId, 'first');
      expect(plan.state.completedContent, 'first response');
      expect(plan.runtime!.activeParticipantId, isNull);
      expect(plan.runtime!.activeParticipantName, isEmpty);
      expect(plan.runtime!.activeParticipantRoleLabel, isEmpty);
      expect(plan.runtime!.activeParticipantColorValue, isNull);
      expect(plan.runtime!.currentRound, 1);
      expect(plan.runtime!.maxRounds, 3);
      expect(plan.runtime!.multiRound, isTrue);
      expect(plan.runtime!.stopRequested, isTrue);
      expect(plan.runtime!.paused, isTrue);
      expect(plan.runtime!.activeToolName, isEmpty);
      expect(plan.exitReason, 'participant_turn_paused');
    });

    test(
      'pauses before selecting a speaker when stop is already requested',
      () {
        final plan = _planner.start(
          owner: _owner('owner-a', 1),
          participants: [_participant('primary')],
          primaryModel: 'primary-model',
          config: const ParticipantTurnConfig(),
          cursor: const ParticipantTurnCursor(roundIndex: 1),
          completedContent: 'previous response',
          stopRequested: true,
        );

        expect(plan.kind, ParticipantTurnStepKind.pause);
        expect(plan.participant, isNull);
        expect(plan.state.completedContent, 'previous response');
        expect(plan.runtime!.currentRound, 1);
        expect(plan.runtime!.paused, isTrue);
      },
    );

    test('a final participant turn completes even when stop is requested', () {
      var plan = _planner.start(
        owner: _owner('owner-a', 1),
        participants: [_participant('primary')],
        primaryModel: 'primary-model',
        config: const ParticipantTurnConfig(),
      );
      expect(plan.state.awaitingFinalTurn, isTrue);

      plan = _planner.advance(
        state: plan.state,
        completedContent: 'final response',
        stopRequested: true,
      );

      expect(plan.kind, ParticipantTurnStepKind.complete);
      expect(plan.state.stopRequested, isTrue);
      expect(plan.exitReason, 'participant_turn_completed');
    });

    test('resumes from an explicit cursor and preferred participant', () {
      final plan = _planner.start(
        owner: _owner('owner-a', 2),
        participants: [
          _participant('first'),
          _participant('second', endpointId: 'remote', order: 1),
        ],
        primaryModel: 'primary-model',
        config: const ParticipantTurnConfig(
          depth: ParticipantTurnDepth.multiRound,
          maxRounds: 3,
        ),
        cursor: const ParticipantTurnCursor(roundIndex: 1, participantIndex: 0),
        preferredParticipantId: 'second',
        lastSpeakerParticipantId: 'first',
        completedContent: 'prior response',
      );

      expect(plan.participant!.id, 'second');
      expect(plan.runtime!.currentRound, 2);
      expect(plan.state.completedContent, 'prior response');
    });

    test('projects exact active participant runtime values', () {
      final participant = _participant(
        'speaker',
        displayName: '  Speaker Name  ',
        roleLabel: '  Reviewer  ',
        colorValue: 0xFF123456,
      );
      final plan = _planner.start(
        owner: _owner('owner-a', 1),
        participants: [participant],
        primaryModel: 'primary-model',
        config: const ParticipantTurnConfig(
          depth: ParticipantTurnDepth.multiRound,
          maxRounds: 4,
        ),
      );

      expect(plan.runtime!.activeParticipantId, 'speaker');
      expect(plan.runtime!.activeParticipantName, 'Speaker Name');
      expect(plan.runtime!.activeParticipantRoleLabel, 'Reviewer');
      expect(plan.runtime!.activeParticipantColorValue, 0xFF123456);
      expect(plan.runtime!.currentRound, 1);
      expect(plan.runtime!.maxRounds, 4);
      expect(plan.runtime!.multiRound, isTrue);
      expect(plan.runtime!.stopRequested, isFalse);
      expect(plan.runtime!.paused, isFalse);
      expect(plan.runtime!.activeToolName, isEmpty);
    });

    test('clears a one-shot preference when the cursor is complete', () {
      final plan = _planner.start(
        owner: _owner('owner-a', 1),
        participants: [
          _participant('first'),
          _participant('second', endpointId: 'remote', order: 1),
        ],
        primaryModel: 'primary-model',
        config: const ParticipantTurnConfig(),
        cursor: const ParticipantTurnCursor(roundIndex: 1),
        preferredParticipantId: 'second',
        lastSpeakerParticipantId: 'first',
        completedContent: 'last response',
      );

      expect(plan.kind, ParticipantTurnStepKind.complete);
      expect(plan.state.cursor.roundIndex, 1);
      expect(plan.state.preferredParticipantId, isNull);
      expect(plan.state.lastSpeakerParticipantId, 'first');
      expect(plan.state.completedContent, 'last response');
      expect(plan.runtime, isNull);
    });

    test('rejects completion input when no participant is pending', () {
      final plan = _planner.start(
        owner: _owner('owner-a', 1),
        participants: [_participant('primary', enabled: false)],
        primaryModel: 'primary-model',
        config: const ParticipantTurnConfig(),
      );

      expect(
        () => _planner.advance(
          state: plan.state,
          completedContent: 'invalid',
          stopRequested: false,
        ),
        throwsStateError,
      );
    });

    test('keeps cursor, handoff, stop, and runtime with the owner', () {
      var ownerPlan = _planner.start(
        owner: _owner('owner-a', 7),
        participants: [
          _participant('owner-a-first'),
          _participant('owner-a-second', endpointId: 'remote', order: 1),
        ],
        primaryModel: 'primary-model',
        config: const ParticipantTurnConfig(),
      );
      final visiblePlan = _planner.start(
        owner: _owner('visible-b', 8),
        participants: [_participant('visible-speaker')],
        primaryModel: 'visible-model',
        config: const ParticipantTurnConfig(),
      );

      ownerPlan = _planner.advance(
        state: ownerPlan.state,
        completedContent: 'owner A content',
        handoffParticipantId: 'owner-a-second',
        stopRequested: true,
      );

      expect(ownerPlan.state.owner, _owner('owner-a', 7));
      expect(ownerPlan.state.cursor.roundIndex, 0);
      expect(ownerPlan.state.cursor.participantIndex, 1);
      expect(ownerPlan.state.preferredParticipantId, 'owner-a-second');
      expect(ownerPlan.state.stopRequested, isTrue);
      expect(ownerPlan.kind, ParticipantTurnStepKind.pause);
      expect(ownerPlan.runtime!.paused, isTrue);
      expect(visiblePlan.state.owner, _owner('visible-b', 8));
      expect(visiblePlan.state.stopRequested, isFalse);
      expect(visiblePlan.state.cursor.roundIndex, 1);
      expect(visiblePlan.participant!.id, 'visible-speaker');
      expect(visiblePlan.runtime!.activeParticipantId, 'visible-speaker');
      expect(visiblePlan.runtime!.paused, isFalse);
    });
  });
}

ConversationParticipant _participant(
  String id, {
  String displayName = '',
  String roleLabel = '',
  String endpointId = '',
  String model = '',
  bool facilitatesTurns = false,
  int colorValue = 0xFF6750A4,
  int order = 0,
  bool enabled = true,
}) => ConversationParticipant(
  id: id,
  displayName: displayName,
  roleLabel: roleLabel,
  endpointId: endpointId,
  model: model,
  facilitatesTurns: facilitatesTurns,
  colorValue: colorValue,
  order: order,
  enabled: enabled,
);

ChatTurnOwner _owner(String conversationId, int generation) => ChatTurnOwner(
  conversationId: conversationId,
  interactionGeneration: generation,
);
