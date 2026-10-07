import '../../../chat/data/datasources/chat_datasource.dart';
import '../entities/live_llm_diagnostic.dart';
import 'live_llm_diagnostic_evidence.dart';
import 'live_llm_diagnostic_response_scoring.dart';

/// Streaming response measurement, published by the diagnostic service.
class LiveLlmStreamingProbeMeasurement {
  const LiveLlmStreamingProbeMeasurement({
    required this.result,
    required this.metrics,
  });

  final LiveLlmDiagnosticProbeResult result;
  final LiveLlmDiagnosticStreamingMetrics metrics;
}

/// Measures content delivery and sequence fidelity. Selection, request settings,
/// error-to-report handling and publication stay with the service.
class LiveLlmStreamingProbe {
  const LiveLlmStreamingProbe({
    required StreamedChatCompletion Function() stream,
    required void Function(String content) recordThinking,
    Stopwatch Function() stopwatch = Stopwatch.new,
  }) : _stream = stream,
       _recordThinking = recordThinking,
       _stopwatch = stopwatch;

  static const probeId = 'streaming_response';
  static const sequenceLength = 40;

  /// Ask for the verifiable task rather than describing the streaming mechanism.
  static const prompt =
      'List every integer from 1 to 40 in order, one per line, with nothing '
      'else on any line.';

  final StreamedChatCompletion Function() _stream;
  final void Function(String content) _recordThinking;
  final Stopwatch Function() _stopwatch;

  Future<LiveLlmStreamingProbeMeasurement> run() async {
    final buffer = StringBuffer();
    var chunkCount = 0;
    Duration? timeToFirstToken;
    final stopwatch = _stopwatch()..start();

    final streamed = _stream();

    await for (final chunk in streamed.stream) {
      if (chunk.isEmpty) {
        continue;
      }
      // First *content*, not first event: an endpoint that opens the stream
      // with empty keep-alive frames would otherwise report a flattering TTFT.
      timeToFirstToken ??= stopwatch.elapsed;
      chunkCount += 1;
      buffer.write(chunk);
    }
    final totalElapsed = stopwatch.elapsed;
    final terminal = await streamed.terminal;

    final content = buffer.toString();
    _recordThinking(content);
    final visibleContent = LiveLlmResponseScoring.visibleContent(content);
    final matched = LiveLlmResponseScoring.matchedIntegerSequence(
      visibleContent,
      length: sequenceLength,
    );
    final metrics = LiveLlmDiagnosticStreamingMetrics(
      timeToFirstToken: timeToFirstToken ?? totalElapsed,
      totalElapsed: totalElapsed,
      completionTokens: terminal.usage.completionTokens,
      chunkCount: chunkCount,
      finishReason: terminal.finishReason ?? '',
    );

    final truncated = terminal.finishReason == 'length';
    final passed = matched == sequenceLength && !truncated;
    final status = passed
        ? LiveLlmDiagnosticStatus.passed
        : matched > 0
        ? LiveLlmDiagnosticStatus.warning
        : LiveLlmDiagnosticStatus.failed;
    final rate = metrics.decodeTokensPerSecond;

    return LiveLlmStreamingProbeMeasurement(
      metrics: metrics,
      result: LiveLlmDiagnosticProbeResult(
        id: probeId,
        status: status,
        summary: passed
            ? 'The model streamed the full sequence over the streaming path.'
            : truncated
            ? 'The stream was cut short by the token limit.'
            : 'The streamed sequence was incomplete or out of order.',
        details: [
          'Matched in order: $matched/$sequenceLength',
          'Chunks: $chunkCount',
          'Finish reason: ${terminal.finishReason ?? "(none)"}',
          'TTFT: ${metrics.timeToFirstToken.inMilliseconds} ms',
          'Total: ${metrics.totalElapsed.inMilliseconds} ms',
          if (rate != null) 'Decode: ${rate.toStringAsFixed(1)} tok/s',
          if (metrics.isLikelyBuffered)
            'Buffered delivery: the answer arrived in one chunk or a short '
                'terminal burst, so decode rate is unavailable.',
        ].join('\n'),
        modelContent: LiveLlmDiagnosticEvidence.preview(content, maxChars: 400),
        usage: LiveLlmDiagnosticTokenUsage(
          promptTokens: terminal.usage.promptTokens,
          completionTokens: terminal.usage.completionTokens,
          totalTokens: terminal.usage.totalTokens,
        ),
        passedChecks: matched,
        totalChecks: sequenceLength,
      ),
    );
  }
}
