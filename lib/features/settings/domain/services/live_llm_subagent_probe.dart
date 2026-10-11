import '../../../chat/domain/entities/tool_call_info.dart';
import '../entities/live_llm_diagnostic.dart';
import 'live_llm_diagnostic_evidence.dart';

typedef LiveLlmSubagentReply = ({
  List<ToolCallInfo> calls,
  String content,
  LiveLlmDiagnosticTokenUsage usage,
});

/// Inspects the delegation contract without executing returned tool calls.
class LiveLlmSubagentProbe {
  const LiveLlmSubagentProbe({
    required Future<LiveLlmSubagentReply> Function() complete,
  }) : _complete = complete;

  static const probeId = 'subagent_recognition';
  static const marker = 'CAVERNO_SUBAGENT_DIAGNOSTIC';

  // Natural delegation wording avoids measuring the model's response to
  // meta-framing instead of its ability to select the subagent tool.
  static const prompt =
      'Delegate a sub-task to a subagent and run it in the background so '
      'you get a task id immediately: it should summarize the marker '
      '"$marker". Do not answer in text.';

  final Future<LiveLlmSubagentReply> Function() _complete;

  Future<LiveLlmDiagnosticProbeResult> run() async {
    final result = await _complete();
    final calls = result.calls;
    final names = calls.map((call) => call.name).toList(growable: false);
    final spawnCall = calls
        .where((call) => call.name == 'spawn_subagent')
        .firstOrNull;
    if (spawnCall == null) {
      return LiveLlmDiagnosticProbeResult(
        id: probeId,
        status: LiveLlmDiagnosticStatus.failed,
        summary: 'The model did not emit spawn_subagent.',
        toolCalls: names,
        modelContent: LiveLlmDiagnosticEvidence.preview(result.content),
        usage: result.usage,
      );
    }
    final hasPrompt =
        (spawnCall.arguments['prompt'] as String?)?.contains(marker) ?? false;
    final hasDescription =
        (spawnCall.arguments['description'] as String?)?.trim().isNotEmpty ??
        false;
    final background = spawnCall.arguments['background'] == true;
    final passed = hasPrompt && hasDescription && background;
    return LiveLlmDiagnosticProbeResult(
      id: probeId,
      status: passed
          ? LiveLlmDiagnosticStatus.passed
          : LiveLlmDiagnosticStatus.warning,
      summary: passed
          ? 'The model recognized the subagent contract and required fields.'
          : 'The model emitted spawn_subagent, but the arguments were incomplete.',
      details:
          'description=$hasDescription, promptMarker=$hasPrompt, '
          'background=$background',
      toolCalls: names,
      modelContent: LiveLlmDiagnosticEvidence.preview(result.content),
      usage: result.usage,
    );
  }
}
