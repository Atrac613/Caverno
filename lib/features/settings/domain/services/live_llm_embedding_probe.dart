import '../../../chat/data/datasources/embeddings_client.dart';
import '../../../chat/data/datasources/embeddings_math.dart';
import '../entities/live_llm_diagnostic.dart';

/// Scored embeddings response. Invalid vectors carry no physical metrics.
class LiveLlmEmbeddingProbeMeasurement {
  const LiveLlmEmbeddingProbeMeasurement({required this.result, this.metrics});

  final LiveLlmDiagnosticProbeResult result;
  final LiveLlmDiagnosticEmbeddingMetrics? metrics;
}

/// Pure structural and semantic scoring. Requests, client lifetime, skips,
/// failure diagnostics, timing and publication stay with the service.
abstract final class LiveLlmEmbeddingProbe {
  static const probeId = 'embeddings_capability';
  static const inputs = <String>[
    'A cat rests on a warm windowsill.',
    'The kitten is sleeping beside a sunny window.',
    'Database backups completed at midnight.',
  ];
  static const _semanticMarginMinimum = 0.05;

  static LiveLlmEmbeddingProbeMeasurement evaluate(
    EmbeddingsResult result,
    Duration elapsed,
  ) {
    final vectors = result.vectors;
    final dimensions = vectors.map((vector) => vector.length).toSet();
    final structurallyValid =
        vectors.length == inputs.length &&
        dimensions.length == 1 &&
        dimensions.first > 0 &&
        vectors.every(
          (vector) =>
              vector.every((value) => value.isFinite) &&
              vector.any((value) => value != 0),
        );
    if (!structurallyValid) {
      return LiveLlmEmbeddingProbeMeasurement(
        result: LiveLlmDiagnosticProbeResult(
          id: probeId,
          status: LiveLlmDiagnosticStatus.failed,
          summary: 'The embeddings response contained unusable vectors.',
          details:
              'Expected ${inputs.length} finite, non-zero, equal-width '
              'vectors; received ${vectors.length} with dimensions '
              '${dimensions.toList()}.',
          passedChecks: 0,
          totalChecks: 2,
        ),
      );
    }

    final similarCosine = EmbeddingsMath.cosineSimilarity(
      vectors[0],
      vectors[1],
    );
    final unrelatedCosine = EmbeddingsMath.cosineSimilarity(
      vectors[0],
      vectors[2],
    );
    final metrics = LiveLlmDiagnosticEmbeddingMetrics(
      totalElapsed: elapsed,
      inputCount: inputs.length,
      returnedVectorCount: vectors.length,
      dimension: vectors.first.length,
      model: result.model,
      similarCosine: similarCosine,
      unrelatedCosine: unrelatedCosine,
    );
    final semanticPass = metrics.semanticMargin >= _semanticMarginMinimum;
    return LiveLlmEmbeddingProbeMeasurement(
      result: LiveLlmDiagnosticProbeResult(
        id: probeId,
        status: semanticPass
            ? LiveLlmDiagnosticStatus.passed
            : LiveLlmDiagnosticStatus.warning,
        summary: semanticPass
            ? 'The embedding model returned usable, semantically separated vectors.'
            : 'The vectors were usable but did not separate the paraphrase from the control.',
        details: [
          'Model: ${result.model}',
          'Vectors: ${vectors.length} x ${vectors.first.length}',
          'Similar cosine: ${similarCosine.toStringAsFixed(6)}',
          'Unrelated cosine: ${unrelatedCosine.toStringAsFixed(6)}',
          'Semantic margin: ${metrics.semanticMargin.toStringAsFixed(6)} '
              '(required >= ${_semanticMarginMinimum.toStringAsFixed(2)})',
        ].join('\n'),
        passedChecks: semanticPass ? 2 : 1,
        totalChecks: 2,
        metadata: {'embeddingModel': result.model},
      ),
      metrics: metrics,
    );
  }
}
