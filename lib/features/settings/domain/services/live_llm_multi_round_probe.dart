import '../../../chat/data/datasources/chat_datasource.dart';
import '../../../chat/domain/entities/mcp_tool_entity.dart';
import '../../../chat/domain/entities/message.dart';
import '../../../chat/domain/entities/tool_call_info.dart';
import '../../../chat/domain/services/tool_definition_search_service.dart';
import '../entities/live_llm_diagnostic.dart';
import 'live_llm_diagnostic_evidence.dart';
import 'live_llm_diagnostic_response_scoring.dart';

/// Sends the discovery turn using only the search tool.
typedef MultiRoundProbeCompletion =
    Future<ChatCompletionResult> Function({
      required List<Message> messages,
      required List<Map<String, dynamic>> tools,
    });

/// Sends the datetime and final turns with the preceding tool observations.
typedef MultiRoundProbeFollowUp =
    Future<ChatCompletionResult> Function({
      required List<Message> messages,
      required List<ToolResultInfo> toolResults,
      required List<Map<String, dynamic>> tools,
    });

typedef MultiRoundProbeExecution =
    Future<McpToolResult> Function({
      required String name,
      required Map<String, dynamic> arguments,
    });

/// Sequential local-tool measurement. The service owns selection, catalog
/// lookup, request settings, thinking observation, errors and report publication.
class LiveLlmMultiRoundProbe {
  const LiveLlmMultiRoundProbe({
    required MultiRoundProbeCompletion complete,
    required MultiRoundProbeFollowUp completeWithToolResults,
    required List<Message> Function(String user) messages,
  }) : _complete = complete,
       _completeWithToolResults = completeWithToolResults,
       _messages = messages;

  static const probeId = 'multi_round_tool_loop';
  static const _marker = 'CAVERNO_MULTI_ROUND_LOOP_OK';

  final MultiRoundProbeCompletion _complete;
  final MultiRoundProbeFollowUp _completeWithToolResults;
  final List<Message> Function(String user) _messages;

  Future<LiveLlmMultiRoundProbeMeasurement> run({
    required Map<String, dynamic>? searchTool,
    required Map<String, dynamic>? dateTool,
    required MultiRoundProbeExecution? execute,
  }) async {
    final stopwatch = Stopwatch()..start();
    final modelResults = <ChatCompletionResult>[];
    final observedToolNames = <String>[];
    var toolCallCount = 0;
    var successfulToolExecutionCount = 0;

    LiveLlmMultiRoundProbeMeasurement finish({
      required LiveLlmDiagnosticStatus status,
      required String summary,
      String details = '',
      String modelContent = '',
      int passedChecks = 0,
      int totalChecks = 3,
    }) {
      stopwatch.stop();
      final usage = LiveLlmDiagnosticEvidence.totalUsage(modelResults);
      return LiveLlmMultiRoundProbeMeasurement(
        result: LiveLlmDiagnosticProbeResult(
          id: probeId,
          status: status,
          summary: summary,
          details: details,
          modelContent: LiveLlmDiagnosticEvidence.preview(modelContent),
          toolCalls: List.unmodifiable(observedToolNames),
          usage: usage,
          passedChecks: passedChecks,
          totalChecks: totalChecks,
        ),
        metrics: LiveLlmDiagnosticMultiRoundToolLoopMetrics(
          totalElapsed: stopwatch.elapsed,
          modelTurnCount: modelResults.length,
          toolCallCount: toolCallCount,
          successfulToolExecutionCount: successfulToolExecutionCount,
          promptTokens: usage.promptTokens,
          completionTokens: usage.completionTokens,
          taskCompleted: status == LiveLlmDiagnosticStatus.passed,
        ),
      );
    }

    if (execute == null || searchTool == null || dateTool == null) {
      return finish(
        status: LiveLlmDiagnosticStatus.skipped,
        summary: 'The sequential local tools are not available.',
      );
    }

    final messages = _messages(
      'Find the available tool that reports the current date and timezone, '
      'use it, then return JSON with marker="$_marker", '
      'today copied from relative_dates.today, and timezone copied from '
      'the datetime result.',
    );
    final searchRequest = await _complete(
      messages: messages,
      // The datetime tool is intentionally absent, so the model has to
      // discover it before it can call it.
      tools: [searchTool],
    );
    modelResults.add(searchRequest);
    final searchCalls = LiveLlmResponseScoring.toolCallsFrom(searchRequest);
    toolCallCount += searchCalls.length;
    observedToolNames.addAll(searchCalls.map((call) => call.name));
    // Judged by name, not by count. `tool_search` is the only tool attached
    // here, so a second call is a second search -- the discovery this probe
    // exists to measure, issued in parallel. Counting instead cost
    // qwen/qwen3.8-flash all 65 points on 2026-09-18, and took the run's
    // verdict to Failed, for searching twice before answering.
    if (searchCalls.isEmpty ||
        searchCalls.any(
          (call) => call.name != ToolDefinitionSearchService.toolName,
        )) {
      return finish(
        status: LiveLlmDiagnosticStatus.failed,
        summary: 'The first turn did not call tool_search.',
        details: 'Returned calls: ${observedToolNames.join(", ")}',
        modelContent: searchRequest.content,
      );
    }

    // Every search runs: parallel queries differ, and it is their union that
    // decides whether the datetime tool was discovered.
    final searchResults = <ToolResultInfo>[];
    for (final searchCall in searchCalls) {
      final searchExecution = await execute(
        name: searchCall.name,
        arguments: searchCall.arguments,
      );
      if (!searchExecution.isSuccess) {
        return finish(
          status: LiveLlmDiagnosticStatus.failed,
          summary: 'The local tool catalog search failed.',
          details: searchExecution.errorMessage ?? searchExecution.result,
        );
      }
      successfulToolExecutionCount += 1;
      searchResults.add(
        ToolResultInfo(
          id: searchCall.id.isEmpty
              ? 'diagnostic-tool-search-call-${searchResults.length}'
              : searchCall.id,
          name: searchCall.name,
          arguments: searchCall.arguments,
          result: searchExecution.result,
        ),
      );
    }
    final discovered =
        ToolDefinitionSearchService.discoveredToolNamesFromResults(
          searchResults,
        );
    if (!discovered.contains('get_current_datetime')) {
      return finish(
        status: LiveLlmDiagnosticStatus.failed,
        summary: 'Tool search did not discover get_current_datetime.',
        details: LiveLlmDiagnosticEvidence.preview(
          searchResults.map((result) => result.result).join('\n'),
          maxChars: 1200,
        ),
        passedChecks: 1,
      );
    }

    final dateRequest = await _completeWithToolResults(
      messages: messages,
      toolResults: searchResults,
      tools: [searchTool, dateTool],
    );
    modelResults.add(dateRequest);
    final dateCalls = LiveLlmResponseScoring.toolCallsFrom(dateRequest);
    toolCallCount += dateCalls.length;
    observedToolNames.addAll(dateCalls.map((call) => call.name));
    // Same rule as the first turn. Both tools are attached by now, so a call
    // to anything but the datetime tool still fails -- re-searching here means
    // the model dropped the catalog it was just handed.
    if (dateCalls.isEmpty ||
        dateCalls.any((call) => call.name != 'get_current_datetime')) {
      return finish(
        status: LiveLlmDiagnosticStatus.failed,
        summary: 'The second turn did not call get_current_datetime.',
        details:
            'Returned calls: ${dateCalls.map((call) => call.name).join(", ")}',
        modelContent: dateRequest.content,
        passedChecks: 1,
      );
    }

    // One reading is the whole answer, so repeats need no second execution.
    final dateCall = dateCalls.first;
    final dateExecution = await execute(
      name: dateCall.name,
      arguments: dateCall.arguments,
    );
    if (!dateExecution.isSuccess) {
      return finish(
        status: LiveLlmDiagnosticStatus.failed,
        summary: 'The local datetime tool failed.',
        details: dateExecution.errorMessage ?? dateExecution.result,
        passedChecks: 1,
      );
    }
    successfulToolExecutionCount += 1;
    final dateResult = ToolResultInfo(
      id: dateCall.id.isEmpty ? 'diagnostic-datetime-call' : dateCall.id,
      name: dateCall.name,
      arguments: dateCall.arguments,
      result: dateExecution.result,
    );

    final finalRequest = await _completeWithToolResults(
      messages: messages,
      toolResults: [dateResult],
      tools: const <Map<String, dynamic>>[],
    );
    modelResults.add(finalRequest);
    final finalCalls = LiveLlmResponseScoring.toolCallsFrom(finalRequest);
    toolCallCount += finalCalls.length;
    observedToolNames.addAll(finalCalls.map((call) => call.name));

    final expected = LiveLlmResponseScoring.tryDecodeJsonObject(
      dateExecution.result,
    );
    final relativeDates = expected?['relative_dates'];
    final today = relativeDates is Map
        ? relativeDates['today'] as String?
        : null;
    final timezone = expected?['timezone'] as String?;
    final content = finalRequest.content.trim();
    final decoded = LiveLlmResponseScoring.tryDecodeJsonObject(content);
    final markerOk = decoded?['marker'] == _marker;
    final todayOk = today != null && decoded?['today'] == today;
    final timezoneOk = timezone != null && decoded?['timezone'] == timezone;
    final noExtraCalls = finalCalls.isEmpty;
    final passed = markerOk && todayOk && timezoneOk && noExtraCalls;
    return finish(
      status: passed
          ? LiveLlmDiagnosticStatus.passed
          : LiveLlmDiagnosticStatus.warning,
      summary: passed
          ? 'The model completed two sequential tool rounds and the final answer.'
          : 'The loop reached a final answer but did not preserve its contract.',
      details: [
        'Search discovered datetime: true',
        'Marker copied: $markerOk',
        'Today copied: $todayOk',
        'Timezone copied: $timezoneOk',
        'No extra final calls: $noExtraCalls',
      ].join('\n'),
      modelContent: content,
      passedChecks:
          2 +
          [
            markerOk,
            todayOk,
            timezoneOk,
            noExtraCalls,
          ].where((ok) => ok).length,
      totalChecks: 6,
    );
  }
}

class LiveLlmMultiRoundProbeMeasurement {
  const LiveLlmMultiRoundProbeMeasurement({
    required this.result,
    required this.metrics,
  });

  final LiveLlmDiagnosticProbeResult result;
  final LiveLlmDiagnosticMultiRoundToolLoopMetrics metrics;
}
