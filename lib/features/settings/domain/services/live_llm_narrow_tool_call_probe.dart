import '../../../chat/domain/entities/tool_call_info.dart';
import '../entities/live_llm_diagnostic.dart';
import 'live_llm_diagnostic_evidence.dart';

typedef LiveLlmNarrowToolCallReply = ({
  List<ToolCallInfo> calls,
  String content,
  LiveLlmDiagnosticTokenUsage usage,
});

/// Scores datetime tool selection without executing returned calls.
class LiveLlmNarrowToolCallProbe {
  const LiveLlmNarrowToolCallProbe({
    required Future<LiveLlmNarrowToolCallReply> Function() complete,
  }) : _complete = complete;

  static const probeId = 'narrow_tool_call';
  static const prompt =
      'Call the get_current_datetime tool now. Do not answer in text '
      'before using the tool.';
  final Future<LiveLlmNarrowToolCallReply> Function() _complete;

  Future<LiveLlmDiagnosticProbeResult> run() async {
    final result = await _complete();
    final toolCalls = result.calls;
    final names = toolCalls.map((call) => call.name).toList(growable: false);
    if (toolCalls.any((call) => call.name == 'get_current_datetime')) {
      return LiveLlmDiagnosticProbeResult(
        id: probeId,
        status: LiveLlmDiagnosticStatus.passed,
        summary: 'The model emitted the expected built-in tool call.',
        toolCalls: names,
        modelContent: LiveLlmDiagnosticEvidence.preview(result.content),
        usage: result.usage,
      );
    }
    return LiveLlmDiagnosticProbeResult(
      id: probeId,
      status: LiveLlmDiagnosticStatus.failed,
      summary: 'The model did not emit get_current_datetime.',
      details: names.isEmpty
          ? 'No tool calls were returned.'
          : names.join(', '),
      modelContent: LiveLlmDiagnosticEvidence.preview(result.content),
      toolCalls: names,
      usage: result.usage,
    );
  }
}
