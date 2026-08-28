import 'package:flutter/foundation.dart';

import '../../../../core/utils/logger.dart';

import '../entities/chat_turn_owner.dart';
import '../entities/conversation.dart';
import '../entities/mcp_tool_entity.dart';
import '../entities/tool_call_info.dart';
import 'ask_user_question_turn_cache.dart';
import 'blocked_production_release_retry_policy.dart';
import 'production_release_approval_evidence_snapshot.dart';
import 'production_release_approval_policy.dart';
import 'production_release_approval_token_registry.dart';
import 'production_release_blocked_result.dart';
import 'production_release_prose_shadow.dart';
import 'tool_call_execution_policy.dart';

export 'production_release_approval_evidence_snapshot.dart';

// ChatNotifier decomposition collaborator: production-release-approval-coordinator

final class ProductionReleaseApprovalCoordinator {
  ProductionReleaseApprovalCoordinator({
    required String? Function(int generation) activeConversationId,
    required ChatTurnOwner? Function(int generation) ownerForGeneration,
    required AskUserQuestionTurnCache questionResults,
    String Function()? approvalTokenFactory,
  }) : _activeConversationId = activeConversationId,
       _ownerForGeneration = ownerForGeneration,
       _questionResults = questionResults,
       _approvalTokens = ProductionReleaseApprovalTokenRegistry(
         tokenFactory: approvalTokenFactory ?? debugApprovalTokenFactory,
       );

  /// Test seam for the issued approval token.
  ///
  /// The production factory is deliberately unpredictable, which leaves a test
  /// no way to know the token an end-to-end flow will use.
  @visibleForTesting
  static String Function()? debugApprovalTokenFactory;

  static const _policy = ProductionReleaseApprovalPolicy();
  static const _executionPolicy = ToolCallExecutionPolicy();

  final _pendingReleases = <String, PendingBlockedRelease>{};
  final _proseShadow = ProductionReleaseProseShadow();
  final ProductionReleaseApprovalTokenRegistry _approvalTokens;
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
        : _approvalTokens.tokenFor(activeConversationId);
    final tokenApproved =
        owner != null &&
        token != null &&
        _questionResults.anyEntry(
          owner,
          (offeredOptionLabels, result) => _policy.answerApprovesToken(
            offeredOptionLabels: offeredOptionLabels,
            answerResult: result,
            token: token,
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
      _approvalTokens.tokenFor(conversationId);

  McpToolResult? buildGuardResult(
    ToolCallInfo toolCall, {
    required String? currentAssistantContent,
    required ProductionReleaseApprovalEvidenceSnapshot evidence,
  }) {
    if (!_policy.isProductionReleaseCommandToolCall(toolCall)) return null;
    final conversationId = evidence.conversationId;
    if (evidence.approved) {
      // The token authorized this release and nothing else.
      if (conversationId != null) removePendingRelease(conversationId);
      return null;
    }

    final command =
        _executionPolicy.toolCommandArgument(toolCall.arguments) ?? '';
    if (conversationId != null && command.trim().isNotEmpty) {
      _pendingReleases[conversationId] = PendingBlockedRelease(
        toolName: toolCall.name.trim(),
        command: command.trim(),
      );
    }
    return buildProductionReleaseBlockedResult(
      toolName: toolCall.name,
      command: command,
      assistantIntent: currentAssistantContent ?? '',
      approvalToken: _approvalTokens.issueFor(conversationId),
    );
  }

  PendingBlockedRelease? pendingRelease(String conversationId) =>
      _pendingReleases[conversationId];

  void removePendingRelease(String conversationId) {
    _pendingReleases.remove(conversationId);
    _approvalTokens.release(conversationId);
  }

  void clearGeneration(int generation) =>
      _proseShadow.clearGeneration(generation);

  void clearAll() {
    _proseShadow.clear();
    _pendingReleases.clear();
    _approvalTokens.clear();
  }
}
