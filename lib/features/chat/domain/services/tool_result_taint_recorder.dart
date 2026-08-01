import '../../../../core/security/conversation_taint_state.dart';
import '../entities/chat_turn_owner.dart';
import '../entities/mcp_tool_entity.dart';

/// Records the immediate execution provenance carried by a tool result.
abstract final class ToolResultTaintRecorder {
  static void record({
    required ConversationTaintState state,
    required ChatTurnOwner owner,
    required McpToolResult result,
  }) {
    state.recordToolResult(
      owner: owner,
      toolName: result.toolName,
      isMcpTool: result.isExternalMcpResult,
    );
  }
}
