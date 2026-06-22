import '../entities/conversation_participant.dart';
import '../entities/message.dart';

class ParticipantTurnCursor {
  const ParticipantTurnCursor({this.roundIndex = 0, this.participantIndex = 0});

  final int roundIndex;
  final int participantIndex;

  ParticipantTurnCursor copyWith({int? roundIndex, int? participantIndex}) {
    return ParticipantTurnCursor(
      roundIndex: roundIndex ?? this.roundIndex,
      participantIndex: participantIndex ?? this.participantIndex,
    );
  }
}

class ParticipantTurnDecision {
  const ParticipantTurnDecision({
    required this.participant,
    required this.cursor,
    required this.roundNumber,
    required this.completed,
    required this.paused,
  });

  final ConversationParticipant? participant;
  final ParticipantTurnCursor cursor;
  final int roundNumber;
  final bool completed;
  final bool paused;

  bool get hasParticipant => participant != null;
}

class ParticipantTurnCoordinator {
  const ParticipantTurnCoordinator();

  static const primaryParticipantId = 'primary_assistant';

  List<ConversationParticipant> normalizeParticipants({
    required List<ConversationParticipant> participants,
    required String primaryModel,
  }) {
    final hasNonPrimary = participants.any((participant) {
      return participant.endpointId.trim().isNotEmpty;
    });
    if (!hasNonPrimary ||
        participants.any((participant) => participant.isPrimary)) {
      return orderedEnabledOrDisabled(participants);
    }

    final existingIds = participants
        .map((participant) => participant.id)
        .toSet();
    final primaryId = _uniqueId(primaryParticipantId, existingIds);
    return orderedEnabledOrDisabled([
      ConversationParticipant(
        id: primaryId,
        displayName: 'Primary Assistant',
        roleLabel: 'Facilitator',
        roleSystemPrompt:
            'Facilitate the discussion and help the participants converge on useful next steps.',
        model: primaryModel,
        order: 0,
        colorValue: 0xFF6750A4,
      ),
      ...participants,
    ]);
  }

  List<ConversationParticipant> orderedEnabledParticipants(
    List<ConversationParticipant> participants,
  ) {
    return orderedEnabledOrDisabled(
      participants.where((participant) => participant.enabled).toList(),
    );
  }

  List<ConversationParticipant> orderedEnabledOrDisabled(
    List<ConversationParticipant> participants,
  ) {
    final ordered = [...participants];
    ordered.sort((a, b) {
      final orderCompare = a.order.compareTo(b.order);
      if (orderCompare != 0) return orderCompare;
      if (a.isPrimary != b.isPrimary) return a.isPrimary ? -1 : 1;
      return a.id.compareTo(b.id);
    });
    return ordered;
  }

  ParticipantTurnDecision nextSpeaker({
    required List<ConversationParticipant> participants,
    required ParticipantTurnConfig config,
    ParticipantTurnCursor cursor = const ParticipantTurnCursor(),
    bool stopRequested = false,
  }) {
    final enabled = orderedEnabledParticipants(participants);
    if (enabled.isEmpty) {
      return ParticipantTurnDecision(
        participant: null,
        cursor: cursor,
        roundNumber: cursor.roundIndex + 1,
        completed: true,
        paused: false,
      );
    }

    if (stopRequested) {
      return ParticipantTurnDecision(
        participant: null,
        cursor: cursor,
        roundNumber: cursor.roundIndex + 1,
        completed: false,
        paused: true,
      );
    }

    final maxRounds = _effectiveMaxRounds(config);
    if (cursor.roundIndex >= maxRounds) {
      return ParticipantTurnDecision(
        participant: null,
        cursor: ParticipantTurnCursor(roundIndex: maxRounds),
        roundNumber: maxRounds,
        completed: true,
        paused: false,
      );
    }

    final participantIndex = cursor.participantIndex.clamp(
      0,
      enabled.length - 1,
    );
    final participant = enabled[participantIndex];
    var nextParticipantIndex = participantIndex + 1;
    var nextRoundIndex = cursor.roundIndex;
    if (nextParticipantIndex >= enabled.length) {
      nextParticipantIndex = 0;
      nextRoundIndex += 1;
    }

    final completedAfterTurn = nextRoundIndex >= maxRounds;
    return ParticipantTurnDecision(
      participant: participant,
      cursor: ParticipantTurnCursor(
        roundIndex: nextRoundIndex,
        participantIndex: nextParticipantIndex,
      ),
      roundNumber: cursor.roundIndex + 1,
      completed: completedAfterTurn,
      paused: false,
    );
  }

  List<Message> buildMessagesForParticipant({
    required ConversationParticipant target,
    required List<Message> transcript,
    required List<ConversationParticipant> participants,
    bool includeRolePrompt = true,
  }) {
    final participantsById = {
      for (final participant in participants) participant.id: participant,
    };
    final messages = <Message>[];
    final rolePrompt = target.roleSystemPrompt.trim();
    if (includeRolePrompt && rolePrompt.isNotEmpty) {
      messages.add(
        Message(
          id: 'participant_role_prompt_${target.id}',
          content: rolePrompt,
          role: MessageRole.system,
          timestamp: DateTime.fromMillisecondsSinceEpoch(0),
        ),
      );
    }

    for (final message in transcript) {
      messages.add(
        _messageForParticipantView(
          target: target,
          message: message,
          participantsById: participantsById,
        ),
      );
    }
    return messages;
  }

  Message _messageForParticipantView({
    required ConversationParticipant target,
    required Message message,
    required Map<String, ConversationParticipant> participantsById,
  }) {
    if (message.role == MessageRole.system) {
      return message;
    }

    final isOwnParticipantTurn = message.participantId == target.id;
    final isLegacyPrimaryAssistantTurn =
        target.isPrimary &&
        message.participantId == null &&
        message.role == MessageRole.assistant;
    if (isOwnParticipantTurn || isLegacyPrimaryAssistantTurn) {
      return message.copyWith(role: MessageRole.assistant);
    }

    final speakerLabel = _speakerLabelFor(message, participantsById);
    return message.copyWith(
      role: MessageRole.user,
      content: '[$speakerLabel]: ${message.content}',
    );
  }

  String _speakerLabelFor(
    Message message,
    Map<String, ConversationParticipant> participantsById,
  ) {
    if (message.role == MessageRole.user && message.participantId == null) {
      return 'User';
    }

    final snapshotName = message.participantDisplayName?.trim() ?? '';
    final snapshotRole = message.participantRoleLabel?.trim() ?? '';
    final participant = message.participantId == null
        ? null
        : participantsById[message.participantId];
    final name = snapshotName.isNotEmpty
        ? snapshotName
        : (participant?.effectiveDisplayName ?? 'Assistant');
    final role = snapshotRole.isNotEmpty
        ? snapshotRole
        : (participant?.effectiveRoleLabel ?? '');
    return role.isEmpty ? name : '$name · $role';
  }

  int _effectiveMaxRounds(ParticipantTurnConfig config) {
    if (config.depth == ParticipantTurnDepth.singleRound) {
      return 1;
    }
    return config.maxRounds < 1 ? 1 : config.maxRounds;
  }

  String _uniqueId(String baseId, Set<String> existingIds) {
    if (!existingIds.contains(baseId)) {
      return baseId;
    }
    var suffix = 2;
    while (existingIds.contains('${baseId}_$suffix')) {
      suffix += 1;
    }
    return '${baseId}_$suffix';
  }
}
