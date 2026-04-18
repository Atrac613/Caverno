import '../../data/datasources/chat_remote_datasource.dart';
import '../entities/mcp_tool_entity.dart';

class ScheduledToolExecutionResult {
  const ScheduledToolExecutionResult({
    required this.toolCall,
    required this.result,
    required this.error,
  });

  final ToolCallInfo toolCall;
  final McpToolResult? result;
  final Object? error;

  bool get isSuccess => result != null && error == null;
}

class ToolExecutionScheduler {
  ToolExecutionScheduler._();

  static const Set<String> _concurrencySafeToolNames = {
    'list_directory',
    'read_file',
    'find_files',
    'search_files',
    'ping',
    'whois_lookup',
    'dns_lookup',
    'port_check',
    'ssl_certificate',
    'http_status',
    'http_get',
    'http_head',
    'search_past_conversations',
    'recall_memory',
    'get_current_datetime',
    'web_search',
    'web_url_read',
  };

  static bool isConcurrencySafe(ToolCallInfo toolCall) {
    return _concurrencySafeToolNames.contains(toolCall.name);
  }

  static Future<List<ScheduledToolExecutionResult>> executeBatch({
    required List<ToolCallInfo> toolCalls,
    required Future<McpToolResult> Function(ToolCallInfo toolCall) execute,
  }) async {
    if (toolCalls.isEmpty) {
      return const [];
    }

    final orderedResults = List<ScheduledToolExecutionResult?>.filled(
      toolCalls.length,
      null,
    );
    final parallelBatch = <Future<void>>[];

    Future<void> flushParallelBatch() async {
      if (parallelBatch.isEmpty) {
        return;
      }
      await Future.wait(parallelBatch);
      parallelBatch.clear();
    }

    for (var index = 0; index < toolCalls.length; index++) {
      final toolCall = toolCalls[index];
      if (isConcurrencySafe(toolCall)) {
        parallelBatch.add(
          _execute(toolCall, execute).then((value) {
            orderedResults[index] = value;
          }),
        );
        continue;
      }

      await flushParallelBatch();
      orderedResults[index] = await _execute(toolCall, execute);
    }

    await flushParallelBatch();
    return orderedResults.whereType<ScheduledToolExecutionResult>().toList();
  }

  static Future<ScheduledToolExecutionResult> _execute(
    ToolCallInfo toolCall,
    Future<McpToolResult> Function(ToolCallInfo toolCall) execute,
  ) async {
    try {
      final result = await execute(toolCall);
      return ScheduledToolExecutionResult(
        toolCall: toolCall,
        result: result,
        error: null,
      );
    } catch (error) {
      return ScheduledToolExecutionResult(
        toolCall: toolCall,
        result: null,
        error: error,
      );
    }
  }
}
