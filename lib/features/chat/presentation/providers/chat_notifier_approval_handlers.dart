// Same-library extension on [ChatNotifier] for high-risk tool approval: the
// per-turn approval result cache, the shared approval gate, LLM auto-review,
// and the approval audit trail. Pure relocation from chat_notifier.dart (F5),
// no behavior change.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

extension ChatNotifierApprovalHandlers on ChatNotifier {
  McpToolResult? _lookupToolApprovalResult(
    String toolName,
    Map<String, dynamic> arguments,
  ) {
    final cached = _toolApprovalCache.lookup(toolName, arguments);
    if (cached != null) {
      appLog(
        '[Tool] Reusing cached approval result for $toolName: ${jsonEncode(arguments)}',
      );
    }
    return cached;
  }

  McpToolResult _rememberToolApprovalResult(
    String toolName,
    Map<String, dynamic> arguments,
    McpToolResult result,
  ) {
    return _toolApprovalCache.remember(toolName, arguments, result);
  }

  /// Shared 3-mode approval gate for every high-risk tool (coding writes,
  /// browser actions, device/remote connections). Collapses [mode] into a
  /// single [ToolApprovalGateDecision] the caller switches on; the caller still
  /// owns execution, caching, and result formatting.
  ///
  /// - full access (when [fullAccessEligible]) runs directly;
  /// - auto-review consults the LLM ([reviewDomain] selects the prompt) and
  ///   allows / denies, or falls back to manual approval if the reviewer is
  ///   unavailable;
  /// - default always requires manual approval.
  Future<ToolApprovalGateDecision> _resolveToolApprovalGate({
    required ToolCallInfo toolCall,
    required String actionKind,
    required ToolApprovalMode mode,
    required ToolApprovalAutoReviewDomain reviewDomain,
    required bool fullAccessEligible,
    required Future<ToolApprovalAutoReviewRequest> Function()
    buildReviewRequest,
  }) async {
    if (mode == ToolApprovalMode.fullAccess) {
      if (fullAccessEligible) {
        await _recordApprovalAudit(
          toolCall: toolCall,
          actionKind: actionKind,
          domain: reviewDomain,
          mode: mode,
          outcome: 'allowed',
          decisionSource: 'full_access',
        );
        return ToolApprovalGateDecision.fullAccess;
      }
      // Full access requested but the tool is not eligible (e.g. ssh_connect
      // without a stored password): record why it still prompts, then fall back.
      await _recordApprovalAudit(
        toolCall: toolCall,
        actionKind: actionKind,
        domain: reviewDomain,
        mode: mode,
        outcome: 'manual_fallback',
        decisionSource: 'full_access_ineligible',
      );
      return ToolApprovalGateDecision.needsManualApproval;
    }
    if (mode == ToolApprovalMode.autoReview) {
      final decision = await _runApprovalAutoReview(
        await buildReviewRequest(),
        domain: reviewDomain,
      );
      if (decision == null) {
        await _recordApprovalAudit(
          toolCall: toolCall,
          actionKind: actionKind,
          domain: reviewDomain,
          mode: mode,
          outcome: 'review_unavailable',
          decisionSource: 'auto_review',
        );
        return ToolApprovalGateDecision.needsManualApproval;
      }
      await _recordApprovalAudit(
        toolCall: toolCall,
        actionKind: actionKind,
        domain: reviewDomain,
        mode: mode,
        outcome: decision.isAllowed ? 'allowed' : 'denied',
        decisionSource: 'auto_review',
        rationale: decision.rationale,
        riskLevel: decision.riskLevel,
      );
      return decision.isAllowed
          ? ToolApprovalGateDecision.autoReviewAllowed
          : ToolApprovalGateDecision.denied(decision.rationale);
    }
    // Default mode is a user-driven manual decision; not recorded here.
    return ToolApprovalGateDecision.needsManualApproval;
  }

  /// Appends one automated approval decision to the local audit trail. Best
  /// effort: failures never block tool execution.
  Future<void> _recordApprovalAudit({
    required ToolCallInfo toolCall,
    required String actionKind,
    required ToolApprovalAutoReviewDomain domain,
    required ToolApprovalMode mode,
    required String outcome,
    required String decisionSource,
    String? rationale,
    String? riskLevel,
  }) {
    final context = LlmSessionLogContext.current;
    return ref
        .read(toolApprovalAuditLogProvider)
        .record(
          tool: toolCall.name,
          actionKind: actionKind,
          domain: domain.name,
          mode: mode.name,
          outcome: outcome,
          decisionSource: decisionSource,
          rationale: rationale,
          riskLevel: riskLevel,
          arguments: toolCall.arguments,
          workspaceMode: context?.workspaceMode.name,
          sessionId: context?.sessionId,
          conversationId: context?.conversationId,
        );
  }

  /// Assembles an auto-review request, attaching the recent conversation tail.
  /// Shared by every gated tool's `buildReviewRequest` callback.
  ToolApprovalAutoReviewRequest _buildAutoReviewRequest({
    required ToolCallInfo toolCall,
    required String actionKind,
    required Map<String, dynamic> arguments,
    String? path,
    String? workingDirectory,
    String? reason,
    String? warningTitle,
    String? warningMessage,
    String? preview,
  }) {
    return ToolApprovalAutoReviewRequest(
      actionKind: actionKind,
      toolName: toolCall.name,
      arguments: arguments,
      path: path,
      workingDirectory: workingDirectory,
      reason: reason,
      warningTitle: warningTitle,
      warningMessage: warningMessage,
      preview: preview,
      conversationTail: ToolApprovalAutoReviewService.buildConversationTail(
        state.messages,
      ),
      hasUntrustedInfluence: _conversationTaintState.hasUntrustedInfluence,
    );
  }

  /// Sends an approval request to the configured LLM endpoint and parses its
  /// verdict. Shared by coding-write and browser-action auto-review; [domain]
  /// selects the system prompt. Returns null when auto-review is unavailable
  /// (network/parse failure), letting callers fall back to manual approval.
  Future<ToolApprovalAutoReviewDecision?> _runApprovalAutoReview(
    ToolApprovalAutoReviewRequest request, {
    ToolApprovalAutoReviewDomain domain = ToolApprovalAutoReviewDomain.coding,
  }) async {
    try {
      final response = await _runSecondaryCompletion(
        endpointId: _settings.approvalAutoReviewEndpointId,
        model: _settings.effectiveApprovalAutoReviewModel,
        call: (dataSource, model) => dataSource.createChatCompletion(
          messages: ToolApprovalAutoReviewService.buildMessages(
            request,
            domain: domain,
          ),
          model: model,
          temperature: 0,
          maxTokens: 512,
        ),
      );
      final decision = ToolApprovalAutoReviewService.parseDecision(
        response.content,
      );
      if (decision == null) {
        appLog('[AutoReview] Reviewer returned malformed output.');
        return null;
      }
      appLog(
        '[AutoReview] ${decision.outcome.name} ${request.toolName}: '
        '${decision.rationale}',
      );
      return decision;
    } catch (error) {
      appLog('[AutoReview] Reviewer failed: $error');
      return null;
    }
  }

  McpToolResult _autoReviewDeniedResult({
    required String toolName,
    required String rationale,
  }) {
    return McpToolResult(
      toolName: toolName,
      result: 'Auto-review denied this action. Rationale: $rationale',
      isSuccess: false,
      errorMessage: 'Auto-review denied: $rationale',
    );
  }
}
