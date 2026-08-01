import 'package:caverno_content_protocol/caverno_content_protocol.dart';

import '../entities/chat_turn_owner.dart';
import '../entities/conversation_participant.dart';
import '../entities/message.dart';
import 'participant_turn_coordinator.dart';
import 'proposal_parsing_text_utils.dart';
import 'truncation_notice.dart';

// ChatNotifier decomposition collaborator: participant-message-finalizer

enum ParticipantMessageFinalizationStatus {
  staleOwner,
  missingMessages,
  droppedEmptyAssistant,
  finalized,
}

enum ParticipantResponseMetricsDisposition { consume, discard }

enum ParticipantVisibleStateDisposition { unchanged, loading, complete }

/// Immutable, owner-bound facts captured before participant finalization.
final class ParticipantMessageFinalizationInput {
  ParticipantMessageFinalizationInput({
    required this.owner,
    required this.ownerIsCurrent,
    required List<Message>? sourceMessages,
    required this.isFinalTurn,
    required this.participant,
    required List<ConversationParticipant> participants,
    required List<String> participantToolNames,
    required this.finishReason,
    required this.isDetached,
    required this.autoReadEnabled,
    required this.ttsEnabled,
  }) : sourceMessages = sourceMessages == null
           ? null
           : List<Message>.unmodifiable(sourceMessages),
       participants = List<ConversationParticipant>.unmodifiable(participants),
       participantToolNames = List<String>.unmodifiable(participantToolNames);

  final ChatTurnOwner owner;
  final bool ownerIsCurrent;
  final List<Message>? sourceMessages;
  final bool isFinalTurn;
  final ConversationParticipant participant;
  final List<ConversationParticipant> participants;
  final List<String> participantToolNames;
  final String finishReason;
  final bool isDetached;
  final bool autoReadEnabled;
  final bool ttsEnabled;
}

/// Immutable first-phase decision made while response metadata still exists.
///
/// The adapter must update token usage first, then either consume or discard
/// response metadata according to [metricsDisposition]. A consume plan must be
/// completed with [ParticipantMessageFinalizer.applyMetrics]. A discard plan
/// must be completed with
/// [ParticipantMessageFinalizer.completeAfterDiscard].
final class ParticipantMessageFinalizationPlan {
  ParticipantMessageFinalizationPlan._({
    required this.owner,
    required this.status,
    required List<Message> preparedMessages,
    required List<int> messageIndexesToSave,
    required this.content,
    required this.handoffTargetParticipantId,
    required this.shouldApplyOwnerMessages,
    required this.shouldPersist,
    required this.shouldUpdateTokenUsage,
    required this.autoReadContent,
    required this.metricsDisposition,
    required this.visibleStateDisposition,
    required int? responseMetricsMessageIndex,
  }) : preparedMessages = List<Message>.unmodifiable(preparedMessages),
       _messageIndexesToSave = List<int>.unmodifiable(messageIndexesToSave),
       _responseMetricsMessageIndex = responseMetricsMessageIndex;

  final ChatTurnOwner owner;
  final ParticipantMessageFinalizationStatus status;
  final List<Message> preparedMessages;
  final String content;
  final String? handoffTargetParticipantId;
  final bool shouldApplyOwnerMessages;
  final bool shouldPersist;
  final bool shouldUpdateTokenUsage;
  final String? autoReadContent;
  final ParticipantResponseMetricsDisposition metricsDisposition;
  final ParticipantVisibleStateDisposition visibleStateDisposition;
  final List<int> _messageIndexesToSave;
  final int? _responseMetricsMessageIndex;

  List<Message> get preparedMessagesToSave => List<Message>.unmodifiable(
    _messageIndexesToSave.map((index) => preparedMessages[index]),
  );

  bool get shouldAutoRead => autoReadContent != null;

  bool get shouldUpdateVisibleState =>
      visibleStateDisposition != ParticipantVisibleStateDisposition.unchanged;

  bool? get visibleIsLoading => switch (visibleStateDisposition) {
    ParticipantVisibleStateDisposition.unchanged => null,
    ParticipantVisibleStateDisposition.loading => true,
    ParticipantVisibleStateDisposition.complete => false,
  };
}

/// Effects that are safe to apply after the metadata disposition is complete.
final class ParticipantMessageFinalizationResult {
  ParticipantMessageFinalizationResult._({
    required ParticipantMessageFinalizationPlan plan,
    required List<Message> updatedMessages,
    required List<Message> messagesToSave,
  }) : _plan = plan,
       updatedMessages = List<Message>.unmodifiable(updatedMessages),
       messagesToSave = List<Message>.unmodifiable(messagesToSave);

  final ParticipantMessageFinalizationPlan _plan;
  final List<Message> updatedMessages;
  final List<Message> messagesToSave;

  ChatTurnOwner get owner => _plan.owner;
  ParticipantMessageFinalizationStatus get status => _plan.status;
  String get content => _plan.content;
  String? get handoffTargetParticipantId => _plan.handoffTargetParticipantId;
  bool get shouldApplyOwnerMessages => _plan.shouldApplyOwnerMessages;
  bool get shouldPersist => _plan.shouldPersist;
  bool get shouldUpdateTokenUsage => _plan.shouldUpdateTokenUsage;
  String? get autoReadContent => _plan.autoReadContent;
  ParticipantResponseMetricsDisposition get metricsDisposition =>
      _plan.metricsDisposition;
  ParticipantVisibleStateDisposition get visibleStateDisposition =>
      _plan.visibleStateDisposition;
  bool get shouldAutoRead => _plan.shouldAutoRead;
  bool get shouldUpdateVisibleState => _plan.shouldUpdateVisibleState;
  bool? get visibleIsLoading => _plan.visibleIsLoading;
}

/// Narrow content policy matching participant finalization visibility rules.
abstract final class ParticipantMessageVisibilityPolicy {
  static bool hasVisibleAssistantContent(String content) {
    if (content.trim().isEmpty) return false;

    final parsed = ContentParser.parse(content);
    for (final segment in parsed.segments) {
      switch (segment.type) {
        case ContentType.text:
        case ContentType.thinking:
          if (segment.content.trim().isNotEmpty) {
            return true;
          }
        case ContentType.toolCall:
          final toolName = segment.toolCall?.name.toLowerCase();
          if (toolName != 'memory_update') {
            return true;
          }
        case ContentType.toolResult:
          continue;
      }
    }
    return false;
  }

  static bool shouldKeepSavedMessage(Message message) {
    return message.role != MessageRole.assistant ||
        message.content.trim().isNotEmpty;
  }
}

/// Plans and completes participant messages without shared mutable state.
final class ParticipantMessageFinalizer {
  const ParticipantMessageFinalizer();

  ParticipantMessageFinalizationPlan plan(
    ParticipantMessageFinalizationInput input,
  ) {
    final sourceMessages = input.sourceMessages;
    if (!input.ownerIsCurrent) {
      return _inactivePlan(
        input,
        ParticipantMessageFinalizationStatus.staleOwner,
      );
    }
    if (sourceMessages == null || sourceMessages.isEmpty) {
      return _inactivePlan(
        input,
        ParticipantMessageFinalizationStatus.missingMessages,
      );
    }

    final preparedMessages = List<Message>.of(sourceMessages);
    final lastIndex = preparedMessages.length - 1;
    final lastMessage = preparedMessages[lastIndex];
    final isTruncated = ProposalParsingTextUtils.isCompletionTruncated(
      input.finishReason,
    );
    final handoff = isTruncated
        ? null
        : const ParticipantTurnCoordinator().extractHandoffDirective(
            content: lastMessage.content,
            participants: input.participants,
            sourceParticipantId: input.participant.id,
          );
    final handoffTarget = _handoffTarget(handoff, input.participants);
    final visibleContent = handoff?.content ?? lastMessage.content;
    final shouldDropLastAssistant =
        lastMessage.role == MessageRole.assistant &&
        !ParticipantMessageVisibilityPolicy.hasVisibleAssistantContent(
          visibleContent,
        );

    int? responseMetricsMessageIndex;
    if (shouldDropLastAssistant) {
      preparedMessages.removeAt(lastIndex);
    } else {
      final finalizedContent = isTruncated
          ? TruncationNotice.withMaxTokenNotice(visibleContent)
          : visibleContent;
      preparedMessages[lastIndex] = lastMessage.copyWith(
        content: finalizedContent,
        isStreaming: false,
        participantToolNames: _normalizedToolNames(input.participantToolNames),
        handoffTargetParticipantId: handoffTarget?.id,
        handoffTargetDisplayName: handoffTarget?.effectiveDisplayName,
        handoffTargetRoleLabel: handoffTarget?.effectiveRoleLabel,
        responseMetrics: null,
      );
      responseMetricsMessageIndex = lastIndex;
    }

    final messageIndexesToSave = <int>[
      for (var index = 0; index < preparedMessages.length; index++)
        if (!preparedMessages[index].isStreaming &&
            ParticipantMessageVisibilityPolicy.shouldKeepSavedMessage(
              preparedMessages[index],
            ))
          index,
    ];
    final visibleStateDisposition = input.isDetached
        ? ParticipantVisibleStateDisposition.unchanged
        : input.isFinalTurn
        ? ParticipantVisibleStateDisposition.complete
        : ParticipantVisibleStateDisposition.loading;
    final content = shouldDropLastAssistant || preparedMessages.isEmpty
        ? ''
        : preparedMessages.last.content;
    final autoReadContent =
        !shouldDropLastAssistant &&
            !input.isDetached &&
            input.isFinalTurn &&
            input.autoReadEnabled &&
            input.ttsEnabled &&
            content.isNotEmpty
        ? content
        : null;

    return ParticipantMessageFinalizationPlan._(
      owner: input.owner,
      status: shouldDropLastAssistant
          ? ParticipantMessageFinalizationStatus.droppedEmptyAssistant
          : ParticipantMessageFinalizationStatus.finalized,
      preparedMessages: preparedMessages,
      messageIndexesToSave: messageIndexesToSave,
      content: content,
      handoffTargetParticipantId: handoff?.targetParticipantId,
      shouldApplyOwnerMessages: true,
      shouldPersist: true,
      shouldUpdateTokenUsage: true,
      autoReadContent: autoReadContent,
      metricsDisposition: shouldDropLastAssistant
          ? ParticipantResponseMetricsDisposition.discard
          : ParticipantResponseMetricsDisposition.consume,
      visibleStateDisposition: visibleStateDisposition,
      responseMetricsMessageIndex: responseMetricsMessageIndex,
    );
  }

  /// Attaches consumed metrics without repeating content finalization.
  ParticipantMessageFinalizationResult applyMetrics(
    ParticipantMessageFinalizationPlan plan,
    MessageResponseMetrics? responseMetrics,
  ) {
    final messageIndex = plan._responseMetricsMessageIndex;
    if (plan.metricsDisposition !=
            ParticipantResponseMetricsDisposition.consume ||
        messageIndex == null) {
      throw StateError('Response metrics require a consume plan.');
    }
    final updatedMessages = List<Message>.of(plan.preparedMessages);
    updatedMessages[messageIndex] = updatedMessages[messageIndex].copyWith(
      responseMetrics: responseMetrics,
    );
    return _resultFor(plan, updatedMessages);
  }

  /// Completes a plan only after its metadata has been discarded.
  ParticipantMessageFinalizationResult completeAfterDiscard(
    ParticipantMessageFinalizationPlan plan,
  ) {
    if (plan.metricsDisposition !=
        ParticipantResponseMetricsDisposition.discard) {
      throw StateError('Only a discard plan can complete without metrics.');
    }
    return _resultFor(plan, plan.preparedMessages);
  }

  ParticipantMessageFinalizationResult _resultFor(
    ParticipantMessageFinalizationPlan plan,
    List<Message> updatedMessages,
  ) {
    return ParticipantMessageFinalizationResult._(
      plan: plan,
      updatedMessages: updatedMessages,
      messagesToSave: [
        for (final index in plan._messageIndexesToSave) updatedMessages[index],
      ],
    );
  }

  ParticipantMessageFinalizationPlan _inactivePlan(
    ParticipantMessageFinalizationInput input,
    ParticipantMessageFinalizationStatus status,
  ) {
    return ParticipantMessageFinalizationPlan._(
      owner: input.owner,
      status: status,
      preparedMessages: input.sourceMessages ?? const <Message>[],
      messageIndexesToSave: const <int>[],
      content: '',
      handoffTargetParticipantId: null,
      shouldApplyOwnerMessages: false,
      shouldPersist: false,
      shouldUpdateTokenUsage: false,
      autoReadContent: null,
      metricsDisposition: ParticipantResponseMetricsDisposition.discard,
      visibleStateDisposition: ParticipantVisibleStateDisposition.unchanged,
      responseMetricsMessageIndex: null,
    );
  }

  ConversationParticipant? _handoffTarget(
    ParticipantTurnHandoff? handoff,
    List<ConversationParticipant> participants,
  ) {
    final targetId = handoff?.targetParticipantId?.trim();
    if (targetId == null || targetId.isEmpty) return null;
    for (final participant in participants) {
      if (participant.id == targetId) return participant;
    }
    return null;
  }

  List<String> _normalizedToolNames(List<String> toolNames) {
    return toolNames
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }
}
