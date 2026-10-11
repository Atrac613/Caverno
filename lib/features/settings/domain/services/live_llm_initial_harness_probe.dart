import '../../../chat/domain/services/tool_definition_search_service.dart';
import '../entities/live_llm_diagnostic.dart';
import 'live_llm_diagnostic_evidence.dart';

typedef LiveLlmInitialHarnessReply = ({
  List<String> toolNames,
  String content,
  LiveLlmDiagnosticTokenUsage usage,
});

/// Scores initial catalog selection without executing returned tool calls.
class LiveLlmInitialHarnessProbe {
  const LiveLlmInitialHarnessProbe({
    required Future<LiveLlmInitialHarnessReply> Function() complete,
  }) : _complete = complete;

  static const probeId = 'initial_harness_selection';
  static const prompt =
      'Using the currently exposed Caverno initial tool set, call '
      'get_current_datetime exactly once. Do not call tool_search.';

  final Future<LiveLlmInitialHarnessReply> Function() _complete;

  Future<LiveLlmDiagnosticProbeResult> run({
    required int initialToolCount,
    required bool toolSearchEnabled,
  }) async {
    final result = await _complete();
    final names = result.toolNames;
    if (names.contains('get_current_datetime')) {
      return LiveLlmDiagnosticProbeResult(
        id: probeId,
        status: LiveLlmDiagnosticStatus.passed,
        summary: 'The model selected the datetime tool from the harness set.',
        details:
            'Initial tool count: $initialToolCount. '
            'Tool search enabled: $toolSearchEnabled.',
        toolCalls: names,
        modelContent: LiveLlmDiagnosticEvidence.preview(result.content),
        usage: result.usage,
      );
    }
    return LiveLlmDiagnosticProbeResult(
      id: probeId,
      status: names.contains(ToolDefinitionSearchService.toolName)
          ? LiveLlmDiagnosticStatus.warning
          : LiveLlmDiagnosticStatus.failed,
      summary: names.contains(ToolDefinitionSearchService.toolName)
          ? 'The model used tool_search instead of the directly exposed tool.'
          : 'The model did not select the expected harness tool.',
      details:
          'Initial tool count: $initialToolCount. '
          'Returned calls: ${names.isEmpty ? "(none)" : names.join(", ")}',
      toolCalls: names,
      modelContent: LiveLlmDiagnosticEvidence.preview(result.content),
      usage: result.usage,
    );
  }
}
