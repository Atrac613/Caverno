import '../entities/mcp_tool_entity.dart';
import '../entities/tool_call_info.dart';

enum ToolExecutionBatchMode { serial, parallelFileRead, parallelNetworkRead }

enum ToolExecutionLifecycleState { queued, started, completed }

class ToolExecutionBatchTelemetry {
  const ToolExecutionBatchTelemetry({
    required this.mode,
    required this.toolNames,
    this.note,
  });

  final ToolExecutionBatchMode mode;
  final List<String> toolNames;
  final String? note;

  int get batchSize => toolNames.length;
}

class ToolExecutionLifecycleEvent {
  const ToolExecutionLifecycleEvent({
    required this.toolCall,
    required this.state,
    required this.schedulerMode,
    this.resultStatus,
    this.durationMs,
  });

  final ToolCallInfo toolCall;
  final ToolExecutionLifecycleState state;
  final ToolExecutionBatchMode schedulerMode;
  final String? resultStatus;
  final int? durationMs;
}

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

  static const int maxParallelBatchSize = 3;

  static const Set<String> _fileReadToolNames = {
    'list_directory',
    'read_file',
    'find_files',
    'search_files',
    'search_past_conversations',
    'recall_memory',
    'get_current_datetime',
    'web_search',
    'web_url_read',
  };

  static const Set<String> _networkReadToolNames = {
    'ping',
    'whois_lookup',
    'dns_lookup',
    'port_check',
    'ssl_certificate',
    'http_status',
    'http_get',
    'http_head',
  };

  static bool isConcurrencySafe(ToolCallInfo toolCall) {
    return executionModeFor(toolCall) != ToolExecutionBatchMode.serial;
  }

  static ToolExecutionBatchMode executionModeFor(ToolCallInfo toolCall) {
    if (_fileReadToolNames.contains(toolCall.name)) {
      return ToolExecutionBatchMode.parallelFileRead;
    }
    if (_networkReadToolNames.contains(toolCall.name)) {
      return ToolExecutionBatchMode.parallelNetworkRead;
    }
    return ToolExecutionBatchMode.serial;
  }

  static Future<List<ScheduledToolExecutionResult>> executeBatch({
    required List<ToolCallInfo> toolCalls,
    required Future<McpToolResult> Function(ToolCallInfo toolCall) execute,
    void Function(ToolExecutionBatchTelemetry telemetry)? onBatch,
    void Function(ToolExecutionLifecycleEvent event)? onLifecycle,
  }) async {
    if (toolCalls.isEmpty) {
      return const [];
    }

    final orderedResults = List<ScheduledToolExecutionResult?>.filled(
      toolCalls.length,
      null,
    );
    final parallelBatch = <Future<void>>[];
    final parallelBatchNames = <String>[];
    ToolExecutionBatchMode? parallelBatchMode;

    Future<void> flushParallelBatch({String? note}) async {
      if (parallelBatch.isEmpty) {
        return;
      }
      await Future.wait(parallelBatch);
      onBatch?.call(
        ToolExecutionBatchTelemetry(
          mode: parallelBatchMode ?? ToolExecutionBatchMode.parallelFileRead,
          toolNames: List<String>.from(parallelBatchNames),
          note: note,
        ),
      );
      parallelBatch.clear();
      parallelBatchNames.clear();
      parallelBatchMode = null;
    }

    for (var index = 0; index < toolCalls.length; index++) {
      final toolCall = toolCalls[index];
      final executionMode = executionModeFor(toolCall);
      if (executionMode != ToolExecutionBatchMode.serial) {
        if (parallelBatchMode != null && parallelBatchMode != executionMode) {
          await flushParallelBatch(note: 'group switch');
        }
        if (parallelBatch.length >= maxParallelBatchSize) {
          await flushParallelBatch(note: 'parallel batch limit');
        }
        parallelBatchMode ??= executionMode;
        parallelBatchNames.add(toolCall.name);
        onLifecycle?.call(
          ToolExecutionLifecycleEvent(
            toolCall: toolCall,
            state: ToolExecutionLifecycleState.queued,
            schedulerMode: executionMode,
          ),
        );
        parallelBatch.add(
          _execute(
            toolCall,
            execute,
            executionMode: executionMode,
            onLifecycle: onLifecycle,
          ).then((value) {
            orderedResults[index] = value;
          }),
        );
        continue;
      }

      await flushParallelBatch(note: 'serial fallback');
      onLifecycle?.call(
        ToolExecutionLifecycleEvent(
          toolCall: toolCall,
          state: ToolExecutionLifecycleState.queued,
          schedulerMode: executionMode,
        ),
      );
      orderedResults[index] = await _execute(
        toolCall,
        execute,
        executionMode: executionMode,
        onLifecycle: onLifecycle,
      );
      onBatch?.call(
        ToolExecutionBatchTelemetry(
          mode: ToolExecutionBatchMode.serial,
          toolNames: [toolCall.name],
          note: 'non-concurrency-safe tool',
        ),
      );
    }

    await flushParallelBatch();
    return orderedResults.whereType<ScheduledToolExecutionResult>().toList();
  }

  static Future<ScheduledToolExecutionResult> _execute(
    ToolCallInfo toolCall,
    Future<McpToolResult> Function(ToolCallInfo toolCall) execute, {
    required ToolExecutionBatchMode executionMode,
    void Function(ToolExecutionLifecycleEvent event)? onLifecycle,
  }) async {
    final stopwatch = Stopwatch()..start();
    onLifecycle?.call(
      ToolExecutionLifecycleEvent(
        toolCall: toolCall,
        state: ToolExecutionLifecycleState.started,
        schedulerMode: executionMode,
      ),
    );
    try {
      final result = await execute(toolCall);
      stopwatch.stop();
      onLifecycle?.call(
        ToolExecutionLifecycleEvent(
          toolCall: toolCall,
          state: ToolExecutionLifecycleState.completed,
          schedulerMode: executionMode,
          resultStatus: result.isSuccess ? 'success' : 'tool_failure',
          durationMs: stopwatch.elapsedMilliseconds,
        ),
      );
      return ScheduledToolExecutionResult(
        toolCall: toolCall,
        result: result,
        error: null,
      );
    } catch (error) {
      stopwatch.stop();
      onLifecycle?.call(
        ToolExecutionLifecycleEvent(
          toolCall: toolCall,
          state: ToolExecutionLifecycleState.completed,
          schedulerMode: executionMode,
          resultStatus: 'exception',
          durationMs: stopwatch.elapsedMilliseconds,
        ),
      );
      return ScheduledToolExecutionResult(
        toolCall: toolCall,
        result: null,
        error: error,
      );
    }
  }
}
