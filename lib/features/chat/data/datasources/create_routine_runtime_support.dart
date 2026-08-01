import 'create_routine_runtime_contract.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import '../../domain/services/create_routine_tool_handler.dart';

int createRoutineRuntimePriority(
  CreateRoutineRuntimeDisposition? disposition,
) => switch (disposition) {
  null => 0,
  CreateRoutineRuntimeDisposition.completed => 0,
  CreateRoutineRuntimeDisposition.rejected => 1,
  CreateRoutineRuntimeDisposition.ownerExpired => 2,
  CreateRoutineRuntimeDisposition.effectUncertain => 3,
  CreateRoutineRuntimeDisposition.boundaryMismatch => 4,
};

McpToolResult createRoutineRuntimeFailure(String message) => McpToolResult(
  toolName: createRoutineToolName,
  result: '',
  isSuccess: false,
  errorMessage: message,
);

bool matchesCreateRoutineOperation(
  CreateRoutineOperationIdentity operation,
  CreateRoutineRuntimeIdentity runtime,
) =>
    operation.owner == runtime.owner &&
    operation.toolCallId == runtime.toolCallId &&
    operation.toolName == runtime.toolName;

enum CreateRoutineSuccessReleaseResult {
  released,
  boundaryMismatch,
  effectUncertain,
}

Future<CreateRoutineSuccessReleaseResult> releaseCreateRoutineSuccess(
  CreateRoutineSuccessReleaseCallback release,
  CreateRoutineSuccessIdentity identity,
) async {
  try {
    final acknowledgement = await release(identity);
    if (acknowledgement.identity != identity) {
      return CreateRoutineSuccessReleaseResult.boundaryMismatch;
    }
    return acknowledgement.disposition ==
            CreateRoutineSuccessReleaseDisposition.released
        ? CreateRoutineSuccessReleaseResult.released
        : CreateRoutineSuccessReleaseResult.effectUncertain;
  } catch (_) {
    return CreateRoutineSuccessReleaseResult.effectUncertain;
  }
}

final class CreateRoutineRuntimeObservation {
  CreateRoutineRuntimeDisposition? _disposition;

  CreateRoutineRuntimeDisposition classify(McpToolResult result) {
    if (result.isSuccess) return CreateRoutineRuntimeDisposition.completed;
    return _disposition ?? CreateRoutineRuntimeDisposition.rejected;
  }

  void observeApproval(CreateRoutineApprovalDisposition disposition) {
    switch (disposition) {
      case CreateRoutineApprovalDisposition.approved:
        return;
      case CreateRoutineApprovalDisposition.rejected:
        observe(CreateRoutineRuntimeDisposition.rejected);
      case CreateRoutineApprovalDisposition.ownerExpired:
        observe(CreateRoutineRuntimeDisposition.ownerExpired);
      case CreateRoutineApprovalDisposition.effectUncertain:
        observe(CreateRoutineRuntimeDisposition.effectUncertain);
    }
  }

  void observeOwner(CreateRoutineOwnerDisposition disposition) {
    switch (disposition) {
      case CreateRoutineOwnerDisposition.current:
        return;
      case CreateRoutineOwnerDisposition.ownerExpired:
        observe(CreateRoutineRuntimeDisposition.ownerExpired);
      case CreateRoutineOwnerDisposition.effectUncertain:
        observe(CreateRoutineRuntimeDisposition.effectUncertain);
    }
  }

  void observe(CreateRoutineRuntimeDisposition disposition) {
    if (createRoutineRuntimePriority(disposition) >
        createRoutineRuntimePriority(_disposition)) {
      _disposition = disposition;
    }
  }
}
