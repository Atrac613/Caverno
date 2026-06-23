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

class ParticipantTurnHandoff {
  const ParticipantTurnHandoff({
    required this.targetLabel,
    required this.content,
    this.targetParticipantId,
  });

  final String targetLabel;
  final String content;
  final String? targetParticipantId;
}

class ParticipantTurnCoordinator {
  const ParticipantTurnCoordinator();

  static const primaryParticipantId = 'primary_assistant';
  static final RegExp _handoffLinePattern = RegExp(
    r'^\s*Handoff\s*:\s*(.+?)\s*$',
    caseSensitive: false,
  );

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
        facilitatesTurns: true,
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
    String? preferredParticipantId,
    String? lastSpeakerParticipantId,
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
    final facilitator = _facilitatorFor(enabled);
    if (facilitator != null) {
      return _facilitatorManagedDecision(
        enabled: enabled,
        facilitator: facilitator,
        cursor: cursor,
        maxRounds: maxRounds,
        preferredParticipantId: preferredParticipantId,
        lastSpeakerParticipantId: lastSpeakerParticipantId,
      );
    }

    final preferredCursor = _cursorForPreferredParticipant(
      enabled: enabled,
      cursor: cursor,
      maxRounds: maxRounds,
      preferredParticipantId: preferredParticipantId,
    );
    final effectiveCursor = preferredCursor ?? cursor;
    return _roundRobinDecision(
      enabled: enabled,
      cursor: effectiveCursor,
      maxRounds: maxRounds,
    );
  }

  ParticipantTurnDecision _facilitatorManagedDecision({
    required List<ConversationParticipant> enabled,
    required ConversationParticipant facilitator,
    required ParticipantTurnCursor cursor,
    required int maxRounds,
    required String? preferredParticipantId,
    required String? lastSpeakerParticipantId,
  }) {
    final facilitatorIndex = enabled.indexWhere(
      (participant) => participant.id == facilitator.id,
    );
    final preferredIndex = lastSpeakerParticipantId == facilitator.id
        ? _preferredParticipantIndex(
            enabled: enabled,
            preferredParticipantId: preferredParticipantId,
            excludedParticipantId: facilitator.id,
          )
        : null;
    if (preferredIndex != null) {
      return ParticipantTurnDecision(
        participant: enabled[preferredIndex],
        cursor: cursor.copyWith(participantIndex: preferredIndex),
        roundNumber: cursor.roundIndex < 1 ? 1 : cursor.roundIndex,
        completed: false,
        paused: false,
      );
    }

    if (lastSpeakerParticipantId == facilitator.id) {
      return _completedDecision(cursor: cursor, maxRounds: maxRounds);
    }

    if (cursor.roundIndex >= maxRounds) {
      return _completedDecision(cursor: cursor, maxRounds: maxRounds);
    }

    final nextRoundIndex = cursor.roundIndex + 1;
    return ParticipantTurnDecision(
      participant: facilitator,
      cursor: ParticipantTurnCursor(
        roundIndex: nextRoundIndex,
        participantIndex: facilitatorIndex < 0 ? 0 : facilitatorIndex,
      ),
      roundNumber: nextRoundIndex,
      completed: false,
      paused: false,
    );
  }

  ParticipantTurnDecision _roundRobinDecision({
    required List<ConversationParticipant> enabled,
    required ParticipantTurnCursor cursor,
    required int maxRounds,
  }) {
    if (cursor.roundIndex >= maxRounds) {
      return _completedDecision(cursor: cursor, maxRounds: maxRounds);
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

  ParticipantTurnDecision _completedDecision({
    required ParticipantTurnCursor cursor,
    required int maxRounds,
  }) {
    return ParticipantTurnDecision(
      participant: null,
      cursor: ParticipantTurnCursor(roundIndex: maxRounds),
      roundNumber: cursor.roundIndex < 1 ? 1 : cursor.roundIndex,
      completed: true,
      paused: false,
    );
  }

  int? _preferredParticipantIndex({
    required List<ConversationParticipant> enabled,
    required String? preferredParticipantId,
    String? excludedParticipantId,
  }) {
    final normalizedPreferredId = preferredParticipantId?.trim();
    if (normalizedPreferredId == null || normalizedPreferredId.isEmpty) {
      return null;
    }
    final index = enabled.indexWhere((participant) {
      return participant.id == normalizedPreferredId &&
          participant.id != excludedParticipantId;
    });
    return index < 0 ? null : index;
  }

  ParticipantTurnCursor? _cursorForPreferredParticipant({
    required List<ConversationParticipant> enabled,
    required ParticipantTurnCursor cursor,
    required int maxRounds,
    required String? preferredParticipantId,
  }) {
    final normalizedPreferredId = preferredParticipantId?.trim();
    if (normalizedPreferredId == null || normalizedPreferredId.isEmpty) {
      return null;
    }

    final preferredIndex = enabled.indexWhere(
      (participant) => participant.id == normalizedPreferredId,
    );
    if (preferredIndex < 0) {
      return null;
    }

    final preferredRoundIndex = preferredIndex < cursor.participantIndex
        ? cursor.roundIndex + 1
        : cursor.roundIndex;
    if (preferredRoundIndex >= maxRounds) {
      return null;
    }
    return ParticipantTurnCursor(
      roundIndex: preferredRoundIndex,
      participantIndex: preferredIndex,
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
    final rolePrompt = buildRolePromptForParticipant(
      target: target,
      participants: participants,
    );
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

  String buildRolePromptForParticipant({
    required ConversationParticipant target,
    required List<ConversationParticipant> participants,
  }) {
    final lines = <String>[
      'You are participating in a shared multi-participant conversation.',
      'Your participant identity:',
      '- Name: ${target.effectiveDisplayName}',
      '- Role: ${target.effectiveRoleLabel}',
    ];
    final otherParticipants = orderedEnabledOrDisabled(participants)
        .where((participant) => participant.id != target.id)
        .map(_participantLabel)
        .where((label) => label.isNotEmpty)
        .toList(growable: false);
    if (otherParticipants.isNotEmpty) {
      lines.add('Other participants available in this conversation:');
      lines.addAll(otherParticipants.map((label) => '- $label'));
    }
    final hasFacilitator = participants.any(_isFacilitator);
    final targetIsFacilitator = _isFacilitator(target);
    lines.addAll([
      'Speak from your assigned identity and role. Do not answer as another participant.',
      'When another participant is better suited to address a point, name that participant or role and yield the floor instead of taking over their contribution.',
    ]);
    if (targetIsFacilitator) {
      lines.addAll([
        'As facilitator, manage the floor: frame the question, invite the most relevant participant to speak, synthesize contributions, and keep the group moving. You may add your own view when it clarifies or unblocks the discussion, but prefer delegation when a specialist participant is available.',
        'To explicitly hand off the next turn, end your response with exactly one routing line: "Handoff: <participant name or role>". Use only participants listed above; the routing line is removed from the visible transcript.',
        'Before that routing line, include a visible natural invitation addressed to the target participant, such as "Senior Engineer, what do you think about this implementation risk?" so the user can see why the next speaker is responding.',
        'Do not include a handoff line when asking the user a question or requesting clarification; that returns the floor to the user.',
        'Do not mix an unresolved user-facing choice or confirmation request with a participant handoff in the same response.',
        'If no participant needs to speak next, do not include a handoff line; the floor returns to the user.',
      ]);
    } else if (hasFacilitator) {
      lines.add(
        'A facilitator is managing the floor. Answer only the point you were handed, do not route the next turn yourself, and let the facilitator decide whether anyone else should speak.',
      );
    } else {
      lines.add(
        'To explicitly hand off the next turn, end your response with exactly one routing line: "Handoff: <participant name or role>". Use only participants listed above; the routing line is removed from the visible transcript.',
      );
    }

    final rolePrompt = target.roleSystemPrompt.trim();
    if (rolePrompt.isNotEmpty) {
      lines
        ..add('Role-specific instructions:')
        ..add(rolePrompt);
    }
    return lines.join('\n');
  }

  ParticipantTurnHandoff? extractHandoffDirective({
    required String content,
    required List<ConversationParticipant> participants,
    String? sourceParticipantId,
  }) {
    final lines = content.split('\n');
    var directiveIndex = lines.length - 1;
    while (directiveIndex >= 0 && lines[directiveIndex].trim().isEmpty) {
      directiveIndex -= 1;
    }
    if (directiveIndex < 0) {
      return null;
    }

    final match = _handoffLinePattern.firstMatch(lines[directiveIndex]);
    if (match == null) {
      return _extractImplicitHandoffFromInvitation(
        content: content,
        participants: participants,
        sourceParticipantId: sourceParticipantId,
      );
    }

    final targetLabel = match.group(1)?.trim() ?? '';
    if (targetLabel.isEmpty) {
      return null;
    }

    final visibleLines = lines.take(directiveIndex).toList();
    while (visibleLines.isNotEmpty && visibleLines.last.trim().isEmpty) {
      visibleLines.removeLast();
    }
    final visibleContent = visibleLines.join('\n').trimRight();
    final sourceParticipant = _participantById(
      participants,
      sourceParticipantId,
    );
    final targetParticipantId = _resolveHandoffParticipantId(
      targetLabel: targetLabel,
      participants: participants,
      sourceParticipantId: sourceParticipantId,
    );
    final invitesHandoffTarget = _appearsToInviteHandoffTarget(
      content: visibleContent,
      targetLabel: targetLabel,
      targetParticipantId: targetParticipantId,
      participants: participants,
    );
    final invitesPotentialSpeaker = _appearsToInvitePotentialSpeaker(
      content: visibleContent,
      targetParticipantId: targetParticipantId,
    );
    final ignoreLastLineForUserDecision =
        invitesHandoffTarget || invitesPotentialSpeaker;
    final asksUserForDecision =
        sourceParticipant != null &&
        _isFacilitator(sourceParticipant) &&
        _appearsToAskUserForDecision(
          content: visibleContent,
          ignoreLastLine: ignoreLastLineForUserDecision,
        );
    final returnsFloorToUser =
        asksUserForDecision ||
        (sourceParticipant != null &&
            _isFacilitator(sourceParticipant) &&
            _appearsToReturnFloorToUser(visibleContent) &&
            !ignoreLastLineForUserDecision);
    final cleanedVisibleContent =
        asksUserForDecision && ignoreLastLineForUserDecision
        ? _contentBeforeLastNonEmptyLine(visibleContent)
        : visibleContent;

    return ParticipantTurnHandoff(
      targetLabel: targetLabel,
      content: cleanedVisibleContent,
      targetParticipantId: returnsFloorToUser ? null : targetParticipantId,
    );
  }

  ParticipantTurnHandoff? _extractImplicitHandoffFromInvitation({
    required String content,
    required List<ConversationParticipant> participants,
    required String? sourceParticipantId,
  }) {
    final sourceParticipant = _participantById(
      participants,
      sourceParticipantId,
    );
    if (sourceParticipant == null || !_isFacilitator(sourceParticipant)) {
      return null;
    }
    final targetParticipant = _participantInvitedByLastLine(
      content: content,
      participants: participants,
      sourceParticipantId: sourceParticipantId,
    );
    if (targetParticipant == null) {
      return null;
    }
    final asksUserForDecision = _appearsToAskUserForDecision(
      content: content,
      ignoreLastLine: true,
    );
    return ParticipantTurnHandoff(
      targetLabel: targetParticipant.effectiveRoleLabel.isEmpty
          ? targetParticipant.effectiveDisplayName
          : targetParticipant.effectiveRoleLabel,
      content: asksUserForDecision
          ? _contentBeforeLastNonEmptyLine(content)
          : content.trimRight(),
      targetParticipantId: asksUserForDecision ? null : targetParticipant.id,
    );
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

  String _participantLabel(ConversationParticipant participant) {
    final name = participant.effectiveDisplayName;
    final role = participant.effectiveRoleLabel;
    return role.isEmpty ? name : '$name · $role';
  }

  bool _isFacilitator(ConversationParticipant participant) {
    return participant.isTurnFacilitator;
  }

  ConversationParticipant? _facilitatorFor(
    List<ConversationParticipant> participants,
  ) {
    for (final participant in orderedEnabledParticipants(participants)) {
      if (_isFacilitator(participant)) {
        return participant;
      }
    }
    return null;
  }

  ConversationParticipant? _participantById(
    List<ConversationParticipant> participants,
    String? participantId,
  ) {
    final normalizedParticipantId = participantId?.trim();
    if (normalizedParticipantId == null || normalizedParticipantId.isEmpty) {
      return null;
    }
    for (final participant in participants) {
      if (participant.id == normalizedParticipantId) {
        return participant;
      }
    }
    return null;
  }

  bool _appearsToReturnFloorToUser(String content) {
    final trimmed = content.trimRight();
    if (trimmed.isEmpty) {
      return false;
    }
    return trimmed.endsWith('?') || trimmed.runes.last == 0xFF1F;
  }

  bool _appearsToAskUserForDecision({
    required String content,
    required bool ignoreLastLine,
  }) {
    final text = ignoreLastLine
        ? _contentBeforeLastNonEmptyLine(content)
        : content;
    final normalized = text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.trim().isEmpty) {
      return false;
    }

    final englishDecisionPrompts = <RegExp>[
      RegExp(r'\bwhich\b.{0,120}\b(start|choose|option|scenario|approach)\b'),
      RegExp(r'\bwhat\b.{0,120}\b(would you like|do you want|should we)\b'),
      RegExp(r'\bplease (choose|select|tell me|let me know)\b'),
      RegExp(r'\b(let me know|tell me)\b.{0,120}\b(which|what|whether|if)\b'),
      RegExp(r'\bdo you want\b'),
      RegExp(r'\bwould you like\b'),
    ];
    if (englishDecisionPrompts.any((pattern) => pattern.hasMatch(normalized))) {
      return true;
    }

    return _containsJapaneseDecisionPrompt(normalized);
  }

  bool _containsJapaneseDecisionPrompt(String text) {
    final please = String.fromCharCodes([0x304f, 0x3060, 0x3055, 0x3044]);
    if (!text.contains(please)) {
      return false;
    }
    final decisionMarkers = <String>[
      String.fromCharCodes([0x3069, 0x306e]),
      String.fromCharCodes([0x3069, 0x3093, 0x306a]),
      String.fromCharCodes([0x3069, 0x3061, 0x3089]),
      String.fromCharCodes([0x3069, 0x308c]),
      String.fromCharCodes([0x3054, 0x6307, 0x793a]),
      String.fromCharCodes([0x6559, 0x3048, 0x3066]),
      String.fromCharCodes([0x9078, 0x3093, 0x3067]),
      String.fromCharCodes([0x8a71, 0x3057, 0x304b, 0x3051, 0x3066]),
    ];
    return decisionMarkers.any(text.contains);
  }

  bool _appearsToInviteHandoffTarget({
    required String content,
    required String targetLabel,
    required String? targetParticipantId,
    required List<ConversationParticipant> participants,
  }) {
    final lastLine = _lastNonEmptyLine(content);
    if (lastLine == null) {
      return false;
    }
    final targetParticipant = _participantById(
      participants,
      targetParticipantId,
    );
    final aliases = <String>{
      targetLabel,
      if (targetParticipant != null) ...{
        targetParticipant.id,
        targetParticipant.effectiveDisplayName,
        targetParticipant.effectiveRoleLabel,
        _participantLabel(targetParticipant),
        '${targetParticipant.effectiveDisplayName} ${targetParticipant.effectiveRoleLabel}',
        '${targetParticipant.effectiveRoleLabel} ${targetParticipant.effectiveDisplayName}',
      },
    };
    return aliases.any((alias) => _lineStartsWithAlias(lastLine, alias));
  }

  ConversationParticipant? _participantInvitedByLastLine({
    required String content,
    required List<ConversationParticipant> participants,
    required String? sourceParticipantId,
  }) {
    final lastLine = _lastNonEmptyLine(content);
    if (lastLine == null) {
      return null;
    }
    for (final participant in orderedEnabledParticipants(participants)) {
      if (participant.id == sourceParticipantId) {
        continue;
      }
      final aliases = <String>{
        participant.id,
        participant.effectiveDisplayName,
        participant.effectiveRoleLabel,
        _participantLabel(participant),
        '${participant.effectiveDisplayName} ${participant.effectiveRoleLabel}',
        '${participant.effectiveRoleLabel} ${participant.effectiveDisplayName}',
      };
      for (final alias in aliases) {
        final remainder = _lineRemainderAfterAlias(lastLine, alias);
        if (remainder != null && _appearsToRequestResponse(remainder)) {
          return participant;
        }
      }
    }
    return null;
  }

  bool _appearsToInvitePotentialSpeaker({
    required String content,
    required String? targetParticipantId,
  }) {
    if (targetParticipantId == null) {
      return false;
    }
    final lastLine = _lastNonEmptyLine(content);
    if (lastLine == null) {
      return false;
    }
    final separatorIndex = _vocativeSeparatorIndex(lastLine);
    if (separatorIndex <= 0) {
      return false;
    }
    final prefix = lastLine.substring(0, separatorIndex).trim();
    if (prefix.isEmpty || prefix.runes.length > 48) {
      return false;
    }
    final remainder = lastLine.substring(separatorIndex + 1).trim();
    if (remainder.isEmpty) {
      return false;
    }
    return _appearsToRequestResponse(remainder);
  }

  String? _lineRemainderAfterAlias(String line, String alias) {
    final trimmedAlias = alias.trim();
    if (trimmedAlias.isEmpty) {
      return null;
    }
    final lowerLine = line.trimLeft().toLowerCase();
    final lowerAlias = trimmedAlias.toLowerCase();
    if (!lowerLine.startsWith(lowerAlias)) {
      return null;
    }
    final remainder = line.trimLeft().substring(trimmedAlias.length).trimLeft();
    if (remainder.isEmpty) {
      return null;
    }
    final firstRune = remainder.runes.first;
    const comma = 0x2C;
    const colon = 0x3A;
    const japaneseComma = 0x3001;
    const fullWidthColon = 0xFF1A;
    if (firstRune != comma &&
        firstRune != colon &&
        firstRune != japaneseComma &&
        firstRune != fullWidthColon) {
      return null;
    }
    return remainder
        .substring(String.fromCharCode(firstRune).length)
        .trimLeft();
  }

  int _vocativeSeparatorIndex(String line) {
    const comma = 0x2C;
    const colon = 0x3A;
    const japaneseComma = 0x3001;
    const fullWidthColon = 0xFF1A;
    final runes = line.runes.toList(growable: false);
    for (var index = 0; index < runes.length; index += 1) {
      final rune = runes[index];
      if (rune == comma ||
          rune == colon ||
          rune == japaneseComma ||
          rune == fullWidthColon) {
        return index;
      }
    }
    return -1;
  }

  bool _appearsToRequestResponse(String content) {
    final normalized = content.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.contains('?') || normalized.runes.contains(0xFF1F)) {
      return true;
    }
    final englishResponsePrompts = <RegExp>[
      RegExp(r'\bwhat\b.{0,120}\b(think|highlight|recommend|suggest)\b'),
      RegExp(r'\bhow\b.{0,120}\b(would|should|could|do)\b'),
      RegExp(r'\bplease (respond|review|explain|weigh in|comment)\b'),
      RegExp(r'\b(can|could|would) you\b.{0,120}\b(share|explain|review)\b'),
    ];
    if (englishResponsePrompts.any((pattern) => pattern.hasMatch(normalized))) {
      return true;
    }
    return _containsJapaneseResponsePrompt(normalized);
  }

  bool _containsJapaneseResponsePrompt(String text) {
    final please = String.fromCharCodes([0x304f, 0x3060, 0x3055, 0x3044]);
    final request = String.fromCharCodes([0x304a, 0x9858, 0x3044]);
    if (!text.contains(please) && !text.contains(request)) {
      return false;
    }
    final responseMarkers = <String>[
      String.fromCharCodes([0x6559, 0x3048, 0x3066]),
      String.fromCharCodes([0x601d, 0x3044, 0x307e, 0x3059]),
      String.fromCharCodes([0x3054, 0x5b58, 0x77e5]),
      String.fromCharCodes([0x8a71, 0x3057, 0x3066]),
      String.fromCharCodes([0x8aac, 0x660e]),
      String.fromCharCodes([0x805e, 0x304b, 0x305b]),
    ];
    return responseMarkers.any(text.contains);
  }

  String? _lastNonEmptyLine(String content) {
    final lines = content.split('\n');
    for (var index = lines.length - 1; index >= 0; index -= 1) {
      final line = lines[index].trim();
      if (line.isNotEmpty) {
        return line;
      }
    }
    return null;
  }

  String _contentBeforeLastNonEmptyLine(String content) {
    final lines = content.split('\n');
    for (var index = lines.length - 1; index >= 0; index -= 1) {
      if (lines[index].trim().isNotEmpty) {
        lines.removeAt(index);
        break;
      }
    }
    while (lines.isNotEmpty && lines.last.trim().isEmpty) {
      lines.removeLast();
    }
    return lines.join('\n').trimRight();
  }

  bool _lineStartsWithAlias(String line, String alias) {
    final normalizedLine = _normalizeHandoffLabel(line);
    final normalizedAlias = _normalizeHandoffLabel(alias);
    if (normalizedLine.isNotEmpty && normalizedAlias.isNotEmpty) {
      return normalizedLine == normalizedAlias ||
          normalizedLine.startsWith('$normalizedAlias ');
    }

    final loweredLine = line.toLowerCase();
    final loweredAlias = alias.trim().toLowerCase();
    return loweredAlias.isNotEmpty && loweredLine.startsWith(loweredAlias);
  }

  String? _resolveHandoffParticipantId({
    required String targetLabel,
    required List<ConversationParticipant> participants,
    required String? sourceParticipantId,
  }) {
    final normalizedTarget = _normalizeHandoffLabel(targetLabel);
    if (normalizedTarget.isEmpty) {
      return null;
    }

    for (final participant in orderedEnabledParticipants(participants)) {
      if (participant.id == sourceParticipantId) {
        continue;
      }
      final aliases = <String>{
        participant.id,
        participant.effectiveDisplayName,
        participant.effectiveRoleLabel,
        _participantLabel(participant),
        '${participant.effectiveDisplayName} ${participant.effectiveRoleLabel}',
        '${participant.effectiveRoleLabel} ${participant.effectiveDisplayName}',
      };
      if (aliases.any(
        (alias) => _normalizeHandoffLabel(alias) == normalizedTarget,
      )) {
        return participant.id;
      }
    }
    return null;
  }

  String _normalizeHandoffLabel(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
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
