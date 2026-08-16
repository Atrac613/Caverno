export '../../domain/services/file_rollback_tool_handler.dart';
export 'file_rollback_tool_runtime_adapter.dart';

import '../../domain/services/file_rollback_tool_handler.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import '../../domain/entities/chat_turn_owner.dart';
import 'built_in_filesystem_tool_handler.dart';
import 'file_rollback_checkpoint_store.dart';
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

  void beginFileTurnCheckpoint(ChatTurnOwner owner, String turnId) =>
      filesystemToolHandler.checkpointStore.beginFileTurnCheckpoint(
        owner,
        turnId,
      );

  void beginChatFileTurnCheckpoint(ChatTurnOwner owner) =>
      beginFileTurnCheckpoint(
        owner,
        'chat_generation_${owner.interactionGeneration}',
      );

  bool endFileTurnCheckpoint(ChatTurnOwner owner) =>
      filesystemToolHandler.checkpointStore.endFileTurnCheckpoint(owner);

  Future<FileTurnRollbackPreview?> previewLastFileTurnCheckpoint(
    ChatTurnOwner owner,
  ) => filesystemToolHandler.checkpointStore.previewLastFileTurnCheckpoint(
    owner,
  );

  Future<McpToolResult> rollbackLastFileTurnCheckpoint(
    ChatTurnOwner owner,
    int expectedCheckpointToken,
  ) {
    return filesystemToolHandler.checkpointStore.rollbackLastFileTurnCheckpoint(
      owner,
      expectedCheckpointToken,
    );
  }

  /// The recovery half of [rollbackLastFileTurnCheckpoint]: both are exposed
  /// here so a caller holding the service can finish a rollback it started.
  Future<McpToolResult> reconcileFileTurnRollbackRecovery({
    required ChatTurnOwner owner,
    required String recoveryReceipt,
  }) => filesystemToolHandler.checkpointStore.reconcileFileTurnRollbackRecovery(
    owner: owner,
    recoveryReceipt: recoveryReceipt,
  );

  Future<FileTurnRollbackPreview?> previewFsTurn(String? conversationId) async {
    final owner = filesystemToolHandler.checkpointStore
        .latestCompletedCheckpointOwner(conversationId ?? '');
    return owner == null ? null : previewLastFileTurnCheckpoint(owner);
  }
}
