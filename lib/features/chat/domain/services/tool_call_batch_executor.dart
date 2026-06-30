import '../entities/mcp_tool_entity.dart';
import '../entities/tool_call_info.dart';
import 'tool_call_execution_policy.dart';

typedef ToolCallDispatch =
    Future<McpToolResult> Function(ToolCallInfo toolCall);

class ToolCallBatchExecutionResult {
  const ToolCallBatchExecutionResult({
    required this.toolResults,
    required this.abortLoop,
  });

  final List<ToolResultInfo> toolResults;
  final bool abortLoop;
}

class ToolCallBatchExecutor {
  const ToolCallBatchExecutor({
    ToolCallExecutionPolicy toolCallExecutionPolicy =
        const ToolCallExecutionPolicy(),
  }) : _toolCallExecutionPolicy = toolCallExecutionPolicy;

  final ToolCallExecutionPolicy _toolCallExecutionPolicy;

  Future<ToolCallBatchExecutionResult> execute({
    required List<ToolCallInfo> toolCalls,
    required ToolCallDispatch dispatchToolCall,
    required Set<String> executedToolCallKeys,
    required Map<String, int> toolFailureCounts,
    int commandRetryGeneration = 0,
  }) async {
    final toolResults = <ToolResultInfo>[];
    var abortLoop = false;

    for (final toolCall in toolCalls) {
      final toolCallKey = _toolCallExecutionPolicy.toolExecutionKey(
        toolCall,
        commandRetryGeneration: commandRetryGeneration,
      );
      // Failure tracking ignores model narration (`reason`) so a retried denied
      // command counts as one repeating action and trips the abort; success
      // dedup keeps narration so a re-narrated inspection can still re-run.
      final toolFailureKey = _toolCallExecutionPolicy.toolFailureKey(
        toolCall,
        commandRetryGeneration: commandRetryGeneration,
      );
      if (executedToolCallKeys.contains(toolCallKey)) {
        continue;
      }

      final result = await dispatchToolCall(toolCall);
      final toolResultText = result.isSuccess
          ? result.result
          : (result.result.trim().isNotEmpty
                ? result.result
                : 'Error: ${result.errorMessage ?? 'Tool execution failed'}');

      toolResults.add(
        ToolResultInfo(
          id: toolCall.id,
          name: toolCall.name,
          arguments: toolCall.arguments,
          result: toolResultText,
        ),
      );

      if (result.isSuccess) {
        executedToolCallKeys.add(toolCallKey);
        toolFailureCounts.remove(toolFailureKey);
      } else {
        final failureCount = (toolFailureCounts[toolFailureKey] ?? 0) + 1;
        toolFailureCounts[toolFailureKey] = failureCount;
        if (failureCount >= 2) {
          abortLoop = true;
          break;
        }
      }
    }

    return ToolCallBatchExecutionResult(
      toolResults: toolResults,
      abortLoop: abortLoop,
    );
  }
}
