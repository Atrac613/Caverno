import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

import '../../domain/entities/mcp_tool_entity.dart';
import '../../domain/services/file_rollback_tool_contract.dart';
import 'file_rollback_checkpoint_store.dart';

typedef FileRollbackDenialLookup =
    McpToolResult? Function(FileRollbackToolRequest request);
typedef FileRollbackGateResolver =
    Future<ToolApprovalGateDecision> Function(
      FileRollbackApprovalRequest request,
    );
typedef FileRollbackManualApproval =
    Future<bool> Function(FileRollbackApprovalRequest request);
typedef FileRollbackOwnerCheck =
    bool Function(FileRollbackOperationIdentity identity);
typedef FileRollbackResultRecorder =
    void Function(FileRollbackApprovalRequest request, McpToolResult result);

/// Production seam between the rollback handler and owner-keyed runtime state.
final class FileRollbackToolRuntimeAdapter
    implements
        FileRollbackHistoryPort,
        FileRollbackApprovalPort,
        FileRollbackExecutionPort {
  const FileRollbackToolRuntimeAdapter({
    required FileRollbackCheckpointStore checkpointStore,
    required FileRollbackDenialLookup lookupDenial,
    required FileRollbackGateResolver resolveGate,
    required FileRollbackManualApproval requestManualApproval,
    required FileRollbackOwnerCheck ownerIsCurrent,
    required FileRollbackResultRecorder rememberDenial,
    required FileRollbackResultRecorder rememberResult,
  }) : _checkpointStore = checkpointStore,
       _lookupDenial = lookupDenial,
       _resolveGate = resolveGate,
       _requestManualApproval = requestManualApproval,
       _ownerIsCurrent = ownerIsCurrent,
       _rememberDenial = rememberDenial,
       _rememberResult = rememberResult;

  final FileRollbackCheckpointStore _checkpointStore;
  final FileRollbackDenialLookup _lookupDenial;
  final FileRollbackGateResolver _resolveGate;
  final FileRollbackManualApproval _requestManualApproval;
  final FileRollbackOwnerCheck _ownerIsCurrent;
  final FileRollbackResultRecorder _rememberDenial;
  final FileRollbackResultRecorder _rememberResult;

  @override
  Future<FileRollbackToolPreview?> previewLatest(
    FileRollbackOperationIdentity identity,
  ) async {
    final preview = await _checkpointStore.previewFileRollbackCheckpoint(
      identity.owner,
    );
    if (preview == null) return null;
    if (preview.owner != identity.owner) {
      throw StateError('Rollback checkpoint owner mismatch.');
    }
    return FileRollbackToolPreview(
      identity: identity,
      checkpointToken: preview.checkpointToken,
      path: preview.path,
      preview: preview.preview,
      summary: preview.summary,
    );
  }

  @override
  FileRollbackCachedDenial? lookupDenial(FileRollbackToolRequest request) {
    final result = _lookupDenial(request);
    return result == null
        ? null
        : FileRollbackCachedDenial(identity: request.identity, result: result);
  }

  @override
  Future<FileRollbackApprovalDecision> resolveGate(
    FileRollbackApprovalRequest request,
  ) async {
    return FileRollbackApprovalDecision(
      identity: request.identity,
      checkpointToken: request.checkpointToken,
      gate: await _resolveGate(request),
    );
  }

  @override
  Future<FileRollbackManualApprovalDecision> requestManualApproval(
    FileRollbackApprovalRequest request,
  ) async {
    return FileRollbackManualApprovalDecision(
      identity: request.identity,
      checkpointToken: request.checkpointToken,
      approved: await _requestManualApproval(request),
    );
  }

  @override
  FileRollbackAcknowledgement acknowledgeOwner(
    FileRollbackApprovalRequest request,
  ) {
    return _acknowledgement(
      request,
      _ownerIsCurrent(request.identity)
          ? FileRollbackAcknowledgementDisposition.acknowledged
          : FileRollbackAcknowledgementDisposition.ownerExpired,
    );
  }

  @override
  FileRollbackAcknowledgement rememberDenial(
    FileRollbackApprovalRequest request,
    McpToolResult result,
  ) {
    _rememberDenial(request, result);
    return _acknowledgement(
      request,
      _ownerIsCurrent(request.identity)
          ? FileRollbackAcknowledgementDisposition.acknowledged
          : FileRollbackAcknowledgementDisposition.ownerExpired,
    );
  }

  @override
  FileRollbackAcknowledgement rememberResult(
    FileRollbackApprovalRequest request,
    McpToolResult result,
  ) {
    _rememberResult(request, result);
    return _acknowledgement(
      request,
      _ownerIsCurrent(request.identity)
          ? FileRollbackAcknowledgementDisposition.acknowledged
          : FileRollbackAcknowledgementDisposition.effectUncertain,
    );
  }

  @override
  Future<FileRollbackExecutionResult> rollback(
    FileRollbackOperationIdentity identity,
    String checkpointToken,
  ) async {
    final execution = await _checkpointStore.rollbackFileCheckpoint(
      owner: identity.owner,
      expectedCheckpointToken: checkpointToken,
      toolName: identity.toolName,
    );
    if (execution.owner != identity.owner ||
        execution.checkpointToken != checkpointToken) {
      return FileRollbackExecutionResult.effectUncertain(
        identity: identity,
        checkpointToken: checkpointToken,
      );
    }
    if (!_ownerIsCurrent(identity)) {
      if (execution.disposition ==
          FileRollbackCheckpointExecutionDisposition.checkpointChanged) {
        return FileRollbackExecutionResult.ownerExpired(
          identity: identity,
          checkpointToken: checkpointToken,
          expiredEffectDisposition:
              FileRollbackExpiredEffectDisposition.notApplied,
        );
      }
      if (execution.disposition ==
              FileRollbackCheckpointExecutionDisposition.completed &&
          execution.result?.isSuccess == true) {
        return FileRollbackExecutionResult.ownerExpired(
          identity: identity,
          checkpointToken: checkpointToken,
          expiredEffectDisposition:
              FileRollbackExpiredEffectDisposition.retained,
        );
      }
      if (execution.disposition !=
          FileRollbackCheckpointExecutionDisposition.ownerExpiredBeforeEffect) {
        return FileRollbackExecutionResult.effectUncertain(
          identity: identity,
          checkpointToken: checkpointToken,
        );
      }
    }
    return switch (execution.disposition) {
      FileRollbackCheckpointExecutionDisposition.completed ||
      FileRollbackCheckpointExecutionDisposition.checkpointChanged =>
        FileRollbackExecutionResult.completed(
          identity: identity,
          checkpointToken: checkpointToken,
          result: execution.result!,
        ),
      FileRollbackCheckpointExecutionDisposition.ownerExpiredBeforeEffect =>
        FileRollbackExecutionResult.ownerExpired(
          identity: identity,
          checkpointToken: checkpointToken,
          expiredEffectDisposition:
              FileRollbackExpiredEffectDisposition.notApplied,
        ),
      FileRollbackCheckpointExecutionDisposition.ownerExpiredAfterEffect =>
        FileRollbackExecutionResult.ownerExpired(
          identity: identity,
          checkpointToken: checkpointToken,
          expiredEffectDisposition:
              FileRollbackExpiredEffectDisposition.retained,
        ),
      FileRollbackCheckpointExecutionDisposition.effectUncertain =>
        FileRollbackExecutionResult.effectUncertain(
          identity: identity,
          checkpointToken: checkpointToken,
        ),
    };
  }

  FileRollbackAcknowledgement _acknowledgement(
    FileRollbackApprovalRequest request,
    FileRollbackAcknowledgementDisposition disposition,
  ) {
    return FileRollbackAcknowledgement(
      identity: request.identity,
      checkpointToken: request.checkpointToken,
      disposition: disposition,
    );
  }
}
