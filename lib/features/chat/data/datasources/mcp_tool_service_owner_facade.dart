import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import 'background_process_monitor_service.dart';
import 'background_process_tools.dart';
import 'built_in_filesystem_tool_handler.dart';
import 'built_in_local_command_tool_handler.dart';
import 'file_rollback_checkpoint_store.dart';

/// Owner-bound operations implemented as overridable service instance methods.
mixin McpToolServiceOwnerFacade {
  BuiltInFilesystemToolHandler get filesystemToolHandler;
  BuiltInLocalCommandToolHandler get localCommandToolHandler;
  BackgroundProcessMonitorService? get backgroundProcessMonitorService;
  BackgroundProcessTools? get backgroundProcessTools;

  Future<McpToolResult> executeFileTool({
    required ChatTurnOwner owner,
    required String name,
    required Map<String, dynamic> arguments,
  }) => filesystemToolHandler.execute(
    name: name,
    arguments: arguments,
    owner: owner,
  );

  Future<McpToolResult> executeProcessTool({
    required ChatTurnOwner owner,
    required String name,
    required Map<String, dynamic> arguments,
  }) => localCommandToolHandler.execute(
    owner: owner,
    name: name,
    arguments: arguments,
  );

  Future<void> clearBackgroundProcessOwner(ChatTurnOwner owner) {
    backgroundProcessMonitorService?.clearOwner(owner);
    return backgroundProcessTools?.clearOwner(owner: owner) ??
        Future<void>.value();
  }

  Future<FileRollbackPreview?> previewFileRollback(ChatTurnOwner owner) =>
      filesystemToolHandler.checkpointStore.previewLastFileRollbackChange(
        owner,
      );

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
  }) => filesystemToolHandler.checkpointStore
      .reconcileFileTurnRollbackRecovery(
        owner: owner,
        recoveryReceipt: recoveryReceipt,
      );

  Future<FileTurnRollbackPreview?> previewFsTurn(String? conversationId) async {
    final owner = filesystemToolHandler.checkpointStore
        .latestCompletedCheckpointOwner(conversationId ?? '');
    return owner == null ? null : previewLastFileTurnCheckpoint(owner);
  }
}
