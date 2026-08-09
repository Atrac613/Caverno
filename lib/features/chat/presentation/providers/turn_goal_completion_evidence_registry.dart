import '../../data/datasources/llm_session_log_store.dart';
import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/entities/tool_call_info.dart';
import '../../domain/services/goal_update_ack.dart';
import '../../domain/services/tool_result_prompt_builder.dart';
import 'turn_finalization_state_registry.dart';

typedef GoalTurnRecorder =
    Future<bool> Function({
      required String assistantResponse,
      required int tokenUsageDelta,
      required ToolResultCompletionEvidence completionEvidence,
      required bool toolCompletionClaimed,
      required String conversationId,
    });
typedef GoalCompletionShadowRecorder =
    Future<void> Function({
      required bool lexicalCompleted,
      required ChatTurnOwner owner,
      required LlmSessionLogContext context,
      required GoalUpdateAckOutcome? toolCompletionOutcome,
    });

/// Owns goal-completion evidence for explicitly registered turn owners.
///
/// Mutations never create state. Disposed owners reject late writes so
/// asynchronous callbacks cannot resurrect completed-turn evidence.
final class TurnGoalCompletionEvidenceRegistry {
  final Map<ChatTurnOwner, ToolResultCompletionEvidence> _evidenceByOwner =
      <ChatTurnOwner, ToolResultCompletionEvidence>{};
  final Map<String, int> _disposedGenerationWatermarks = <String, int>{};
  int get length => _evidenceByOwner.length;
  bool get isEmpty => _evidenceByOwner.isEmpty;

  bool contains(ChatTurnOwner owner) => _evidenceByOwner.containsKey(owner);

  bool begin(
    ChatTurnOwner owner, {
    ToolResultCompletionEvidence initialEvidence =
        const ToolResultCompletionEvidence(),
  }) {
    final disposedThrough =
        _disposedGenerationWatermarks[owner.conversationId] ?? 0;
    if (owner.interactionGeneration <= disposedThrough ||
        _evidenceByOwner.containsKey(owner)) {
      return false;
    }
    _evidenceByOwner[owner] = initialEvidence;
    return true;
  }

  ToolResultCompletionEvidence? evidenceFor(ChatTurnOwner owner) =>
      _evidenceByOwner[owner];

  ToolResultCompletionEvidence combinedToolResultsFor(
    ChatTurnOwner owner,
    List<ToolResultInfo> toolResults,
  ) => ToolResultPromptBuilder.completionEvidence(toolResults)
      .carryForwardIncompleteFrom(
        _evidenceByOwner[owner] ?? const ToolResultCompletionEvidence(),
      );

  ToolResultCompletionEvidence replaceWithToolResults(
    ChatTurnOwner owner,
    List<ToolResultInfo> toolResults,
  ) => replaceWithCombinedEvidence(
    owner,
    ToolResultPromptBuilder.completionEvidence(toolResults),
  );

  ToolResultCompletionEvidence replaceWithCombinedEvidence(
    ChatTurnOwner owner,
    ToolResultCompletionEvidence evidence,
  ) {
    final combined = evidence.carryForwardIncompleteFrom(
      _evidenceByOwner[owner] ?? const ToolResultCompletionEvidence(),
    );
    replace(owner, combined);
    return combined;
  }

  ToolResultCompletionEvidence reconcileForFinalization(
    ChatTurnOwner owner, {
    required List<ToolResultInfo> completedToolResults,
    required List<ToolResultInfo> contentToolResults,
    int? mutationGeneration,
    int? verificationGeneration,
  }) {
    var evidence = ToolResultPromptBuilder.reconcileFinalizationEvidence(
      authoritativeEvidence:
          _evidenceByOwner[owner] ?? const ToolResultCompletionEvidence(),
      completedToolResults: completedToolResults,
      contentToolResults: contentToolResults,
    );
    if (mutationGeneration != null && verificationGeneration != null) {
      evidence = evidence.settleForExecutionGenerations(
        mutationGeneration: mutationGeneration,
        verificationGeneration: verificationGeneration,
      );
    }
    replace(owner, evidence);
    return evidence;
  }

  ToolResultCompletionEvidence settleSuccessfulSavedValidation(
    ToolResultCompletionEvidence evidence, {
    required Conversation? conversation,
    required bool succeeded,
  }) {
    if (!succeeded || evidence.hasBlockingEvidence || conversation == null) {
      return evidence;
    }
    return evidence.settleForExecutionGenerations(
      mutationGeneration: conversation.mutationGeneration,
      verificationGeneration: conversation.mutationGeneration,
    );
  }

  bool replace(ChatTurnOwner owner, ToolResultCompletionEvidence evidence) {
    if (!_evidenceByOwner.containsKey(owner)) return false;
    _evidenceByOwner[owner] = evidence;
    return true;
  }

  ToolResultCompletionEvidence? update(
    ChatTurnOwner owner,
    ToolResultCompletionEvidence Function(ToolResultCompletionEvidence evidence)
    transform,
  ) {
    final evidence = _evidenceByOwner[owner];
    if (evidence == null) return null;
    final updated = transform(evidence);
    _evidenceByOwner[owner] = updated;
    return updated;
  }

  bool dispose(ChatTurnOwner owner) {
    final removed = _evidenceByOwner.remove(owner) != null;
    final disposedThrough =
        _disposedGenerationWatermarks[owner.conversationId] ?? 0;
    if (owner.interactionGeneration > disposedThrough) {
      _disposedGenerationWatermarks[owner.conversationId] =
          owner.interactionGeneration;
    }
    return removed;
  }

  void clear() {
    for (final owner in _evidenceByOwner.keys.toList(growable: false)) {
      dispose(owner);
    }
  }
}

/// Reconciles and records one owner's goal state before terminal disposal.
///
/// Consume claim and shadow values before awaiting the goal write.
final class TurnGoalCompletionFinalizer {
  TurnGoalCompletionFinalizer({
    required GoalTurnRecorder recordGoalTurn,
    required GoalCompletionShadowRecorder recordGoalCompletionShadow,
  }) : _recordGoalTurn = recordGoalTurn,
       _recordGoalCompletionShadow = recordGoalCompletionShadow;

  final GoalTurnRecorder _recordGoalTurn;
  final GoalCompletionShadowRecorder _recordGoalCompletionShadow;

  Future<ToolResultCompletionEvidence?> finalize({
    required ChatTurnOwner owner,
    required TurnGoalCompletionEvidenceRegistry evidenceRegistry,
    required TurnFinalizationStateRegistry finalizationState,
    required List<ToolResultInfo> completedToolResults,
    required List<ToolResultInfo> contentToolResults,
    required Conversation? conversation,
    required String assistantResponse,
    required int tokenUsageDelta,
    required LlmSessionLogContext context,
  }) async {
    if (!evidenceRegistry.contains(owner) ||
        !finalizationState.contains(owner)) {
      return null;
    }
    final evidence = evidenceRegistry.reconcileForFinalization(
      owner,
      completedToolResults: completedToolResults,
      contentToolResults: contentToolResults,
      mutationGeneration: conversation?.mutationGeneration,
      verificationGeneration: conversation?.verificationGeneration,
    );
    final toolCompletionClaimed = finalizationState.takeGoalClaim(owner);
    final toolCompletionOutcome = finalizationState.takeGoalOutcome(owner);
    final goalWasActive = conversation?.goal?.isActive == true;
    final lexicalCompleted = await _recordGoalTurn(
      assistantResponse: assistantResponse,
      tokenUsageDelta: tokenUsageDelta,
      completionEvidence: evidence,
      toolCompletionClaimed: toolCompletionClaimed,
      conversationId: owner.conversationId,
    );
    if (goalWasActive) {
      await _recordGoalCompletionShadow(
        lexicalCompleted: lexicalCompleted,
        owner: owner,
        context: context,
        toolCompletionOutcome: toolCompletionOutcome,
      );
    }
    return evidence;
  }
}
