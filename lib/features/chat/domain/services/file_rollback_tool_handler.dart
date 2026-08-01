// ChatNotifier decomposition collaborator: file-rollback-tool-handler

import '../entities/mcp_tool_entity.dart';
import 'file_rollback_tool_contract.dart';

export 'file_rollback_tool_contract.dart';

/// Coordinates one exact approved rollback without reading ambient state.
final class FileRollbackToolHandler {
  const FileRollbackToolHandler({
    required FileRollbackHistoryPort historyPort,
    required FileRollbackApprovalPort approvalPort,
    required FileRollbackExecutionPort executionPort,
  }) : _historyPort = historyPort,
       _approvalPort = approvalPort,
       _executionPort = executionPort;

  static const String _expiredMessage =
      'Tool approval expired before execution';
  static const String _effectUncertainMessage =
      'The file change may have been rolled back; inspect the target before '
      'retrying';

  final FileRollbackHistoryPort _historyPort;
  final FileRollbackApprovalPort _approvalPort;
  final FileRollbackExecutionPort _executionPort;

  Future<McpToolResult> handle(FileRollbackToolRequest request) async {
    final identity = request.identity;
    final cachedDenial = _approvalPort.lookupDenial(request);
    if (cachedDenial != null) {
      _requireIdentity(
        cachedDenial.identity,
        identity,
        'Cached rollback denial',
      );
      _requireToolResult(
        cachedDenial.result,
        identity,
        'Cached rollback denial',
      );
      return cachedDenial.result;
    }

    final target = await _historyPort.previewLatest(identity);
    if (target == null) {
      return _failure(
        request.toolName,
        'No recent file change is available to roll back',
      );
    }
    _requireCheckpointIdentity(target, identity, 'Rollback preview');

    final suppliedReason = request.reason;
    final reason = suppliedReason?.trim().isNotEmpty == true
        ? suppliedReason
        : target.summary;
    final approvalRequest = FileRollbackApprovalRequest(
      toolRequest: request,
      target: target,
      reason: reason,
    );
    final approvalDecision = await _approvalPort.resolveGate(approvalRequest);
    _requireBoundResponse(
      approvalDecision.belongsTo(approvalRequest),
      'Rollback approval',
    );
    final gate = approvalDecision.gate;
    if (gate.isDenied) {
      return _rememberDenial(
        approvalRequest,
        _autoReviewDeniedResult(request.toolName, gate.deniedRationale!),
      );
    }
    if (gate.needsManual) {
      final decision = await _approvalPort.requestManualApproval(
        approvalRequest,
      );
      _requireBoundResponse(
        decision.belongsTo(approvalRequest),
        'Manual rollback approval',
      );
      if (!decision.approved) {
        return _rememberDenial(
          approvalRequest,
          _failure(request.toolName, 'User denied file rollback'),
        );
      }
    }

    final ownerAcknowledgement = _approvalPort.acknowledgeOwner(
      approvalRequest,
    );
    _requireBoundResponse(
      ownerAcknowledgement.belongsTo(approvalRequest),
      'Rollback owner acknowledgement',
    );
    if (ownerAcknowledgement.disposition !=
        FileRollbackAcknowledgementDisposition.acknowledged) {
      return _ownerExpired(request.toolName);
    }

    final FileRollbackExecutionResult execution;
    try {
      execution = await _executionPort.rollback(
        identity,
        target.checkpointToken,
      );
    } catch (_) {
      return _effectUncertain(request.toolName);
    }
    if (!execution.belongsTo(approvalRequest)) {
      return _effectUncertain(request.toolName);
    }
    switch (execution.disposition) {
      case FileRollbackExecutionDisposition.effectUncertain:
        return _effectUncertain(request.toolName);
      case FileRollbackExecutionDisposition.ownerExpired:
        return switch (execution.expiredEffectDisposition!) {
          FileRollbackExpiredEffectDisposition.notApplied ||
          FileRollbackExpiredEffectDisposition.compensated => _ownerExpired(
            request.toolName,
          ),
          FileRollbackExpiredEffectDisposition.retained ||
          FileRollbackExpiredEffectDisposition.uncertain => _effectUncertain(
            request.toolName,
          ),
        };
      case FileRollbackExecutionDisposition.completed:
        final result = execution.result!;
        if (result.toolName != request.toolName) {
          return _effectUncertain(request.toolName);
        }
        if (gate.bypassedApproval) {
          return result;
        }
        try {
          final acknowledgement = _approvalPort.rememberResult(
            approvalRequest,
            result,
          );
          if (!acknowledgement.belongsTo(approvalRequest) ||
              acknowledgement.disposition !=
                  FileRollbackAcknowledgementDisposition.acknowledged) {
            return _effectUncertain(request.toolName);
          }
        } catch (_) {
          return _effectUncertain(request.toolName);
        }
        return result;
    }
  }

  McpToolResult _rememberDenial(
    FileRollbackApprovalRequest request,
    McpToolResult result,
  ) {
    final acknowledgement = _approvalPort.rememberDenial(request, result);
    _requireBoundResponse(
      acknowledgement.belongsTo(request),
      'Rollback denial acknowledgement',
    );
    if (acknowledgement.disposition !=
        FileRollbackAcknowledgementDisposition.acknowledged) {
      return _ownerExpired(request.identity.toolName);
    }
    return result;
  }

  void _requireCheckpointIdentity(
    FileRollbackToolPreview target,
    FileRollbackOperationIdentity expected,
    String source,
  ) {
    _requireIdentity(target.identity, expected, source);
  }

  void _requireIdentity(
    FileRollbackOperationIdentity actual,
    FileRollbackOperationIdentity expected,
    String source,
  ) {
    _requireBoundResponse(actual == expected, source);
  }

  void _requireToolResult(
    McpToolResult result,
    FileRollbackOperationIdentity expected,
    String source,
  ) {
    _requireBoundResponse(result.toolName == expected.toolName, source);
  }

  void _requireBoundResponse(bool matches, String source) {
    if (!matches) {
      throw StateError('$source identity mismatch.');
    }
  }

  McpToolResult _ownerExpired(String toolName) {
    return _failure(toolName, _expiredMessage);
  }

  McpToolResult _effectUncertain(String toolName) {
    return _failure(toolName, _effectUncertainMessage);
  }

  McpToolResult _failure(String toolName, String message) {
    return McpToolResult(
      toolName: toolName,
      result: '',
      isSuccess: false,
      errorMessage: message,
    );
  }

  McpToolResult _autoReviewDeniedResult(String toolName, String rationale) {
    return McpToolResult(
      toolName: toolName,
      result: 'Auto-review denied this action. Rationale: $rationale',
      isSuccess: false,
      errorMessage: 'Auto-review denied: $rationale',
    );
  }
}
