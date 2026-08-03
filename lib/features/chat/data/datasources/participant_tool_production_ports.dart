import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import '../../domain/services/participant_tool_executor.dart';
import '../../domain/services/turn_tool_approval_coordinator.dart';
import 'participant_tool_runtime_contract.dart';

export '../../domain/services/participant_tool_policy.dart';
export '../../domain/services/participant_tool_executor.dart';
export 'participant_tool_runtime_adapter.dart';
export 'turn_tool_approval_runtime_ports.dart';

typedef ParticipantToolManualApprovalCallback =
    Future<bool> Function(
      ParticipantToolRuntimeIdentity identity,
      Map<String, dynamic> arguments,
    );
typedef ParticipantToolEffectCallback =
    Future<McpToolResult> Function(
      ParticipantToolRuntimeIdentity identity,
      Map<String, dynamic> arguments,
    );
typedef ParticipantToolActivityProjection =
    bool Function(
      ParticipantToolRuntimeIdentity identity,
      String activeToolName,
    );
typedef ParticipantToolTaintRecorder =
    void Function(
      ParticipantToolRuntimeIdentity identity,
      McpToolResult result,
    );
typedef ParticipantToolAuditCallback =
    Future<void> Function(
      ParticipantToolRuntimeIdentity identity,
      ToolApprovalAuditRecord record,
    );

/// Owner-validating production callbacks used by participant tool execution.
final class ParticipantToolProductionPorts {
  const ParticipantToolProductionPorts({
    required this.scope,
    required this.participantDisplayName,
    required ParticipantToolManualApprovalCallback requestManualApproval,
    required ToolApprovalAutoReviewPort autoReviewPort,
    required ParticipantToolAuditCallback recordAudit,
    required ToolApprovalOwnerPort ownerPort,
    required ParticipantToolActivityProjection projectActivity,
    required ParticipantToolTaintRecorder recordTaint,
    ParticipantToolEffectCallback? executeEffect,
  }) : _requestManualApproval = requestManualApproval,
       _autoReviewPort = autoReviewPort,
       _recordAudit = recordAudit,
       _ownerPort = ownerPort,
       _executeEffect = executeEffect,
       _projectActivity = projectActivity,
       _recordTaint = recordTaint;

  final ParticipantToolScope scope;
  final String participantDisplayName;
  final ParticipantToolManualApprovalCallback _requestManualApproval;
  final ToolApprovalAutoReviewPort _autoReviewPort;
  final ParticipantToolAuditCallback _recordAudit;
  final ToolApprovalOwnerPort _ownerPort;
  final ParticipantToolEffectCallback? _executeEffect;
  final ParticipantToolActivityProjection _projectActivity;
  final ParticipantToolTaintRecorder _recordTaint;

  Future<ParticipantToolApprovalAcknowledgement> resolveApproval(
    ParticipantToolRuntimeApprovalRequest runtimeRequest,
  ) async {
    final identity = runtimeRequest.identity;
    if (!_matches(identity)) {
      return ParticipantToolApprovalAcknowledgement(
        identity: identity,
        disposition: ParticipantToolApprovalDisposition.effectUncertain,
      );
    }
    if (!_ownerPort.isCurrent(identity.owner)) {
      return ParticipantToolApprovalAcknowledgement(
        identity: identity,
        disposition: ParticipantToolApprovalDisposition.ownerExpired,
      );
    }
    final approvalRequest = runtimeRequest.request;
    final coordinator = TurnToolApprovalCoordinator(
      manualApprovalPort: _ParticipantManualApprovalPort(
        identity: identity,
        arguments: approvalRequest.manualArguments,
        requestApproval: _requestManualApproval,
      ),
      autoReviewPort: _autoReviewPort,
      auditPort: _ParticipantToolAuditPort(identity, _recordAudit),
      ownerPort: _ownerPort,
    );
    final preflight = await coordinator.preflightCachedDenial(
      approvalRequest.coordinatorRequest,
    );
    final outcome =
        preflight.outcome ??
        await coordinator.resolveAfterPreflight(
          preflight,
          targetDisplayName: participantDisplayName,
        );
    if (!_ownerPort.isCurrent(identity.owner)) {
      return ParticipantToolApprovalAcknowledgement(
        identity: identity,
        disposition: ParticipantToolApprovalDisposition.ownerExpired,
      );
    }
    return ParticipantToolApprovalAcknowledgement(
      identity: identity,
      disposition: ParticipantToolApprovalDisposition.resolved,
      outcome: outcome,
    );
  }

  Future<ParticipantToolExecutionAcknowledgement> execute(
    ParticipantToolRuntimeExecutionRequest request,
  ) async {
    final identity = request.identity;
    if (!_matches(identity)) {
      return ParticipantToolExecutionAcknowledgement(
        identity: identity,
        disposition: ParticipantToolExecutionDisposition.effectUncertain,
      );
    }
    if (!_ownerPort.isCurrent(identity.owner)) {
      return ParticipantToolExecutionAcknowledgement(
        identity: identity,
        disposition:
            ParticipantToolExecutionDisposition.ownerExpiredBeforeEffect,
      );
    }
    final executeEffect = _executeEffect;
    if (executeEffect == null) {
      return ParticipantToolExecutionAcknowledgement(
        identity: identity,
        disposition: ParticipantToolExecutionDisposition.rejected,
        result: McpToolResult(
          toolName: identity.toolName,
          result: '',
          isSuccess: false,
          errorMessage: 'Participant tool service is unavailable.',
        ),
      );
    }
    final result = await executeEffect(identity, request.arguments);
    return ParticipantToolExecutionAcknowledgement(
      identity: identity,
      disposition: result.isSuccess
          ? ParticipantToolExecutionDisposition.completed
          : ParticipantToolExecutionDisposition.rejected,
      result: result,
    );
  }

  ParticipantToolActivityAcknowledgement projectActivity(
    ParticipantToolRuntimeActivityRequest request,
  ) {
    final identity = request.identity;
    if (!_matches(identity)) {
      return ParticipantToolActivityAcknowledgement(
        identity: identity,
        activeToolName: request.activeToolName,
        disposition: ParticipantToolActivityDisposition.effectUncertain,
      );
    }
    if (!_ownerPort.isCurrent(identity.owner)) {
      return ParticipantToolActivityAcknowledgement(
        identity: identity,
        activeToolName: request.activeToolName,
        disposition: ParticipantToolActivityDisposition.ownerExpired,
      );
    }
    if (!_projectActivity(identity, request.activeToolName)) {
      return ParticipantToolActivityAcknowledgement(
        identity: identity,
        activeToolName: request.activeToolName,
        disposition: ParticipantToolActivityDisposition.rejected,
      );
    }
    return ParticipantToolActivityAcknowledgement(
      identity: identity,
      activeToolName: request.activeToolName,
      disposition: ParticipantToolActivityDisposition.applied,
    );
  }

  ParticipantToolTaintAcknowledgement recordTaint(
    ParticipantToolRuntimeTaintRequest request,
  ) {
    final identity = request.identity;
    if (!_matches(identity)) {
      return ParticipantToolTaintAcknowledgement(
        identity: identity,
        resultFingerprint: request.resultFingerprint,
        disposition: ParticipantToolTaintDisposition.effectUncertain,
      );
    }
    _recordTaint(identity, request.result);
    return ParticipantToolTaintAcknowledgement(
      identity: identity,
      resultFingerprint: request.resultFingerprint,
      disposition: ParticipantToolTaintDisposition.recorded,
    );
  }

  bool _matches(ParticipantToolRuntimeIdentity identity) =>
      identity.scope == scope;
}

final class _ParticipantToolAuditPort implements ToolApprovalAuditPort {
  const _ParticipantToolAuditPort(this.identity, this._recordAudit);

  final ParticipantToolRuntimeIdentity identity;
  final ParticipantToolAuditCallback _recordAudit;

  @override
  Future<void> record(ChatTurnOwner owner, ToolApprovalAuditRecord record) {
    if (owner != identity.owner || record.toolName != identity.toolName) {
      throw StateError('Participant tool audit identity mismatch.');
    }
    return _recordAudit(identity, record);
  }
}

final class _ParticipantManualApprovalPort implements ManualToolApprovalPort {
  const _ParticipantManualApprovalPort({
    required this.identity,
    required this.arguments,
    required ParticipantToolManualApprovalCallback requestApproval,
  }) : _requestApproval = requestApproval;

  final ParticipantToolRuntimeIdentity identity;
  final Map<String, dynamic> arguments;
  final ParticipantToolManualApprovalCallback _requestApproval;

  @override
  Future<ManualToolApprovalDecision> requestApproval(
    ChatTurnOwner owner,
    ManualToolApprovalRequest request,
  ) async {
    if (owner != identity.owner ||
        request.toolCallId != identity.toolCallId ||
        request.toolName != identity.toolName) {
      return ManualToolApprovalDecision.denied(
        ParticipantToolExecutor.manualApprovalDeniedResult(identity.toolName),
      );
    }
    final approved = await _requestApproval(identity, arguments);
    return approved
        ? const ManualToolApprovalDecision.approved()
        : ManualToolApprovalDecision.denied(
            ParticipantToolExecutor.manualApprovalDeniedResult(
              identity.toolName,
            ),
          );
  }
}
