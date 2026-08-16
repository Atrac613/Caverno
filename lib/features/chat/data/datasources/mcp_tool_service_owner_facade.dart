import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import 'background_process_monitor_service.dart';
import 'background_process_tools.dart';
import 'built_in_filesystem_tool_handler.dart';
import 'built_in_local_command_tool_handler.dart';
import 'file_rollback_checkpoint_store.dart';
import 'owner_tool_routing.dart';

/// Owner-bound operations implemented as overridable service instance methods.
mixin McpToolServiceOwnerFacade {
  BuiltInFilesystemToolHandler get filesystemToolHandler;
  BuiltInLocalCommandToolHandler get localCommandToolHandler;

  Future<McpToolResult> executeFileTool({
    required ChatTurnOwner owner,
    required String name,
    required Map<String, dynamic> arguments,
  }) => filesystemToolHandler.executeOwned(
    owner: owner,
    name: name,
    arguments: arguments,
  );

  Future<McpToolResult> executeProcessTool({
    required ChatTurnOwner owner,
    required String name,
    required Map<String, dynamic> arguments,
  }) => localCommandToolHandler.executeOwned(
    owner: owner,
    name: name,
    arguments: arguments,
  );

  BackgroundProcessMonitorService? get backgroundProcessMonitorService;
  BackgroundProcessTools? get backgroundProcessTools;

  /// Ends the turn's ownership; jobs still running are carried, not killed.
  Future<void> clearBackgroundProcessOwner(ChatTurnOwner owner) {
    backgroundProcessMonitorService?.clearOwner(owner);
    return backgroundProcessTools?.clearOwner(owner: owner) ??
        Future<void>.value();
  }

  /// Ends the conversation's ownership, terminating anything it carried. Not
  /// the same boundary: releasing a turn is not releasing its processes.
  Future<void> clearBackgroundProcessConversation(String conversationId) {
    backgroundProcessMonitorService?.clearConversation(conversationId);
    return backgroundProcessTools?.clearConversation(
          conversationId: conversationId,
        ) ??
        Future<void>.value();
  }

  Future<FileRollbackPreview?> previewFileRollback(ChatTurnOwner owner) =>
      filesystemToolHandler.checkpointStore.previewLastFileRollbackChange(
        owner,
      );
}
