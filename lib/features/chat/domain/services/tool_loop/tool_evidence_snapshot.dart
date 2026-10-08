import '../../entities/tool_call_info.dart';
import '../immutable_json_snapshot.dart';

ToolCallInfo freezeToolCall(ToolCallInfo toolCall) {
  return ToolCallInfo(
    id: toolCall.id,
    name: toolCall.name,
    arguments: ImmutableJsonSnapshot.freezeMap(toolCall.arguments),
  );
}

ToolResultInfo freezeToolResult(ToolResultInfo toolResult) {
  return ToolResultInfo(
    id: toolResult.id,
    name: toolResult.name,
    arguments: ImmutableJsonSnapshot.freezeMap(toolResult.arguments),
    result: toolResult.result,
  );
}
