// Same-library extension on [ChatNotifier] for high-risk tool approval: the
// per-turn approval result cache, the shared approval gate, LLM auto-review,
// and the approval audit trail. Pure relocation from chat_notifier.dart (F5),
// no behavior change.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

extension ChatNotifierApprovalHandlers on ChatNotifier {
  McpToolResult? _lookupToolApprovalResult(
    String toolName,
    Map<String, dynamic> arguments, {
    String? stateFingerprint,
  }) {
    final cached = _toolApprovalCache.lookup(
      toolName,
      arguments,
      stateFingerprint: stateFingerprint,
    );
    if (cached?.denialResult != null) {
      appLog(
        '[Tool] Reusing cached approval denial for $toolName: ${jsonEncode(arguments)}',
      );
    }
    return cached?.denialResult;
  }

  McpToolResult _rememberToolApprovalResult(
    String toolName,
    Map<String, dynamic> arguments,
    McpToolResult result, {
    String? stateFingerprint,
  }) {
    _toolApprovalCache.rememberApproval(
      toolName,
      arguments,
      stateFingerprint: stateFingerprint,
    );
    return result;
  }

  McpToolResult _rememberToolApprovalDenial(
    String toolName,
    Map<String, dynamic> arguments,
    McpToolResult result, {
    String? stateFingerprint,
  }) {
    return _toolApprovalCache.rememberDenial(
      toolName,
      arguments,
      result,
      stateFingerprint: stateFingerprint,
    );
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
    Map<String, dynamic>? approvalCacheArguments,
    String? approvalCacheStateFingerprint,
    required Future<ToolApprovalAutoReviewRequest> Function()
    buildReviewRequest,
  }) async {
    final cachedApproval = approvalCacheArguments == null
        ? null
        : _toolApprovalCache.lookup(
            toolCall.name,
            approvalCacheArguments,
            stateFingerprint: approvalCacheStateFingerprint,
          );
    if (cachedApproval?.isApproved == true) {
      await _recordApprovalAudit(
        toolCall: ToolCallInfo(
          id: toolCall.id,
          name: toolCall.name,
          arguments: approvalCacheArguments!,
        ),
        actionKind: actionKind,
        domain: reviewDomain,
        mode: mode,
        outcome: 'allowed',
        decisionSource: 'cached_approval',
      );
      appLog(
        '[Tool] Reusing cached approval grant for ${toolCall.name}: '
        '${jsonEncode(approvalCacheArguments)}',
      );
      return ToolApprovalGateDecision.cachedApproval;
    }
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
      if (decision.isAllowed) {
        await _recordApprovalAudit(
          toolCall: toolCall,
          actionKind: actionKind,
          domain: reviewDomain,
          mode: mode,
          outcome: 'allowed',
          decisionSource: 'auto_review',
          rationale: decision.rationale,
          riskLevel: decision.riskLevel,
        );
        return ToolApprovalGateDecision.autoReviewAllowed;
      }
      // Denied. In an escalatable domain (see _domainEscalatesDeniedActionToManual)
      // a user-driven denial escalates to manual approval (the human decides)
      // instead of dead-ending the turn; a denial with untrusted content in
      // context stays a hard deny so untrusted input can never reach a human
      // rubber-stamp. See [ToolApprovalGateDecision.fromAutoReviewDenial].
      final gateDecision = _domainEscalatesDeniedActionToManual(reviewDomain)
          ? ToolApprovalGateDecision.fromAutoReviewDenial(
              decision.rationale,
              hasUntrustedInfluence:
                  _conversationTaintState.hasUntrustedInfluence,
            )
          : ToolApprovalGateDecision.denied(decision.rationale);
      await _recordApprovalAudit(
        toolCall: toolCall,
        actionKind: actionKind,
        domain: reviewDomain,
        mode: mode,
        outcome: gateDecision.escalatedFromAutoReviewDenial
            ? 'denied_escalated_manual'
            : 'denied',
        decisionSource: 'auto_review',
        rationale: decision.rationale,
        riskLevel: decision.riskLevel,
      );
      return gateDecision;
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
          untrustedInfluence: _conversationTaintState.hasUntrustedInfluence,
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

  /// Whether an auto-review denial in [domain] escalates to manual user
  /// approval (the user decides) instead of a hard deny.
  ///
  /// Scoped to `coding`: the user directly drives local shell / file / git
  /// actions, those have a well-established manual-approval prompt, and a denied
  /// build/run command dead-ending the turn is the reported pain point. Other
  /// domains stay hard-deny for now: `browser` denials can be phishing-shaped
  /// (e.g. a credential-submit click) where routing to a user who may rubber-
  /// stamp it is riskier, `connection` is not the reported need, and
  /// `participant` (sub-agent) denials must never interrupt the user.
  bool _domainEscalatesDeniedActionToManual(
    ToolApprovalAutoReviewDomain domain,
  ) {
    return domain == ToolApprovalAutoReviewDomain.coding;
  }

  /// Manual-prompt warning title for a gate decision: a dedicated heading when
  /// the prompt only exists because auto-review escalated a denial, otherwise
  /// the handler's own [fallback] risk-warning title.
  String? _escalatedApprovalWarningTitle(
    ToolApprovalGateDecision gate,
    String? fallback,
  ) {
    return gate.escalatedFromAutoReviewDenial
        ? 'Auto-review flagged this action'
        : fallback;
  }

  /// Manual-prompt warning body for a gate decision: prepends the reviewer's
  /// rationale when the prompt is an escalated auto-review denial, so the user
  /// sees *why* approval is being requested before deciding.
  String? _escalatedApprovalWarningMessage(
    ToolApprovalGateDecision gate,
    String? fallback,
  ) {
    final rationale = gate.autoReviewEscalationRationale;
    if (rationale == null) {
      return fallback;
    }
    return fallback == null || fallback.isEmpty
        ? rationale
        : '$rationale\n\n$fallback';
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
