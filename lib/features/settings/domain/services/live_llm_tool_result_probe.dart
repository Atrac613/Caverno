import '../../../chat/data/datasources/chat_datasource.dart';
import '../../../chat/domain/entities/mcp_tool_entity.dart';
import '../../../chat/domain/entities/message.dart';
import '../../../chat/domain/entities/tool_call_info.dart';
import '../entities/live_llm_diagnostic.dart';
import 'live_llm_diagnostic_evidence.dart';
import 'live_llm_diagnostic_response_scoring.dart';

typedef ToolResultProbeCompletion =
    Future<ChatCompletionResult> Function({
      required List<Message> messages,
      required List<Map<String, dynamic>> tools,
    });
typedef ToolResultProbeFollowUp =
    Future<ChatCompletionResult> Function({
      required List<Message> messages,
      required List<ToolResultInfo> toolResults,
      required List<Map<String, dynamic>> tools,
    });
typedef ToolResultProbeExecution =
    Future<McpToolResult> Function({
      required String name,
      required Map<String, dynamic> arguments,
    });

/// Measures final-answer integration using only the built-in datetime tool.
/// Catalog gating, request settings and report publication stay in the service.
class LiveLlmToolResultProbe {
  const LiveLlmToolResultProbe({
    required ToolResultProbeCompletion complete,
    required ToolResultProbeFollowUp followUp,
    required List<Message> Function(String user) messages,
  }) : _complete = complete,
       _followUp = followUp,
       _messages = messages;

  static const probeId = 'tool_result_integration';
  static const _toolResultMarker = 'CAVERNO_TOOL_RESULT_OK';
  final ToolResultProbeCompletion _complete;
  final ToolResultProbeFollowUp _followUp;
  final List<Message> Function(String user) _messages;

  Future<LiveLlmDiagnosticProbeResult> run({
    required Map<String, dynamic> dateTool,
    required ToolResultProbeExecution execute,
  }) async {
    final messages = _messages(
      'Call get_current_datetime. After the tool result arrives, return '
      'JSON with probe="datetime_tool_result", marker="$_toolResultMarker", '
      'today copied from relative_dates.today, and timezone copied from the '
      'tool result.',
    );
    final firstResult = await _complete(messages: messages, tools: [dateTool]);
    final firstToolCalls = LiveLlmResponseScoring.toolCallsFrom(firstResult);
    final call = firstToolCalls
        .where((item) => item.name == 'get_current_datetime')
        .firstOrNull;
    if (call == null) {
      return LiveLlmDiagnosticProbeResult(
        id: probeId,
        status: LiveLlmDiagnosticStatus.failed,
        summary: 'The model did not request the datetime tool.',
        toolCalls: firstToolCalls
            .map((item) => item.name)
            .toList(growable: false),
        modelContent: LiveLlmDiagnosticEvidence.preview(firstResult.content),
        usage: LiveLlmDiagnosticEvidence.usage(firstResult),
      );
    }

    final toolExecution = await execute(
      name: call.name,
      arguments: call.arguments,
    );
    if (!toolExecution.isSuccess) {
      return LiveLlmDiagnosticProbeResult(
        id: probeId,
        status: LiveLlmDiagnosticStatus.failed,
        summary: 'The built-in datetime tool failed.',
        details: toolExecution.errorMessage ?? toolExecution.result,
        toolCalls: [call.name],
        usage: LiveLlmDiagnosticEvidence.usage(firstResult),
      );
    }

    final expected = LiveLlmResponseScoring.tryDecodeJsonObject(
      toolExecution.result,
    );
    final relativeDates = expected?['relative_dates'];
    final today = relativeDates is Map
        ? relativeDates['today'] as String?
        : null;
    final timezone = expected?['timezone'] as String?;
    final followUp = await _followUp(
      messages: messages,
      toolResults: [
        ToolResultInfo(
          id: call.id.isEmpty ? 'diagnostic-datetime-call' : call.id,
          name: call.name,
          arguments: call.arguments,
          result: toolExecution.result,
        ),
      ],
      // This probe measures whether the model uses the returned value in its
      // answer. The multi-round probe separately measures further tool calls.
      tools: const <Map<String, dynamic>>[],
    );
    final content = followUp.content.trim();
    final followUpCalls = LiveLlmResponseScoring.toolCallsFrom(followUp);
    final decoded = LiveLlmResponseScoring.tryDecodeJsonObject(content);
    final markerOk =
        decoded?['marker'] == _toolResultMarker ||
        content.contains(_toolResultMarker);
    final todayOk = today == null || content.contains(today);
    final timezoneOk = timezone == null || content.contains(timezone);
    final passed = followUpCalls.isEmpty && markerOk && todayOk && timezoneOk;
    final unexpectedCalls = followUpCalls.map((call) => call.name).toList();
    return LiveLlmDiagnosticProbeResult(
      id: probeId,
      status: passed
          ? LiveLlmDiagnosticStatus.passed
          : LiveLlmDiagnosticStatus.warning,
      summary: passed
          ? 'The model integrated the tool result into its final answer.'
          : unexpectedCalls.isNotEmpty
          ? 'The model requested another tool instead of completing the answer.'
          : content.isEmpty
          ? 'The model returned no final answer after the tool result.'
          : 'The model did not clearly copy all tool-result fields.',
      details: [
        if (today != null) 'Expected today: $today',
        if (timezone != null) 'Expected timezone: $timezone',
        if (unexpectedCalls.isNotEmpty)
          'Unexpected follow-up tool calls: ${unexpectedCalls.join(", ")}',
        if (content.isEmpty) 'Finish reason: ${followUp.finishReason}',
      ].join('\n'),
      modelContent: LiveLlmDiagnosticEvidence.preview(content),
      toolCalls: [call.name, ...unexpectedCalls],
      usage: LiveLlmDiagnosticEvidence.usage(followUp),
    );
  }
}
