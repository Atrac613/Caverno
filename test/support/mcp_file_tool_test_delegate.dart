import 'package:caverno/features/chat/data/datasources/mcp_tool_service.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';

export 'package:caverno/features/chat/data/datasources/mcp_tool_service.dart';
export 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
export 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';

mixin FileTools on McpToolService {
  @override
  Future<McpToolResult> executeFileTool({
    required ChatTurnOwner owner,
    required String name,
    required Map<String, dynamic> arguments,
  }) => executeTool(name: name, arguments: arguments);
}
