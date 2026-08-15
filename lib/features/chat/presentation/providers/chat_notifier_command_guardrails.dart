// Same-library extension; see chat_notifier_git_handlers.dart for rationale.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

typedef _ReleaseProof = ({int gen, String thread, bool explicit, bool reply});
typedef _ReleaseApprovalEvidence = ({String? conversationId, bool approved});
const _productionReleaseApprovalPolicy = ProductionReleaseApprovalPolicy();

extension ChatNotifierCommandGuardrails on ChatNotifier {
  McpToolResult? _buildProductionReleaseApprovalGuardResult(
    ToolCallInfo toolCall, {
    required String? currentAssistantContent,
    required _ReleaseApprovalEvidence approvalEvidence,
  }) {
    if (!_productionReleaseApprovalPolicy.isProductionReleaseCommandToolCall(
      toolCall,
    )) {
      return null;
    }
    final conversationId = approvalEvidence.conversationId;
    if (approvalEvidence.approved) {
      // The command is about to run, so the conversation no longer owes a
      // retry for it.
      if (conversationId != null) {
        _pendingBlockedReleases.remove(conversationId);
      }
      return null;
    }

    final command =
        _toolCallExecutionPolicy.toolCommandArgument(toolCall.arguments) ?? '';
    if (conversationId != null && command.trim().isNotEmpty) {
      _pendingBlockedReleases[conversationId] = PendingBlockedRelease(
        toolName: toolCall.name.trim(),
        command: command.trim(),
      );
    }
    final payload = jsonEncode({
      'ok': false,
      'code': 'production_release_explicit_approval_required',
      'error':
          'A production release command was blocked because the latest user '
          'message or ask_user_question answer did not explicitly approve '
          'production release execution.',
      'command': command,
      if ((currentAssistantContent ?? '').trim().isNotEmpty)
        'assistant_intent': _claims.clipForDiagnostic(
          currentAssistantContent!.trim(),
        ),
      'required_action': productionReleaseApprovalRequiredAction,
    });
    return McpToolResult(
      toolName: toolCall.name,
      result: payload,
      isSuccess: true,
    );
  }

  ConversationWorkflowTask? _savedTaskForGeneration(
    int interactionGeneration,
  ) => _turnOwnerSnapshotForGeneration(interactionGeneration)?.savedTask;

  void _captureProof(int gen, QueuedChatMessage message, Conversation? owner) {
    final conversationId = message.conversationId;
    final conversation = conversationId == null
        ? owner
        : _conversationForId(conversationId);
    if (conversation == null) return;
    final submittedContent = message.content.trim();
    final previous = conversation.messages
        .where(
          (m) => m.role != MessageRole.system && m.content.trim().isNotEmpty,
        )
        .lastOrNull;
    _releaseApprovalSnapshots[gen] = (
      gen: gen,
      thread: conversation.id,
      explicit: _productionReleaseApprovalPolicy
          .looksLikeExplicitProductionReleaseApproval(submittedContent),
      reply:
          _productionReleaseApprovalPolicy
              .looksLikeAffirmativeReleaseApprovalAnswer(submittedContent) &&
          previous?.role == MessageRole.assistant &&
          _productionReleaseApprovalPolicy
              .looksLikeProductionReleaseApprovalPrompt(previous!.content),
    );
  }

  _ReleaseApprovalEvidence _releaseEvidenceFor(int generation) {
    final thread = _activeResponseConversationIdForGeneration(generation);
    final direct = _releaseApprovalSnapshots[generation];
    final directlyApproved =
        direct?.gen == generation &&
        direct?.thread == thread &&
        (direct?.explicit == true || direct?.reply == true);
    final cache = _askUserQuestionTurnCache;
    final owner = _turnOwnerForGeneration(generation);
    final questionApproved =
        owner != null &&
        cache.anyResult(owner, _productionReleaseApprovalPolicy.answerApproves);
    return (
      conversationId: thread,
      approved: thread != null && (directlyApproved || questionApproved),
    );
  }
}
