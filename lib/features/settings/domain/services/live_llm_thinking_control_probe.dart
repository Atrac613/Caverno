import '../../../chat/data/datasources/chat_datasource.dart';
import '../entities/live_llm_diagnostic.dart';
import 'live_llm_diagnostic_evidence.dart';
import 'live_llm_diagnostic_thinking_observer.dart';

typedef ThinkingControlProbeCompletion =
    Future<ChatCompletionResult> Function(LiveLlmDiagnosticThinkingMode mode);

/// Classifies mode-switch responses without observing the run's fixed mode.
/// Eligibility, request settings, errors and publication stay in the service.
class LiveLlmThinkingControlProbe {
  const LiveLlmThinkingControlProbe({
    required ThinkingControlProbeCompletion complete,
  }) : _complete = complete;

  static const probeId = 'thinking_control';
  static const metadataKey = 'thinkingControl';
  static const _thinkingControlled = 'controllable';
  static const _thinkingAlwaysOn = 'always_on';
  static const _thinkingNeverObserved = 'never_reasoned';
  static const _thinkingInverted = 'inverted';
  static const prompt =
      'Reply with exactly CAVERNO_THINKING_CONTROL and no other text.';

  final ThinkingControlProbeCompletion _complete;

  Future<LiveLlmDiagnosticProbeResult> run() async {
    final on = await _complete(LiveLlmDiagnosticThinkingMode.on);
    final off = await _complete(LiveLlmDiagnosticThinkingMode.off);
    final onChars = LiveLlmDiagnosticThinkingObserver.reasoningChars(
      on.content,
    );
    final offChars = LiveLlmDiagnosticThinkingObserver.reasoningChars(
      off.content,
    );
    final (classification, status, summary) = switch ((
      onChars > 0,
      offChars > 0,
    )) {
      (true, false) => (
        _thinkingControlled,
        LiveLlmDiagnosticStatus.passed,
        'The endpoint honours enable_thinking in both directions.',
      ),
      (true, true) => (
        _thinkingAlwaysOn,
        LiveLlmDiagnosticStatus.warning,
        'The model reasoned with thinking switched off; something on the way '
            'ignores enable_thinking: false.',
      ),
      (false, false) => (
        _thinkingNeverObserved,
        LiveLlmDiagnosticStatus.warning,
        'No reasoning came back with thinking switched on. A router or server '
            'default may force thinking off, or the model does not reason.',
      ),
      (false, true) => (
        _thinkingInverted,
        LiveLlmDiagnosticStatus.warning,
        'Reasoning came back only with thinking switched off, the reverse of '
            'the request.',
      ),
    };
    return LiveLlmDiagnosticProbeResult(
      id: probeId,
      status: status,
      summary: summary,
      details:
          'Classification: $classification\n'
          'Thinking on: $onChars reasoning chars '
          '(finish_reason: ${on.finishReason})\n'
          'Thinking off: $offChars reasoning chars '
          '(finish_reason: ${off.finishReason})',
      usage: LiveLlmDiagnosticEvidence.totalUsage([on, off]),
      metadata: {metadataKey: classification},
    );
  }
}
