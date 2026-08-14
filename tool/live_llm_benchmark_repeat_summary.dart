import 'package:caverno/features/settings/domain/entities/live_llm_diagnostic.dart';

Map<String, Object> buildLiveLlmProbeRepeatSummaries(
  Iterable<Iterable<LiveLlmDiagnosticProbeResult>> runs,
) {
  final resultsById = <String, List<LiveLlmDiagnosticProbeResult>>{};
  for (final run in runs) {
    for (final result in run) {
      if (result.status == LiveLlmDiagnosticStatus.skipped) {
        continue;
      }
      resultsById.putIfAbsent(result.id, () => []).add(result);
    }
  }

  final ids = resultsById.keys.toList(growable: false)..sort();
  return <String, Object>{
    for (final id in ids) id: _probeDistribution(resultsById[id]!),
  };
}

Map<String, Object> buildLiveLlmStreamingRepeatSummary(
  Iterable<LiveLlmDiagnosticStreamingMetrics?> values,
) {
  final metrics = values.whereType<LiveLlmDiagnosticStreamingMetrics>().toList(
    growable: false,
  );
  if (metrics.isEmpty) {
    return const <String, Object>{};
  }

  return <String, Object>{
    'measuredRunCount': metrics.length,
    'bufferedRunCount': metrics.where((item) => item.isLikelyBuffered).length,
    'timeToFirstTokenMs': _durationRange(
      metrics.map((item) => item.timeToFirstToken),
    ),
    'totalElapsedMs': _durationRange(metrics.map((item) => item.totalElapsed)),
  };
}

Map<String, int> _durationRange(Iterable<Duration> values) {
  final milliseconds =
      values.map((value) => value.inMilliseconds).toList(growable: false)
        ..sort();
  final minimum = milliseconds.first;
  final maximum = milliseconds.last;
  return <String, int>{
    'min': minimum,
    'max': maximum,
    'spread': maximum - minimum,
  };
}

Map<String, Object> _probeDistribution(
  List<LiveLlmDiagnosticProbeResult> results,
) {
  return <String, Object>{
    'measuredRunCount': results.length,
    'passedRunCount': results
        .where((result) => result.status == LiveLlmDiagnosticStatus.passed)
        .length,
    'warningRunCount': results
        .where((result) => result.status == LiveLlmDiagnosticStatus.warning)
        .length,
    'failedRunCount': results
        .where((result) => result.status == LiveLlmDiagnosticStatus.failed)
        .length,
    'elapsedMs': _integerDistribution(
      results.map((result) => result.elapsed.inMilliseconds),
    ),
    'promptTokens': _integerDistribution(
      results.map((result) => result.usage.promptTokens),
    ),
    'completionTokens': _integerDistribution(
      results.map((result) => result.usage.completionTokens),
    ),
  };
}

Map<String, Object> _integerDistribution(Iterable<int> values) {
  final sorted = values.toList(growable: false)..sort();
  final middle = sorted.length ~/ 2;
  final num median = sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
  return <String, Object>{
    'min': sorted.first,
    'median': median,
    'max': sorted.last,
    'spread': sorted.last - sorted.first,
  };
}
