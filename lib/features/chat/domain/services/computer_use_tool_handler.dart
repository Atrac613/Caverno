import '../../../../core/services/macos_computer_use_tool_policy.dart';
import '../entities/mcp_tool_entity.dart';
import 'computer_use_action_policy.dart';
import 'computer_use_runtime_coordinator.dart';
import 'computer_use_tool_contract.dart';

export 'computer_use_tool_contract.dart';

// ChatNotifier decomposition collaborator: computer-use-tool-handler

/// Routes Computer Use approval, execution, observation, and audit effects.
final class ComputerUseToolHandler {
  const ComputerUseToolHandler({
    required ComputerUseExecutionPort executionPort,
    required ComputerUseApprovalPort approvalPort,
    required ComputerUseObservationPort observationPort,
    required ComputerUseRuntimeStatePort runtimeStatePort,
    required ComputerUseRuntimeCoordinator runtimeCoordinator,
    required DateTime Function() clock,
    ComputerUseActionPolicy actionPolicy = const ComputerUseActionPolicy(),
  }) : _executionPort = executionPort,
       _approvalPort = approvalPort,
       _observationPort = observationPort,
       _runtimeStatePort = runtimeStatePort,
       _runtimeCoordinator = runtimeCoordinator,
       _clock = clock,
       _actionPolicy = actionPolicy;

  static const _expiredMessage = 'The approval turn expired before execution';
  static const _uncertainMessage =
      'The Computer Use action may have completed after its owner or runtime '
      'expired; inspect possible side effects before retrying';

  final ComputerUseExecutionPort _executionPort;
  final ComputerUseApprovalPort _approvalPort;
  final ComputerUseObservationPort _observationPort;
  final ComputerUseRuntimeStatePort _runtimeStatePort;
  final ComputerUseRuntimeCoordinator _runtimeCoordinator;
  final DateTime Function() _clock;
  final ComputerUseActionPolicy _actionPolicy;

  Future<McpToolResult> handle(ComputerUseToolRequest request) async {
    if (!_preEffectCurrent(request)) return _expired(request.toolName);
    final cached = _approvalPort.lookupDenial(request);
    if (cached != null) {
      return cached.belongsTo(request) &&
              cached.value.toolName == request.toolName &&
              _preEffectCurrent(request)
          ? cached.value
          : _expired(request.toolName);
    }

    final policy = MacosComputerUseToolPolicy.decision(request.toolName);
    final target = _actionPolicy.actionTarget(request.action);
    final exactText = _actionPolicy.exactText(request.action);
    final proposal = MacosComputerUseToolPolicy.actionProposalDecision(
      toolName: request.toolName,
      target: target,
      exactText: exactText,
    );
    final presentation = _actionPolicy.approvalPresentation(request.action);
    final visionContext = _actionPolicy.visionObservationContext(
      request.action,
    );
    final details = _approvalDetails(policy, proposal, presentation.details);

    if (!_preEffectCurrent(request)) return _expired(request.toolName);
    final approval = await _approvalPort.requestApproval(
      ComputerUseApprovalRequest(
        toolRequest: request,
        toolPolicy: policy,
        actionProposalPolicy: proposal,
        presentation: presentation,
        target: target,
        exactText: exactText,
        visionContext: visionContext,
        details: details,
      ),
    );
    if (!approval.belongsTo(request) || !_preEffectCurrent(request)) {
      return _expired(request.toolName);
    }
    final approvalOutcome = approval.value;
    if (approvalOutcome.immediateResult case final result?) {
      return result.toolName == request.toolName
          ? result
          : _expired(request.toolName);
    }
    final decision = approvalOutcome.decision!;
    final code = !decision.approved
        ? decision.blockerCode ?? 'approval_denied'
        : policy?.requiresSmokeArming == true && !decision.armed
        ? 'arming_missing'
        : null;
    if (code != null) {
      return _blocked(
        request,
        policy,
        code,
        auditApprovalResult: code == 'arming_missing'
            ? 'arming_missing'
            : 'denied',
      );
    }
    if (proposal?.blockerCodes.isNotEmpty == true) {
      return _blocked(
        request,
        policy,
        'action_policy_blocked',
        auditApprovalResult: 'blocked',
        blockerCodes: proposal!.blockerCodes,
        proposalNextAction: proposal.nextAction,
      );
    }

    return _runAuthorized(
      request,
      policy,
      approvalResult: 'approved',
      observeAfterSuccess: true,
    );
  }

  Future<McpToolResult> handleWithoutApproval(
    ComputerUseToolRequest request,
  ) async {
    final policy = MacosComputerUseToolPolicy.decision(request.toolName);
    return _runAuthorized(
      request,
      policy,
      approvalResult: 'not_required',
      observeAfterSuccess: false,
    );
  }

  Future<ComputerUseObservationRun> runPostActionObservation(
    ComputerUseToolRequest request,
    MacosComputerUseToolPolicyDecision? policy,
    McpToolResult actionResult,
    ComputerUseRuntimeLease lease,
  ) async {
    if (actionResult.toolName != request.toolName) {
      return const ComputerUseObservationRun.runtimeExpired();
    }
    if (policy?.requiresPostActionObservation != true) {
      return const ComputerUseObservationRun.absent();
    }
    final observationToolName = switch (policy!.riskCategory) {
      MacosComputerUseRiskCategory.input ||
      MacosComputerUseRiskCategory.sensitive => 'computer_vision_observe',
      MacosComputerUseRiskCategory.recovery => 'computer_get_permissions',
      _ => null,
    };
    if (observationToolName == null) {
      return const ComputerUseObservationRun.absent();
    }
    if (!_leaseCurrent(request, lease)) {
      return const ComputerUseObservationRun.runtimeExpired();
    }
    final arguments = observationToolName == 'computer_vision_observe'
        ? _actionPolicy.postActionVisionArguments(request.action)
        : const <String, dynamic>{};
    if (!_leaseCurrent(request, lease)) {
      return const ComputerUseObservationRun.runtimeExpired();
    }
    try {
      final result = await _observationPort.observe(
        ComputerUseObservationRequest(
          toolRequest: request,
          actionResult: actionResult,
          observationToolName: observationToolName,
          arguments: arguments,
        ),
        lease,
      );
      if (!result.belongsTo(request) ||
          result.value.toolName != observationToolName ||
          !_leaseCurrent(request, lease)) {
        return const ComputerUseObservationRun.runtimeExpired();
      }
      return ComputerUseObservationRun.observed(result.value);
    } catch (error) {
      if (!_leaseCurrent(request, lease)) {
        return const ComputerUseObservationRun.runtimeExpired();
      }
      return ComputerUseObservationRun.observed(
        ComputerUsePostActionObservation(
          toolName: observationToolName,
          success: false,
          errorCode: error.toString(),
        ),
      );
    }
  }

  Future<McpToolResult> _runAuthorized(
    ComputerUseToolRequest request,
    MacosComputerUseToolPolicyDecision? policy, {
    required String approvalResult,
    required bool observeAfterSuccess,
  }) async {
    final acquisition = _acquireLease(request);
    final lease = acquisition.lease;
    if (lease == null) return acquisition.failure!;

    var effectStarted = false;
    try {
      if (!_leaseCurrent(request, lease)) {
        return _expired(request.toolName);
      }
      effectStarted = true;
      final completion = await _executionPort.execute(request, lease);
      if (!completion.belongsTo(request) ||
          completion.value.toolName != request.toolName ||
          !_leaseCurrent(request, lease)) {
        _recordUncertainAudit(request, policy, approvalResult);
        return _uncertain(request.toolName);
      }

      final result = completion.value;
      final observation = result.isSuccess && observeAfterSuccess
          ? await runPostActionObservation(request, policy, result, lease)
          : const ComputerUseObservationRun.absent();
      if (observation.runtimeExpired || !_leaseCurrent(request, lease)) {
        _recordUncertainAudit(request, policy, approvalResult, result);
        return _uncertain(request.toolName);
      }
      final auditAccepted = _recordAudit(
        request,
        ComputerUseAuditRecord(
          toolName: request.toolName,
          policy: policy,
          approvalResult: approvalResult,
          success: result.isSuccess,
          result: result.result,
          errorCode: result.errorMessage,
          postActionObservation: observation.observation,
        ),
      );
      if (!auditAccepted || !_leaseCurrent(request, lease)) {
        _recordUncertainAudit(request, policy, approvalResult, result);
        return _uncertain(request.toolName);
      }
      return _actionPolicy.resultWithPostActionObservation(
        ComputerUseResultCompositionInput(
          actionResult: result,
          policy: policy,
          observation: observation.observation,
        ),
      );
    } catch (_) {
      if (effectStarted) {
        _recordUncertainAudit(request, policy, approvalResult);
        return _uncertain(request.toolName);
      }
      rethrow;
    } finally {
      final release = _runtimeCoordinator.releaseLease(lease.token);
      if (release == ComputerUseLeaseReleaseDisposition.invalidationPending) {
        _runtimeCoordinator.settleInvalidatedLease(lease);
      }
    }
  }

  ({ComputerUseRuntimeLease? lease, McpToolResult? failure}) _acquireLease(
    ComputerUseToolRequest request,
  ) {
    if (!_preEffectCurrent(request)) {
      return (lease: null, failure: _expired(request.toolName));
    }
    final now = _clock();
    final arming = _runtimeCoordinator.arm(
      identity: request.identity,
      runtimeRevision: request.runtimeRevision,
      armed: true,
      now: now,
      expiresAt: request.authorizationExpiresAt,
    );
    final grant = arming.grant;
    if (grant == null) {
      return (lease: null, failure: _expired(request.toolName));
    }
    if (!_preEffectCurrent(request)) {
      return (lease: null, failure: _expired(request.toolName));
    }
    final consumption = _runtimeCoordinator.consumeGrant(
      grant: grant,
      identity: request.identity,
      runtimeRevision: request.runtimeRevision,
      now: _clock(),
    );
    final permit = consumption.permit;
    if (permit == null) {
      return (lease: null, failure: _expired(request.toolName));
    }
    final runtime = _captureRuntime();
    if (runtime == null || !runtime.matches(request)) {
      return (lease: null, failure: _expired(request.toolName));
    }
    final acquisition = _runtimeCoordinator.acquireLease(
      permit: permit,
      identity: request.identity,
      currentRuntimeRevision: runtime.revision,
      now: _clock(),
    );
    if (acquisition.disposition ==
        ComputerUseLeaseAcquisitionDisposition.busy) {
      _runtimeCoordinator.discardPermit(permit);
      return (
        lease: null,
        failure: _failure(
          request.toolName,
          'Another Computer Use action is still active',
        ),
      );
    }
    if (acquisition.lease == null) {
      _runtimeCoordinator.discardPermit(permit);
    }
    return (
      lease: acquisition.lease,
      failure: acquisition.lease == null ? _expired(request.toolName) : null,
    );
  }

  McpToolResult _blocked(
    ComputerUseToolRequest request,
    MacosComputerUseToolPolicyDecision? policy,
    String code, {
    required String auditApprovalResult,
    List<String> blockerCodes = const [],
    String? proposalNextAction,
  }) {
    final outcome = _actionPolicy.blockedOutcome(
      ComputerUseBlockedInput(
        action: request.action,
        policy: policy,
        code: code,
        approvalBlockerCodes: blockerCodes,
        actionProposalNextAction: proposalNextAction,
      ),
    );
    if (!_recordAudit(
      request,
      ComputerUseAuditRecord(
        toolName: request.toolName,
        policy: policy,
        approvalResult: auditApprovalResult,
        success: false,
        errorCode: code,
      ),
    )) {
      return _expired(request.toolName);
    }
    final result = McpToolResult(
      toolName: request.toolName,
      result: outcome.result,
      isSuccess: false,
      errorMessage: outcome.errorMessage,
    );
    if (!_preEffectCurrent(request)) return _expired(request.toolName);
    final acknowledgement = _approvalPort.rememberDenial(request, result);
    return acknowledgement.belongsTo(request) &&
            acknowledgement.accepted &&
            _preEffectCurrent(request)
        ? result
        : _expired(request.toolName);
  }

  bool _recordAudit(
    ComputerUseToolRequest request,
    ComputerUseAuditRecord record,
  ) {
    final acknowledgement = _executionPort.recordAudit(request, record);
    return acknowledgement.belongsTo(request) && acknowledgement.accepted;
  }

  void _recordUncertainAudit(
    ComputerUseToolRequest request,
    MacosComputerUseToolPolicyDecision? policy,
    String approvalResult, [
    McpToolResult? result,
  ]) {
    try {
      _executionPort.recordAudit(
        request,
        ComputerUseAuditRecord(
          toolName: request.toolName,
          policy: policy,
          approvalResult: approvalResult,
          success: false,
          result: result?.result,
          errorCode: 'effect_uncertain',
          effectUncertain: true,
        ),
      );
    } catch (_) {
      // The action result already carries the durable reconciliation warning.
    }
  }

  List<String> _approvalDetails(
    MacosComputerUseToolPolicyDecision? policy,
    MacosComputerUseActionProposalPolicyDecision? proposal,
    List<String> actionDetails,
  ) {
    return List<String>.unmodifiable([
      if (policy != null) ...[
        'Policy: ${policy.policyLabel}',
        'Risk category: ${policy.riskCategory.name}',
        'Requires approval: ${policy.requiresUserApproval}',
        'Requires smoke arming: ${policy.requiresSmokeArming}',
        'Requires post-action observation: ${policy.requiresPostActionObservation}',
        if (policy.emergencyStop) 'Emergency stop: true',
      ],
      if (proposal != null) ...[
        'Approval boundaries: ${proposal.boundaries.map((value) => value.name).join(', ')}',
        'Action proposal next action: ${proposal.nextAction}',
        if (proposal.blockerCodes.isNotEmpty)
          'Action proposal blockers: ${proposal.blockerCodes.join(', ')}',
      ],
      ...actionDetails,
    ]);
  }

  bool _preEffectCurrent(ComputerUseToolRequest request) {
    return _approvalPort.isOwnerCurrent(request.owner) &&
        _runtimeCurrent(request) &&
        _clock().isBefore(request.authorizationExpiresAt);
  }

  bool _leaseCurrent(
    ComputerUseToolRequest request,
    ComputerUseRuntimeLease lease,
  ) {
    return _approvalPort.isOwnerCurrent(request.owner) &&
        _runtimeCurrent(request) &&
        _runtimeCoordinator.isLeaseCurrent(
          request.identity,
          request.runtimeRevision,
          lease.token,
        );
  }

  bool _runtimeCurrent(ComputerUseToolRequest request) {
    return _captureRuntime()?.matches(request) ?? false;
  }

  ComputerUseRuntimeState? _captureRuntime() {
    try {
      return _runtimeStatePort.capture();
    } catch (_) {
      return null;
    }
  }

  McpToolResult _expired(String toolName) {
    return _failure(toolName, _expiredMessage);
  }

  McpToolResult _uncertain(String toolName) {
    return _failure(toolName, _uncertainMessage);
  }

  McpToolResult _failure(String toolName, String message) {
    return McpToolResult(
      toolName: toolName,
      result: '',
      isSuccess: false,
      errorMessage: message,
    );
  }
}
