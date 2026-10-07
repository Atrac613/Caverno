import 'dart:math' as math;

import 'package:caverno/features/chat/data/datasources/embeddings_client.dart';
import 'package:caverno/features/settings/domain/entities/live_llm_diagnostic.dart';
import 'package:caverno/features/settings/domain/services/live_llm_embedding_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preserves fixed semantic inputs and scores separated vectors', () {
    expect(LiveLlmEmbeddingProbe.inputs, [
      'A cat rests on a warm windowsill.',
      'The kitten is sleeping beside a sunny window.',
      'Database backups completed at midnight.',
    ]);
    expect(
      () => LiveLlmEmbeddingProbe.inputs.add('extra'),
      throwsUnsupportedError,
    );
    final measurement = _evaluate([
      [1, 0],
      [1, 0],
      [0, 1],
    ]);
    final result = measurement.result;
    final metrics = measurement.metrics!;
    expect(result.id, 'embeddings_capability');
    expect(result.status, LiveLlmDiagnosticStatus.passed);
    expect(
      result.summary,
      'The embedding model returned usable, semantically separated vectors.',
    );
    expect(result.passedChecks, 2);
    expect(result.totalChecks, 2);
    expect(result.metadata, {'embeddingModel': 'fixture-model'});
    expect(
      result.details,
      'Model: fixture-model\nVectors: 3 x 2\n'
      'Similar cosine: 1.000000\nUnrelated cosine: 0.000000\n'
      'Semantic margin: 1.000000 (required >= 0.05)',
    );
    expect(result.elapsed, Duration.zero);
    expect(result.usage.totalTokens, 0);
    expect(result.modelContent, isEmpty);
    expect(metrics.totalElapsed, const Duration(milliseconds: 321));
    expect(metrics.model, 'fixture-model');
    expect(metrics.inputCount, 3);
    expect(metrics.returnedVectorCount, 3);
    expect(metrics.dimension, 2);
    expect(metrics.similarCosine, 1);
    expect(metrics.unrelatedCosine, 0);
    expect(metrics.semanticMargin, 1);
  });

  test('warns with physical metrics when semantic order is inverted', () {
    final measurement = _evaluate([
      [1, 0],
      [0, 1],
      [1, 0],
    ]);
    expect(measurement.result.status, LiveLlmDiagnosticStatus.warning);
    expect(
      measurement.result.summary,
      'The vectors were usable but did not separate the paraphrase from the control.',
    );
    expect(measurement.result.passedChecks, 1);
    expect(measurement.result.totalChecks, 2);
    expect(measurement.metrics!.semanticMargin, -1);
    expect(measurement.result.metadata, {'embeddingModel': 'fixture-model'});
  });

  for (final (margin, status) in [
    (0.049, LiveLlmDiagnosticStatus.warning),
    (0.05, LiveLlmDiagnosticStatus.passed),
    (0.051, LiveLlmDiagnosticStatus.passed),
  ]) {
    test('preserves the semantic cutoff at margin $margin', () {
      final measurement = _evaluate([
        [1, 0],
        [margin, math.sqrt(1 - margin * margin)],
        [0, 1],
      ]);
      expect(measurement.metrics!.semanticMargin, closeTo(margin, 1e-12));
      expect(measurement.result.status, status);
    });
  }

  for (final (name, vectors, dimensions)
      in <(String, List<List<double>>, List<int>)>[
        ('no vectors', [], []),
        (
          'too few vectors',
          [
            [1, 0],
          ],
          [2],
        ),
        (
          'too many vectors',
          [
            [1],
            [1],
            [1],
            [1],
          ],
          [1],
        ),
        ('empty vectors', [[], [], []], [0]),
        (
          'unequal widths',
          [
            [1, 0],
            [1],
            [0, 1],
          ],
          [2, 1],
        ),
        (
          'empty middle vector',
          [
            [1],
            [],
            [1],
          ],
          [1, 0],
        ),
        (
          'zero anchor',
          [
            [0, 0],
            [1, 0],
            [0, 1],
          ],
          [2],
        ),
        (
          'zero paraphrase',
          [
            [1, 0],
            [0, 0],
            [0, 1],
          ],
          [2],
        ),
        (
          'zero control',
          [
            [1, 0],
            [1, 0],
            [0, 0],
          ],
          [2],
        ),
        (
          'nan value',
          [
            [double.nan, 1],
            [1, 0],
            [0, 1],
          ],
          [2],
        ),
        (
          'infinite value',
          [
            [1, 0],
            [double.infinity, 1],
            [0, 1],
          ],
          [2],
        ),
        (
          'negative infinite value',
          [
            [1, 0],
            [1, 0],
            [double.negativeInfinity, 1],
          ],
          [2],
        ),
      ]) {
    test('rejects $name without constructing metrics', () {
      final measurement = _evaluate(vectors);
      expect(measurement.result.status, LiveLlmDiagnosticStatus.failed);
      expect(
        measurement.result.summary,
        'The embeddings response contained unusable vectors.',
      );
      expect(
        measurement.result.details,
        'Expected 3 finite, non-zero, equal-width vectors; received '
        '${vectors.length} with dimensions $dimensions.',
      );
      expect(measurement.result.passedChecks, 0);
      expect(measurement.result.totalChecks, 2);
      expect(measurement.metrics, isNull);
      expect(measurement.result.metadata, isEmpty);
    });
  }

  test('does not mutate vector inputs or require positive coordinates', () {
    const vectors = [
      [-1.0, 0.0],
      [-1.0, 0.0],
      [0.0, -1.0],
    ];
    final measurement = _evaluate(vectors);
    expect(measurement.result.status, LiveLlmDiagnosticStatus.passed);
    expect(vectors, [
      [-1, 0],
      [-1, 0],
      [0, -1],
    ]);
  });
}

LiveLlmEmbeddingProbeMeasurement _evaluate(List<List<double>> vectors) =>
    LiveLlmEmbeddingProbe.evaluate(
      EmbeddingsResult(model: 'fixture-model', vectors: vectors),
      const Duration(milliseconds: 321),
    );
