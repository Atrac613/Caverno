import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

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
    this.proseWouldApprove = false,
  });

  final String? conversationId;

  /// Whether a production release may run. Decided by the issued approval
  /// token alone.
  final bool approved;

  /// What the retired wording predicates would have decided, recorded so the
  /// two can be compared before those predicates are deleted.
  ///
  /// Never grants anything. A `true` here beside a `false` [approved] is the
  /// interesting case: prose that reads as approval without the user having
  /// selected the token-bearing option.
  final bool proseWouldApprove;

  bool get shadowDiverges => proseWouldApprove != approved;
}

final class ProductionReleaseApprovalCoordinator {
  ProductionReleaseApprovalCoordinator({
    required String? Function(int generation) activeConversationId,
    required ChatTurnOwner? Function(int generation) ownerForGeneration,
    required AskUserQuestionTurnCache questionResults,
    String Function()? approvalTokenFactory,
  }) : _activeConversationId = activeConversationId,
       _ownerForGeneration = ownerForGeneration,
       _questionResults = questionResults,
       _approvalTokenFactory =
           approvalTokenFactory ??
           debugApprovalTokenFactory ??
           _randomApprovalToken;

  /// Test seam for the issued approval token.
  ///
  /// The production factory is deliberately unpredictable so the model cannot
  /// pre-authorize a release it has not been blocked on yet, which leaves a
  /// test no way to know the token an end-to-end flow will use.
  @visibleForTesting
  static String Function()? debugApprovalTokenFactory;

  static const _policy = ProductionReleaseApprovalPolicy();
  static const _executionPolicy = ToolCallExecutionPolicy();

  final _proofs = <int, _ReleaseApprovalProofSnapshot>{};
  final _pendingReleases = <String, PendingBlockedRelease>{};
  final String? Function(int generation) _activeConversationId;
  final ChatTurnOwner? Function(int generation) _ownerForGeneration;
  final AskUserQuestionTurnCache _questionResults;
  final String Function() _approvalTokenFactory;

  /// Token issued for the release currently blocked in each conversation.
  ///
  /// Kept per conversation rather than per generation because approval arrives
  /// in a later turn than the block: the model is told to ask, the user
  /// answers, and only then is the release retried. Cleared with the pending
  /// release, so a token can never authorize a second, different release.
  final _approvalTokens = <String, String>{};

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
    final token = activeConversationId == null
        ? null
        : _approvalTokens[activeConversationId];
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

    // Shadow only. The wording predicates read denials as approvals in several
    // languages, so they are recorded and compared, never obeyed.
    final proof = _proofs[generation];
    final proseDirect =
        proof?.generation == generation &&
        proof?.conversationId == activeConversationId &&
        (proof?.explicit == true || proof?.promptReply == true);
    final proseQuestion =
        owner != null &&
        _questionResults.anyResult(owner, _policy.answerApproves);

    return ProductionReleaseApprovalEvidenceSnapshot(
      conversationId: activeConversationId,
      approved: activeConversationId != null && tokenApproved,
      proseWouldApprove:
          activeConversationId != null && (proseDirect || proseQuestion),
    );
  }

  /// The token issued for [conversationId]'s blocked release, if any.
  String? approvalToken(String conversationId) =>
      _approvalTokens[conversationId];

  static String _randomApprovalToken() {
    final random = Random.secure();
    final buffer = StringBuffer('rel-');
    for (var i = 0; i < productionReleaseApprovalTokenLength; i++) {
      buffer.write(random.nextInt(16).toRadixString(16));
    }
    return buffer.toString();
  }

  McpToolResult? buildGuardResult(
    ToolCallInfo toolCall, {
    required String? currentAssistantContent,
    required ProductionReleaseApprovalEvidenceSnapshot evidence,
  }) {
    if (!_policy.isProductionReleaseCommandToolCall(toolCall)) return null;
    final conversationId = evidence.conversationId;
    if (evidence.approved) {
      if (conversationId != null) {
        _pendingReleases.remove(conversationId);
        // The token authorized this release and nothing else.
        _approvalTokens.remove(conversationId);
      }
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
    // One token per blocked release, reused while that release stays blocked
    // so a re-ask does not invalidate an answer the user already gave.
    final approvalToken = conversationId == null
        ? _approvalTokenFactory()
        : _approvalTokens.putIfAbsent(
            conversationId,
            _approvalTokenFactory,
          );
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
        'required_action': productionReleaseApprovalRequiredActionFor(
          approvalToken,
        ),
      }),
      isSuccess: true,
    );
  }

  PendingBlockedRelease? pendingRelease(String conversationId) =>
      _pendingReleases[conversationId];

  void removePendingRelease(String conversationId) {
    _pendingReleases.remove(conversationId);
    _approvalTokens.remove(conversationId);
  }

  void clearGeneration(int generation) => _proofs.remove(generation);

  void clearAll() {
    _proofs.clear();
    _pendingReleases.clear();
    _approvalTokens.clear();
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
