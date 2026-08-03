import '../entities/chat_turn_owner.dart';
import '../entities/conversation_participant.dart';
import 'participant_turn_coordinator.dart';
export 'participant_turn_coordinator.dart';

// ChatNotifier decomposition collaborator: participant-turn-planner
enum ParticipantTurnStepKind {
  noParticipants,
  streamParticipant,
  pause,
  complete,
}

final class ParticipantTurnRuntimeProjection {
  const ParticipantTurnRuntimeProjection({
    required this.activeParticipantId,
    required this.activeParticipantName,
    required this.activeParticipantRoleLabel,
    required this.activeParticipantColorValue,
    required this.currentRound,
    required this.maxRounds,
    required this.multiRound,
    required this.stopRequested,
    required this.paused,
    required this.activeToolName,
  });

  final String? activeParticipantId;
  final String activeParticipantName;
  final String activeParticipantRoleLabel;
  final int? activeParticipantColorValue;
  final int currentRound;
  final int maxRounds;
  final bool multiRound;
  final bool stopRequested;
  final bool paused;
  final String activeToolName;
}

final class ParticipantTurnPlannerState {
  ParticipantTurnPlannerState({
    required this.owner,
    required List<ConversationParticipant> participants,
    required this.config,
    required this.cursor,
    required this.preferredParticipantId,
    required this.lastSpeakerParticipantId,
    required this.completedContent,
    required this.stopRequested,
    required this.currentRound,
    required this.awaitingParticipantId,
    required this.awaitingFinalTurn,
  }) : participants = List<ConversationParticipant>.unmodifiable(participants);

  final ChatTurnOwner owner;
  final List<ConversationParticipant> participants;
  final ParticipantTurnConfig config;
  final ParticipantTurnCursor cursor;
  final String? preferredParticipantId;
  final String? lastSpeakerParticipantId;
  final String completedContent;
  final bool stopRequested;
  final int currentRound;
  final String? awaitingParticipantId;
  final bool awaitingFinalTurn;
}

final class ParticipantTurnPlan {
  const ParticipantTurnPlan({
    required this.kind,
    required this.state,
    required this.participant,
    required this.runtime,
    required this.participantsChanged,
    required this.exitReason,
  });

  final ParticipantTurnStepKind kind;
  final ParticipantTurnPlannerState state;
  final ConversationParticipant? participant;
  final ParticipantTurnRuntimeProjection? runtime;
  final bool participantsChanged;
  final String? exitReason;
}

/// Plans one immutable owner state at a time without retaining runtime state.
final class ParticipantTurnPlanner {
  const ParticipantTurnPlanner();

  ParticipantTurnPlan start({
    required ChatTurnOwner owner,
    required List<ConversationParticipant> participants,
    required String primaryModel,
    required ParticipantTurnConfig config,
    ParticipantTurnCursor cursor = const ParticipantTurnCursor(),
    String? preferredParticipantId,
    String? lastSpeakerParticipantId,
    String completedContent = '',
    bool stopRequested = false,
  }) {
    const coordinator = ParticipantTurnCoordinator();
    final normalized = coordinator.normalizeParticipants(
      participants: participants,
      primaryModel: primaryModel,
    );
    final changed = !_sameParticipants(participants, normalized);
    final state = ParticipantTurnPlannerState(
      owner: owner,
      participants: normalized,
      config: config,
      cursor: cursor,
      preferredParticipantId: preferredParticipantId,
      lastSpeakerParticipantId: lastSpeakerParticipantId,
      completedContent: completedContent,
      stopRequested: stopRequested,
      currentRound: cursor.roundIndex < 1 ? 1 : cursor.roundIndex,
      awaitingParticipantId: null,
      awaitingFinalTurn: false,
    );
    return _plan(state, participantsChanged: changed);
  }

  ParticipantTurnPlan advance({
    required ParticipantTurnPlannerState state,
    required String completedContent,
    String? handoffParticipantId,
    required bool stopRequested,
  }) {
    final participantId = state.awaitingParticipantId;
    if (participantId == null) {
      throw StateError('No participant completion is pending.');
    }
    final completedState = ParticipantTurnPlannerState(
      owner: state.owner,
      participants: state.participants,
      config: state.config,
      cursor: state.cursor,
      preferredParticipantId: handoffParticipantId,
      lastSpeakerParticipantId: participantId,
      completedContent: completedContent,
      stopRequested: stopRequested,
      currentRound: state.currentRound,
      awaitingParticipantId: null,
      awaitingFinalTurn: false,
    );
    if (state.awaitingFinalTurn) {
      return _terminalPlan(
        ParticipantTurnStepKind.complete,
        completedState,
        exitReason: 'participant_turn_completed',
      );
    }
    return _plan(completedState);
  }

  ParticipantTurnPlan _plan(
    ParticipantTurnPlannerState state, {
    bool participantsChanged = false,
  }) {
    const coordinator = ParticipantTurnCoordinator();
    final enabled = coordinator.orderedEnabledParticipants(state.participants);
    if (enabled.isEmpty) {
      return _terminalPlan(
        ParticipantTurnStepKind.noParticipants,
        state,
        participantsChanged: participantsChanged,
        exitReason: 'participant_turn_empty_roster',
      );
    }
    if (state.stopRequested) {
      return ParticipantTurnPlan(
        kind: ParticipantTurnStepKind.pause,
        state: state,
        participant: null,
        runtime: _pausedRuntime(state),
        participantsChanged: participantsChanged,
        exitReason: 'participant_turn_paused',
      );
    }
    final decision = coordinator.nextSpeaker(
      participants: state.participants,
      config: state.config,
      cursor: state.cursor,
      preferredParticipantId: state.preferredParticipantId,
      lastSpeakerParticipantId: state.lastSpeakerParticipantId,
    );
    final participant = decision.participant;
    if (participant == null) {
      final terminalState = ParticipantTurnPlannerState(
        owner: state.owner,
        participants: state.participants,
        config: state.config,
        cursor: decision.cursor,
        preferredParticipantId: null,
        lastSpeakerParticipantId: state.lastSpeakerParticipantId,
        completedContent: state.completedContent,
        stopRequested: state.stopRequested,
        currentRound: decision.roundNumber,
        awaitingParticipantId: null,
        awaitingFinalTurn: false,
      );
      return _terminalPlan(
        ParticipantTurnStepKind.complete,
        terminalState,
        participantsChanged: participantsChanged,
        exitReason: 'participant_turn_completed',
      );
    }
    final nextState = ParticipantTurnPlannerState(
      owner: state.owner,
      participants: state.participants,
      config: state.config,
      cursor: decision.cursor,
      preferredParticipantId: null,
      lastSpeakerParticipantId: state.lastSpeakerParticipantId,
      completedContent: state.completedContent,
      stopRequested: state.stopRequested,
      currentRound: decision.roundNumber,
      awaitingParticipantId: participant.id,
      awaitingFinalTurn: decision.completed,
    );
    return ParticipantTurnPlan(
      kind: ParticipantTurnStepKind.streamParticipant,
      state: nextState,
      participant: participant,
      runtime: _activeRuntime(
        participant: participant,
        config: state.config,
        roundNumber: decision.roundNumber,
        stopRequested: state.stopRequested,
      ),
      participantsChanged: participantsChanged,
      exitReason: null,
    );
  }

  ParticipantTurnPlan _terminalPlan(
    ParticipantTurnStepKind kind,
    ParticipantTurnPlannerState state, {
    bool participantsChanged = false,
    required String exitReason,
  }) => ParticipantTurnPlan(
    kind: kind,
    state: state,
    participant: null,
    runtime: null,
    participantsChanged: participantsChanged,
    exitReason: exitReason,
  );
}

ParticipantTurnRuntimeProjection _activeRuntime({
  required ConversationParticipant participant,
  required ParticipantTurnConfig config,
  required int roundNumber,
  required bool stopRequested,
}) {
  final multiRound = config.depth == ParticipantTurnDepth.multiRound;
  return ParticipantTurnRuntimeProjection(
    activeParticipantId: participant.id,
    activeParticipantName: participant.effectiveDisplayName,
    activeParticipantRoleLabel: participant.effectiveRoleLabel,
    activeParticipantColorValue: participant.colorValue,
    currentRound: roundNumber,
    maxRounds: multiRound ? _clampedMaxRounds(config) : 1,
    multiRound: multiRound,
    stopRequested: stopRequested,
    paused: false,
    activeToolName: '',
  );
}

ParticipantTurnRuntimeProjection _pausedRuntime(
  ParticipantTurnPlannerState state,
) => ParticipantTurnRuntimeProjection(
  activeParticipantId: null,
  activeParticipantName: '',
  activeParticipantRoleLabel: '',
  activeParticipantColorValue: null,
  currentRound: state.currentRound,
  maxRounds: state.config.depth == ParticipantTurnDepth.multiRound
      ? _clampedMaxRounds(state.config)
      : 1,
  multiRound: state.config.depth == ParticipantTurnDepth.multiRound,
  stopRequested: true,
  paused: true,
  activeToolName: '',
);

int _clampedMaxRounds(ParticipantTurnConfig config) =>
    config.maxRounds < 1 ? 1 : config.maxRounds;

bool _sameParticipants(
  List<ConversationParticipant> left,
  List<ConversationParticipant> right,
) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
