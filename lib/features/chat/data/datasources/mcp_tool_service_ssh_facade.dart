import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import 'built_in_ssh_tool_handler.dart';

/// Exact-owner SSH entrypoints kept outside generic MCP dispatch.
mixin McpToolServiceSshFacade {
  BuiltInSshToolHandler get sshToolHandler;

  Future<McpToolResult> executeSshTool({
    required ChatTurnOwner owner,
    required String name,
    required Map<String, dynamic> arguments,
  }) => sshToolHandler.execute(owner: owner, name: name, arguments: arguments);
}
