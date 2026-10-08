import 'package:flutter/foundation.dart';

import '../../../../../core/utils/logger.dart';

import '../../entities/chat_turn_owner.dart';
import '../../entities/conversation.dart';
import '../../entities/mcp_tool_entity.dart';
import '../../entities/tool_call_info.dart';
import '../ask_user_question_turn_cache.dart';
import 'blocked_production_release_retry_contract.dart';
import 'production_release_approval_evidence_snapshot.dart';
import 'production_release_approval_gate.dart';
import 'production_release_approval_policy.dart';
import 'production_release_prose_shadow.dart';

export 'production_release_approval_conflict_result.dart';
export 'production_release_approval_evidence_snapshot.dart';
export 'production_release_approval_presentation.dart';
export 'production_release_execution_identity.dart';

// ChatNotifier decomposition collaborator: production-release-approval-coordinator

final class ProductionReleaseApprovalCoordinator {
  ProductionReleaseApprovalCoordinator({
    required String? Function(int generation) activeConversationId,
    required ChatTurnOwner? Function(int generation) ownerForGeneration,
    required AskUserQuestionTurnCache questionResults,
    String Function()? approvalTokenFactory,
    Map<String, dynamic> Function(ToolCallInfo toolCall)?
    resolveExecutionArguments,
  }) : _activeConversationId = activeConversationId,
       _ownerForGeneration = ownerForGeneration,
       _questionResults = questionResults,
       _gate = ProductionReleaseApprovalGate(
         approvalTokenFactory:
             approvalTokenFactory ?? debugApprovalTokenFactory,
         resolveExecutionArguments: resolveExecutionArguments,
       );

  /// Test seam for the issued approval token.
  ///
  /// The production factory is deliberately unpredictable, which leaves a test
  /// no way to know the token an end-to-end flow will use.
  @visibleForTesting
  static String Function()? debugApprovalTokenFactory;

  static const _policy = ProductionReleaseApprovalPolicy();
  final _proseShadow = ProductionReleaseProseShadow();
  final ProductionReleaseApprovalGate _gate;
  final String? Function(int generation) _activeConversationId;
  final ChatTurnOwner? Function(int generation) _ownerForGeneration;
  final AskUserQuestionTurnCache _questionResults;

  void captureProof({
    required int generation,
    required Conversation? conversation,
    required String submittedContent,
  }) {
    if (conversation == null) return;
    _proseShadow.capture(
      generation: generation,
      conversation: conversation,
      submittedContent: submittedContent,
    );
  }

  ProductionReleaseApprovalEvidenceSnapshot evidenceFor(int generation) {
    final activeConversationId = _activeConversationId(generation);
    final owner = _ownerForGeneration(generation);
    final token = activeConversationId == null
        ? null
        : _gate.approvalToken(activeConversationId);
    final binding = _gate.approvalBinding(activeConversationId);
    final tokenApproved =
        owner != null &&
        token != null &&
        _questionResults.anyEntry(
          owner,
          (offeredOptionLabels, result) => _policy.answerApprovesToken(
            offeredOptionLabels: offeredOptionLabels,
            answerResult: result,
            token: token,
            expectedOptionLabel: binding.optionLabel,
            expectedQuestion: binding.question,
          ),
        );

    final snapshot = ProductionReleaseApprovalEvidenceSnapshot(
      conversationId: activeConversationId,
      approved: activeConversationId != null && tokenApproved,
      // Shadow only. The wording predicates read denials as approvals in
      // several languages, so they are recorded and compared, never obeyed.
      proseWouldApprove: _proseShadow.wouldApprove(
        generation: generation,
        conversationId: activeConversationId,
        owner: owner,
        questionResults: _questionResults,
      ),
    );
    final divergence = snapshot.shadowDivergenceLogLine;
    if (divergence != null) appLog(divergence);
    return snapshot;
  }

  /// The token issued for [conversationId]'s blocked release, if any.
  String? approvalToken(String conversationId) =>
      _gate.approvalToken(conversationId);

  McpToolResult? buildGuardResult(
    ToolCallInfo toolCall, {
    required String? currentAssistantContent,
    required ProductionReleaseApprovalEvidenceSnapshot evidence,
    List<ToolResultInfo> executedToolResults = const [],
  }) => _gate.buildGuardResult(
    toolCall,
    currentAssistantContent: currentAssistantContent,
    evidence: evidence,
    isProductionRelease: _policy.isProductionReleaseCommandToolCall(toolCall),
    executedToolResults: executedToolResults,
  );

  PendingBlockedRelease? pendingRelease(String conversationId) =>
      _gate.pendingRelease(conversationId);

  /// Replaces model-authored release wording with the exact harness-owned
  /// execution summary before the question reaches the user.
  ToolCallInfo bindPendingApprovalQuestion(
    String conversationId,
    ToolCallInfo toolCall,
  ) => _gate.bindPendingApprovalQuestion(conversationId, toolCall);

  void removePendingRelease(String conversationId) =>
      _gate.removePendingRelease(conversationId);

  void clearGeneration(int generation) =>
      _proseShadow.clearGeneration(generation);

  void clearAll() {
    _proseShadow.clear();
    _gate.clear();
  }
}
