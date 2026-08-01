export '../../domain/services/file_rollback_tool_handler.dart';
export 'file_rollback_tool_runtime_adapter.dart';

import '../../domain/services/file_rollback_tool_handler.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import 'built_in_filesystem_tool_handler.dart';
import 'file_rollback_tool_runtime_adapter.dart';

/// Exact owner boundary for single-file rollback execution.
mixin McpToolServiceFileRollbackFacade {
  BuiltInFilesystemToolHandler get filesystemToolHandler;

  Future<McpToolResult> executeExactFileRollback({
    required FileRollbackToolRequest request,
    required FileRollbackDenialLookup lookupDenial,
    required FileRollbackGateResolver resolveGate,
    required FileRollbackManualApproval requestManualApproval,
    required FileRollbackOwnerCheck ownerIsCurrent,
    required FileRollbackResultRecorder rememberDenial,
    required FileRollbackResultRecorder rememberResult,
  }) {
    final adapter = FileRollbackToolRuntimeAdapter(
      checkpointStore: filesystemToolHandler.checkpointStore,
      lookupDenial: lookupDenial,
      resolveGate: resolveGate,
      requestManualApproval: requestManualApproval,
      ownerIsCurrent: ownerIsCurrent,
      rememberDenial: rememberDenial,
      rememberResult: rememberResult,
    );
    return FileRollbackToolHandler(
      historyPort: adapter,
      approvalPort: adapter,
      executionPort: adapter,
    ).handle(request);
  }
}
