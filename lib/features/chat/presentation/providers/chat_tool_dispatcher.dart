import '../../../../core/services/browser_tool_policy.dart';
import '../../../../core/services/macos_computer_use_tool_policy.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import '../../domain/entities/tool_call_info.dart';

typedef ChatToolHandler = Future<McpToolResult> Function(ToolCallInfo toolCall);
typedef ChatToolPlanningPolicy = McpToolResult? Function(ToolCallInfo toolCall);

final class ChatToolHandlerRegistry {
  const ChatToolHandlerRegistry(this._handlers);

  final Map<String, ChatToolHandler> _handlers;

  Future<McpToolResult?> dispatch(ToolCallInfo toolCall) {
    final handler = _handlers[toolCall.name];
    if (handler == null) {
      return Future.value();
    }
    return handler(toolCall);
  }
}

final class ChatToolDispatcher {
  const ChatToolDispatcher({
    required this.enforcePlanningPolicy,
    required this.handleComputerUseAction,
    required this.handleComputerUseObservation,
    required this.handleBrowserAction,
    required this.handleBrowserObservation,
    required this.handlerRegistry,
    required this.executeFallbackTool,
  });

  final ChatToolPlanningPolicy enforcePlanningPolicy;
  final ChatToolHandler handleComputerUseAction;
  final ChatToolHandler handleComputerUseObservation;
  final ChatToolHandler handleBrowserAction;
  final ChatToolHandler handleBrowserObservation;
  final ChatToolHandlerRegistry handlerRegistry;
  final ChatToolHandler executeFallbackTool;

  Future<McpToolResult> dispatch(ToolCallInfo toolCall) async {
    final planningPolicyResult = enforcePlanningPolicy(toolCall);
    if (planningPolicyResult != null) {
      return planningPolicyResult;
    }

    if (MacosComputerUseToolPolicy.requiresUserApproval(toolCall.name)) {
      return handleComputerUseAction(toolCall);
    }
    if (MacosComputerUseToolPolicy.isComputerUseTool(toolCall.name)) {
      return handleComputerUseObservation(toolCall);
    }

    if (BrowserToolPolicy.requiresUserApproval(toolCall.name)) {
      return handleBrowserAction(toolCall);
    }
    if (BrowserToolPolicy.isBrowserTool(toolCall.name)) {
      return handleBrowserObservation(toolCall);
    }

    final registryResult = await handlerRegistry.dispatch(toolCall);
    if (registryResult != null) {
      return registryResult;
    }

    return executeFallbackTool(toolCall);
  }
}
