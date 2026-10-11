import '../entities/live_llm_diagnostic.dart';
import 'live_llm_diagnostic_evidence.dart';
import 'live_llm_diagnostic_response_scoring.dart';

typedef LiveLlmInstructionEchoReply = ({
  String content,
  LiveLlmDiagnosticTokenUsage usage,
});

/// Scores the instruction-echo JSON contract without changing request policy.
class LiveLlmInstructionEchoProbe {
  const LiveLlmInstructionEchoProbe({
    required Future<LiveLlmInstructionEchoReply> Function() complete,
  }) : _complete = complete;

  static const probeId = 'instruction_echo';
  static const marker = 'CAVERNO_LIVE_DIAGNOSTIC';
  static const prompt =
      'Return exactly this JSON object and no markdown:\n'
      '{"probe":"instruction_echo","status":"ok","marker":"$marker"}';
  final Future<LiveLlmInstructionEchoReply> Function() _complete;

  Future<LiveLlmDiagnosticProbeResult> run() async {
    final result = await _complete();
    final content = result.content.trim();
    final decoded = LiveLlmResponseScoring.tryDecodeJsonObject(content);
    final jsonPassed =
        decoded?['probe'] == 'instruction_echo' &&
        decoded?['status'] == 'ok' &&
        decoded?['marker'] == marker;
    final markerPresent = content.contains(marker);
    if (jsonPassed) {
      return LiveLlmDiagnosticProbeResult(
        id: probeId,
        status: LiveLlmDiagnosticStatus.passed,
        summary: 'The model followed the exact JSON instruction.',
        modelContent: LiveLlmDiagnosticEvidence.preview(content),
        usage: result.usage,
      );
    }
    return LiveLlmDiagnosticProbeResult(
      id: probeId,
      status: markerPresent
          ? LiveLlmDiagnosticStatus.warning
          : LiveLlmDiagnosticStatus.failed,
      summary: markerPresent
          ? 'The marker was present, but the JSON contract was not exact.'
          : 'The expected diagnostic marker was missing.',
      details: 'Expected marker: $marker',
      modelContent: LiveLlmDiagnosticEvidence.preview(content),
      usage: result.usage,
    );
  }
}
