// Same-library bridge for owner-scoped tool approvals, auto-review, and audit.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

final Expando<SecondaryCompletionRouter<ChatDataSource>>
_secondaryCompletionRouters =
    Expando<SecondaryCompletionRouter<ChatDataSource>>();

SecondaryCompletionRouteSnapshot _secondaryCompletionRoute(
  AppSettings settings,
  String endpointId,
  String model,
  ModelUsageRole usageRole,
) => SecondaryCompletionRouteSnapshot(
  provider: settings.llmProvider,
  primaryBaseUrl: settings.baseUrl,
  primaryApiKey: settings.apiKey,
  primaryModel: settings.model,
  enabledEndpoints: settings.enabledLlmEndpoints,
  selectedEndpointId: endpointId,
  selectedModel: model,
  fallbackModel: settings.model,
  usageRole: usageRole,
);

extension _SecondaryCompletionRouteSettings on AppSettings {
  SecondaryCompletionRouteSnapshot get _planningCompletionRoute =>
      _secondaryCompletionRoute(
        this,
        planningEndpointId,
        effectivePlanningModel,
        ModelUsageRole.planning,
      );

  SecondaryCompletionRouteSnapshot get _goalSuggestionCompletionRoute =>
      _secondaryCompletionRoute(
        this,
        goalSuggestionEndpointId,
        effectiveGoalSuggestionModel,
        ModelUsageRole.goalSuggestion,
      );

  SecondaryCompletionRouteSnapshot get _memoryExtractionCompletionRoute =>
      _secondaryCompletionRoute(
        this,
        memoryExtractionEndpointId,
        effectiveMemoryExtractionModel,
        ModelUsageRole.memoryExtraction,
      );

  SecondaryCompletionRouteSnapshot get _approvalAutoReviewCompletionRoute =>
      _secondaryCompletionRoute(
        this,
        approvalAutoReviewEndpointId,
        effectiveApprovalAutoReviewModel,
        ModelUsageRole.approvalAutoReview,
      );
}

void _recordPlanningRouteAttempt(SecondaryCompletionRouteMetadata metadata) {
  appLog(
    '[Planning] plan_draft model=${metadata.model} '
    'endpoint=${metadata.endpoint} fallback=${metadata.isFallback}',
  );
}

extension ChatNotifierApprovalHandlers on ChatNotifier {
  SecondaryCompletionRouter<ChatDataSource> get _secondaryCompletionRouter =>
      _secondaryCompletionRouters[this] ??=
          SecondaryCompletionRouter<ChatDataSource>(
            meshRunner: _meshRunner,
            logPort: const CallbackSecondaryCompletionLogPort(
              _recordPlanningRouteAttempt,
            ),
          );

  void _routeApproval(
    ChatState Function(ChatState) apply, {
    ChatTurnOwner? owner,
  }) {
    final turnThread = owner?.conversationId ?? TurnThread.currentId;
    state = ThreadScopedChatState.routeToThread(
      byThread: _threadStates,
      turnThread: turnThread,
      visibleThread: conversationId,
      current: state,
      apply: apply,
    );
    if (turnThread == null || turnThread == conversationId) return;
    final threadTitle = _conversationForId(turnThread)?.title.trim() ?? '';
    unawaited(
      ref
          .read(notificationServiceProvider)
          .showApprovalRequiredNotification(
            conversationId: turnThread,
            title: 'Caverno',
            body: threadTitle.isEmpty
                ? 'A thread is waiting for your approval.'
                : '$threadTitle is waiting for your approval.',
          ),
    );
  }

  @visibleForTesting
  ChatTurnOwner registerApprovalOwnerForTest(String conversationId) =>
      _activeResponseRegistry.registerOwnerForTest(conversationId);

  bool _isApprovalOwnerCurrent(ChatTurnOwner owner) =>
      ref.mounted && _activeResponseRegistry.isCurrentOwner(owner);

  McpToolResult? _expiredApproval(
    String toolName,
    OwnerToolApprovalCache approvalCache,
  ) => _isApprovalOwnerCurrent(approvalCache.owner)
      ? null
      : approvalTurnExpiredResult(toolName);

  Future<McpToolResult?> _rollbackExpiredApproval(
    String toolName,
    OwnerToolApprovalCache approvalCache, {
    required String target,
    Future<void> Function()? rollback,
  }) async {
    final expired = _expiredApproval(toolName, approvalCache);
    if (expired == null) return null;
    try {
      await rollback?.call();
    } catch (error) {
      appLog('[Tool] Failed to roll back expired approval for $target: $error');
    }
    return expired;
  }

  String _approvalSummary(String? reason, String fallback) =>
      reason?.trim().isNotEmpty == true ? reason!.trim() : fallback;

  Future<T> _registerPendingToolApproval<T>(
    PendingToolApproval<T> pending,
    ChatState Function(ChatState) apply,
    String capability,
    String summary,
    String? target, [
    bool rememberAllowed = false,
  ]) {
    return _pendingToolApprovals.registerCurrent(
      pending,
      ownerIsCurrent: _isApprovalOwnerCurrent(pending.owner),
      show: () {
        _routeApproval(apply, owner: pending.owner);
        _runtimeEvents.emitRuntimeApprovalRequired(
          generation: pending.owner.interactionGeneration,
          id: pending.id,
          capability: capability,
          summary: summary,
          target: target,
          rememberAllowed: rememberAllowed,
        );
      },
    );
  }

  T? _takeCurrentPendingToolApproval<T extends PendingToolApproval<dynamic>>(
    String id,
  ) => _pendingToolApprovals.takeCurrent<T>(
    id: id,
    ownerIsCurrent: _isApprovalOwnerCurrent,
    clear: _clearPendingToolApprovalProjection,
  );

  bool _completeApproval<T, P extends PendingToolApproval<T>>(
    String id,
    T Function(P pending) value,
  ) {
    final pending = _takeCurrentPendingToolApproval<P>(id);
    if (pending == null || pending.completer.isCompleted) return false;
    pending.completer.complete(value(pending));
    return true;
  }

  void _clearPendingToolApprovalProjection(
    PendingToolApproval<dynamic> pending,
  ) {
    _routeThreadState(
      pending.owner.conversationId,
      (current) =>
          ThreadScopedChatState.clearPendingToolApproval(current, pending),
    );
  }

  void _cancelPendingToolApprovalsForOwner(ChatTurnOwner owner) {
    _localCommandExecutionAuthority.clearOwner(owner);
    final pending = _pendingToolApprovals.cancelOwner(owner);
    for (final request in pending) {
      _clearPendingToolApprovalProjection(request);
    }
  }

  void _cancelAllPendingToolApprovals() {
    _localCommandExecutionAuthority.clearAll();
    _pendingToolApprovals.cancelAll();
  }

  /// Resolves cached, full-access, auto-review, or manual approval policy.
  /// Execution and result caching remain with the caller.
  Future<ToolApprovalGateDecision> _resolveToolApprovalGate(
    OwnerToolApprovalCache approvalCache, {
    required ToolCallInfo toolCall,
    required String actionKind,
    required ToolApprovalMode mode,
    required ToolApprovalAutoReviewDomain reviewDomain,
    required bool fullAccessEligible,
    ToolApprovalGateDecision? requiredManualDecision,
    Map<String, dynamic>? approvalCacheArguments,
    String? approvalCacheStateFingerprint,
    Map<String, dynamic>? auditArguments,
    required Future<ToolApprovalAutoReviewRequest> Function()
    buildReviewRequest,
  }) async {
    final cachedApproval = approvalCacheArguments == null
        ? null
        : approvalCache.lookup(
            toolCall.name,
            approvalCacheArguments,
            stateFingerprint: approvalCacheStateFingerprint,
          );
    final hasCachedApproval = cachedApproval?.isApproved == true;
    final auditToolCall = auditArguments != null
        ? ToolCallInfo(
            id: toolCall.id,
            name: toolCall.name,
            arguments: auditArguments,
          )
        : hasCachedApproval
        ? ToolCallInfo(
            id: toolCall.id,
            name: toolCall.name,
            arguments: approvalCacheArguments!,
          )
        : toolCall;
    return ToolApprovalAutoReviewService.resolveGate(
      toolName: toolCall.name,
      hasCachedApproval: hasCachedApproval,
      mode: mode,
      fullAccessEligible: fullAccessEligible,
      requiredManualDecision: requiredManualDecision,
      review: () async => _runApprovalAutoReview(
        await buildReviewRequest(),
        domain: reviewDomain,
      ),
      recordAudit:
          ({
            required String outcome,
            required String decisionSource,
            String? rationale,
            String? riskLevel,
          }) => _recordApprovalAudit(
            approvalCache.owner,
            toolCall: auditToolCall,
            actionKind: actionKind,
            domain: reviewDomain,
            mode: mode,
            outcome: outcome,
            decisionSource: decisionSource,
            rationale: rationale,
            riskLevel: riskLevel,
          ),
      ownerIsCurrent: () => _isApprovalOwnerCurrent(approvalCache.owner),
      deniedEscalates: _domainEscalatesDeniedActionToManual(reviewDomain),
      hasUntrustedInfluence: _conversationTaintState.hasUntrustedInfluence(
        owner: approvalCache.owner,
      ),
      onCachedApproval: () => appLog(
        '[Tool] Reusing cached approval grant for ${toolCall.name}: '
        '${jsonEncode(approvalCacheArguments)}',
      ),
    );
  }

  /// Appends one automated approval decision to the local audit trail. Best
  /// effort: failures never block tool execution.
  Future<void> _recordApprovalAudit(
    ChatTurnOwner owner, {
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
          untrustedInfluence: _conversationTaintState.hasUntrustedInfluence(
            owner: owner,
          ),
          arguments: toolCall.arguments,
          workspaceMode: context?.workspaceMode.name,
          sessionId: context?.sessionId,
          conversationId: context?.conversationId,
        );
  }

  /// Records one out-of-project read release; see [OutsideRootReadGrants].
  void _recordOutsideRootReadAudit({
    required ChatTurnOwner owner,
    required String toolName,
    required String path,
    required bool approved,
  }) {
    unawaited(
      _recordApprovalAudit(
        owner,
        toolCall: ToolCallInfo(
          id: 'outside_root_read',
          name: toolName,
          arguments: {'path': path},
        ),
        actionKind: 'project_read_outside_root',
        domain: ToolApprovalAutoReviewDomain.coding,
        mode: _settings.codingApprovalMode,
        outcome: approved ? 'allowed' : 'denied',
        decisionSource: 'manual_outside_root_read',
        rationale: approved
            ? 'The user released one file outside the project root.'
            : 'The user declined to release a file outside the project root.',
      ),
    );
  }

  /// Assembles an auto-review request, attaching the recent conversation tail.
  /// Shared by every gated tool's `buildReviewRequest` callback.
  ToolApprovalAutoReviewRequest _buildAutoReviewRequest(
    ChatTurnOwner owner, {
    required ToolCallInfo toolCall,
    required String actionKind,
    required Map<String, dynamic> arguments,
    String? path,
    String? workingDirectory,
    String? reason,
    String? warningTitle,
    String? warningMessage,
    String? preview,
    List<String> outOfRootPaths = const [],
    List<Message>? conversationMessages,
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
      outOfRootPaths: outOfRootPaths,
      conversationTail: ToolApprovalAutoReviewService.buildConversationTail(
        conversationMessages ??
            _activeResponseRegistry.messagesForOwner(owner) ??
            const <Message>[],
      ),
      hasUntrustedInfluence: _conversationTaintState.hasUntrustedInfluence(
        owner: owner,
      ),
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
      final response = await _secondaryCompletionRouter.run(
        primaryDataSource: _dataSource,
        route: _settings._approvalAutoReviewCompletionRoute,
        operation: (dataSource, model) => dataSource.createChatCompletion(
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

  /// Coding denials may escalate to a human because those actions are
  /// user-driven. Other domains remain hard-deny security boundaries.
  bool _domainEscalatesDeniedActionToManual(
    ToolApprovalAutoReviewDomain domain,
  ) {
    return domain == ToolApprovalAutoReviewDomain.coding;
  }

  /// The heading for a manual prompt: whatever the gate says, else [fallback].
  String? _escalatedApprovalWarningTitle(
    ToolApprovalGateDecision gate,
    String? fallback,
  ) {
    return gate.approvalPromptTitle ?? fallback;
  }

  /// Prepends the gate's reason for asking, whatever route sent it here.
  String? _escalatedApprovalWarningMessage(
    ToolApprovalGateDecision gate,
    String? fallback,
  ) {
    final rationale = gate.approvalPromptRationale;
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
