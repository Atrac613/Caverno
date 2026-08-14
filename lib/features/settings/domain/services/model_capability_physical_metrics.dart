import '../entities/app_settings.dart';
import '../entities/live_llm_diagnostic.dart';

/// Stable, unit-bearing LL39 metrics stored with model profiles and revisions.
///
/// The key includes the unit so a consumer cannot silently compare milliseconds
/// with seconds or raw tokens with a point total. Values remain strings because
/// profile metadata is the forward-compatible extension surface.
class ModelCapabilityPhysicalMetrics {
  const ModelCapabilityPhysicalMetrics._();

  static const prefix = 'capability.';
  static const streamingTtftMs = '${prefix}streaming.ttftMs';
  static const streamingElapsedMs = '${prefix}streaming.elapsedMs';
  static const streamingCompletionTokens =
      '${prefix}streaming.completionTokens';
  static const streamingChunkCount = '${prefix}streaming.chunkCount';
  static const streamingLikelyBuffered = '${prefix}streaming.likelyBuffered';
  static const streamingDecodeTokensPerSecond =
      '${prefix}streaming.decodeTokensPerSecond';
  static const toolLoopElapsedMs = '${prefix}toolLoop.elapsedMs';
  static const toolLoopModelTurns = '${prefix}toolLoop.modelTurns';
  static const toolLoopToolCalls = '${prefix}toolLoop.toolCalls';
  static const toolLoopSuccessfulExecutions =
      '${prefix}toolLoop.successfulExecutions';
  static const toolLoopPromptTokens = '${prefix}toolLoop.promptTokens';
  static const toolLoopCompletionTokens = '${prefix}toolLoop.completionTokens';
  static const toolLoopTotalTokens = '${prefix}toolLoop.totalTokens';
  static const toolLoopTaskCompleted = '${prefix}toolLoop.taskCompleted';
  static const embeddingElapsedMs = '${prefix}embedding.elapsedMs';
  static const embeddingModel = '${prefix}embedding.model';
  static const embeddingDimension = '${prefix}embedding.dimension';
  static const embeddingVectorCount = '${prefix}embedding.vectorCount';
  static const embeddingInputCount = '${prefix}embedding.inputCount';
  static const embeddingSimilarCosine = '${prefix}embedding.similarCosine';
  static const embeddingUnrelatedCosine = '${prefix}embedding.unrelatedCosine';
  static const embeddingSemanticMargin = '${prefix}embedding.semanticMargin';
  static const effectiveContextPromptTokens =
      '${prefix}effectiveContext.promptTokens';
  static const effectiveContextConfiguredTokens =
      '${prefix}effectiveContext.configuredTokens';
  static const effectiveContextReachedCeiling =
      '${prefix}effectiveContext.reachedCeiling';

  static Map<String, String> fromReport(LiveLlmDiagnosticReport report) {
    final values = <String, String>{};
    if (report.streamingMetrics case final metrics?) {
      values.addAll({
        streamingTtftMs: '${metrics.timeToFirstToken.inMilliseconds}',
        streamingElapsedMs: '${metrics.totalElapsed.inMilliseconds}',
        streamingCompletionTokens: '${metrics.completionTokens}',
        streamingChunkCount: '${metrics.chunkCount}',
        streamingLikelyBuffered: '${metrics.isLikelyBuffered}',
        if (metrics.decodeTokensPerSecond case final rate?)
          streamingDecodeTokensPerSecond: rate.toStringAsFixed(2),
      });
    }
    if (report.multiRoundToolLoopMetrics case final metrics?) {
      values.addAll({
        toolLoopElapsedMs: '${metrics.totalElapsed.inMilliseconds}',
        toolLoopModelTurns: '${metrics.modelTurnCount}',
        toolLoopToolCalls: '${metrics.toolCallCount}',
        toolLoopSuccessfulExecutions: '${metrics.successfulToolExecutionCount}',
        toolLoopPromptTokens: '${metrics.promptTokens}',
        toolLoopCompletionTokens: '${metrics.completionTokens}',
        toolLoopTotalTokens: '${metrics.totalTokens}',
        toolLoopTaskCompleted: '${metrics.taskCompleted}',
      });
    }
    if (report.embeddingMetrics case final metrics?) {
      values.addAll({
        embeddingElapsedMs: '${metrics.totalElapsed.inMilliseconds}',
        embeddingModel: metrics.model,
        embeddingDimension: '${metrics.dimension}',
        embeddingVectorCount: '${metrics.returnedVectorCount}',
        embeddingInputCount: '${metrics.inputCount}',
        embeddingSimilarCosine: metrics.similarCosine.toStringAsFixed(6),
        embeddingUnrelatedCosine: metrics.unrelatedCosine.toStringAsFixed(6),
        embeddingSemanticMargin: metrics.semanticMargin.toStringAsFixed(6),
      });
    }
    if (report.effectiveContextMetrics case final metrics?) {
      values.addAll({
        effectiveContextPromptTokens: '${metrics.maxSuccessfulPromptTokens}',
        effectiveContextConfiguredTokens: '${metrics.configuredMaximumTokens}',
        effectiveContextReachedCeiling: '${metrics.reachedConfiguredMaximum}',
      });
    }
    return Map.unmodifiable(values);
  }

  static Map<String, String> fromBenchmarkRun(Map<String, dynamic> run) {
    final values = <String, String>{};
    _copyBlock(
      run['streaming'],
      values,
      integers: {
        'timeToFirstTokenMs': streamingTtftMs,
        'totalElapsedMs': streamingElapsedMs,
        'completionTokens': streamingCompletionTokens,
        'chunkCount': streamingChunkCount,
      },
      doubles: {'decodeTokensPerSecond': streamingDecodeTokensPerSecond},
      booleans: {'likelyBuffered': streamingLikelyBuffered},
    );
    if (values[streamingLikelyBuffered] == 'true') {
      values.remove(streamingDecodeTokensPerSecond);
    }
    _copyBlock(
      run['multiRoundToolLoop'],
      values,
      integers: {
        'totalElapsedMs': toolLoopElapsedMs,
        'modelTurnCount': toolLoopModelTurns,
        'toolCallCount': toolLoopToolCalls,
        'successfulToolExecutionCount': toolLoopSuccessfulExecutions,
        'promptTokens': toolLoopPromptTokens,
        'completionTokens': toolLoopCompletionTokens,
        'totalTokens': toolLoopTotalTokens,
      },
      booleans: {'taskCompleted': toolLoopTaskCompleted},
    );
    _copyBlock(
      run['embeddings'],
      values,
      integers: {
        'totalElapsedMs': embeddingElapsedMs,
        'dimension': embeddingDimension,
        'returnedVectorCount': embeddingVectorCount,
        'inputCount': embeddingInputCount,
      },
      doubles: {
        'similarCosine': embeddingSimilarCosine,
        'unrelatedCosine': embeddingUnrelatedCosine,
        'semanticMargin': embeddingSemanticMargin,
      },
      strings: {'model': embeddingModel},
    );
    _copyBlock(
      run['effectiveContext'],
      values,
      integers: {
        'maxSuccessfulPromptTokens': effectiveContextPromptTokens,
        'configuredMaximumTokens': effectiveContextConfiguredTokens,
      },
      booleans: {'reachedConfiguredMaximum': effectiveContextReachedCeiling},
    );
    return Map.unmodifiable(values);
  }

  static Map<String, String> fromProfile(ModelCapabilityProfile profile) =>
      Map.unmodifiable({
        for (final entry in profile.probeMetadata.entries)
          if (entry.key.startsWith(prefix)) entry.key: entry.value,
      });

  static void _copyBlock(
    Object? raw,
    Map<String, String> target, {
    Map<String, String> integers = const {},
    Map<String, String> doubles = const {},
    Map<String, String> booleans = const {},
    Map<String, String> strings = const {},
  }) {
    if (raw == null) return;
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Capability metric block must be an object');
    }
    for (final entry in integers.entries) {
      final value = raw[entry.key];
      if (value == null) continue;
      if (value is! num || !value.isFinite || value < 0 || value % 1 != 0) {
        throw FormatException('${entry.key} must be a non-negative integer');
      }
      target[entry.value] = '${value.toInt()}';
    }
    for (final entry in doubles.entries) {
      final value = raw[entry.key];
      if (value == null) continue;
      if (value is! num || !value.isFinite) {
        throw FormatException('${entry.key} must be a finite number');
      }
      target[entry.value] = '$value';
    }
    for (final entry in booleans.entries) {
      final value = raw[entry.key];
      if (value == null) continue;
      if (value is! bool) {
        throw FormatException('${entry.key} must be a boolean');
      }
      target[entry.value] = '$value';
    }
    for (final entry in strings.entries) {
      final value = raw[entry.key];
      if (value == null) continue;
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('${entry.key} must be a non-empty string');
      }
      target[entry.value] = value.trim();
    }
  }
}
