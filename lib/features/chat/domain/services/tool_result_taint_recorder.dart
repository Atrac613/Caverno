import '../../../../core/security/conversation_taint_state.dart';
import '../entities/mcp_tool_entity.dart';

/// Records the immediate execution provenance carried by a tool result.
abstract final class ToolResultTaintRecorder {
  static void record(ConversationTaintState state, McpToolResult result) {
    state.recordToolResult(
      result.toolName,
      isMcpTool: result.isExternalMcpResult,
    );
  }
}
