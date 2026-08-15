import 'dart:convert';

import '../entities/chat_turn_owner.dart';
import '../entities/conversation.dart';
import '../entities/mcp_tool_entity.dart';
import '../entities/message.dart';
import '../entities/tool_call_info.dart';
import 'ask_user_question_turn_cache.dart';
import 'blocked_production_release_retry_policy.dart';
import 'production_release_approval_policy.dart';
import 'tool_call_execution_policy.dart';

// ChatNotifier decomposition collaborator: production-release-approval-coordinator

final class ProductionReleaseApprovalEvidenceSnapshot {
  const ProductionReleaseApprovalEvidenceSnapshot({
    required this.conversationId,
    required this.approved,
  });

  final String? conversationId;
  final bool approved;
}

final class ProductionReleaseApprovalCoordinator {
  ProductionReleaseApprovalCoordinator({
    required String? Function(int generation) activeConversationId,
    required ChatTurnOwner? Function(int generation) ownerForGeneration,
    required AskUserQuestionTurnCache questionResults,
  }) : _activeConversationId = activeConversationId,
       _ownerForGeneration = ownerForGeneration,
       _questionResults = questionResults;

  static const _policy = ProductionReleaseApprovalPolicy();
  static const _executionPolicy = ToolCallExecutionPolicy();

  final _proofs = <int, _ReleaseApprovalProofSnapshot>{};
  final _pendingReleases = <String, PendingBlockedRelease>{};
  final String? Function(int generation) _activeConversationId;
  final ChatTurnOwner? Function(int generation) _ownerForGeneration;
  final AskUserQuestionTurnCache _questionResults;

  void captureProof({
    required int generation,
    required Conversation? conversation,
    required String submittedContent,
  }) {
    if (conversation == null) return;
    final submitted = submittedContent.trim();
    Message? precedingMessage;
    for (final message in conversation.messages.reversed) {
      if (message.role != MessageRole.system &&
          message.content.trim().isNotEmpty) {
        precedingMessage = message;
        break;
      }
    }
    _proofs[generation] = _ReleaseApprovalProofSnapshot(
      generation: generation,
      conversationId: conversation.id,
      explicit: _policy.looksLikeExplicitProductionReleaseApproval(submitted),
      promptReply:
          _policy.looksLikeAffirmativeReleaseApprovalAnswer(submitted) &&
          precedingMessage?.role == MessageRole.assistant &&
          _policy.looksLikeProductionReleaseApprovalPrompt(
            precedingMessage!.content,
          ),
    );
  }

  ProductionReleaseApprovalEvidenceSnapshot evidenceFor(int generation) {
    final activeConversationId = _activeConversationId(generation);
    final owner = _ownerForGeneration(generation);
    final proof = _proofs[generation];
    final directlyApproved =
        proof?.generation == generation &&
        proof?.conversationId == activeConversationId &&
        (proof?.explicit == true || proof?.promptReply == true);
    final questionApproved =
        owner != null &&
        _questionResults.anyResult(owner, _policy.answerApproves);
    return ProductionReleaseApprovalEvidenceSnapshot(
      conversationId: activeConversationId,
      approved:
          activeConversationId != null &&
          (directlyApproved || questionApproved),
    );
  }

  McpToolResult? buildGuardResult(
    ToolCallInfo toolCall, {
    required String? currentAssistantContent,
    required ProductionReleaseApprovalEvidenceSnapshot evidence,
  }) {
    if (!_policy.isProductionReleaseCommandToolCall(toolCall)) return null;
    final conversationId = evidence.conversationId;
    if (evidence.approved) {
      if (conversationId != null) _pendingReleases.remove(conversationId);
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
    final assistantIntent = currentAssistantContent?.trim() ?? '';
    return McpToolResult(
      toolName: toolCall.name,
      result: jsonEncode({
        'ok': false,
        'code': 'production_release_explicit_approval_required',
        'error':
            'A production release command was blocked because the latest user '
            'message or ask_user_question answer did not explicitly approve '
            'production release execution.',
        'command': command,
        if (assistantIntent.isNotEmpty)
          'assistant_intent': _clipForDiagnostic(assistantIntent),
        'required_action': productionReleaseApprovalRequiredAction,
      }),
      isSuccess: true,
    );
  }

  PendingBlockedRelease? pendingRelease(String conversationId) =>
      _pendingReleases[conversationId];

  void removePendingRelease(String conversationId) =>
      _pendingReleases.remove(conversationId);

  void clearGeneration(int generation) => _proofs.remove(generation);

  void clearAll() {
    _proofs.clear();
    _pendingReleases.clear();
  }

  String _clipForDiagnostic(String value, {int maxLength = 240}) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= maxLength) return normalized;
    return '${normalized.substring(0, maxLength)}...';
  }
}

final class _ReleaseApprovalProofSnapshot {
  const _ReleaseApprovalProofSnapshot({
    required this.generation,
    required this.conversationId,
    required this.explicit,
    required this.promptReply,
  });

  final int generation;
  final String conversationId;
  final bool explicit;
  final bool promptReply;
}
