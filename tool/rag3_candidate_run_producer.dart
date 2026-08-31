import 'dart:math' as math;

import 'rag3_offline_hybrid_eval.dart';

final class Rag3VectorFingerprint {
  const Rag3VectorFingerprint({
    required this.schemaVersion,
    required this.endpointIdentity,
    required this.requestedModelId,
    required this.responseModelId,
    required this.dimension,
  });

  final int schemaVersion;
  final String endpointIdentity;
  final String requestedModelId;
  final String responseModelId;
  final int dimension;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'endpointIdentity': endpointIdentity,
    'requestedModelId': requestedModelId,
    'responseModelId': responseModelId,
    'dimension': dimension,
  };

  bool hasSameIdentity(Rag3VectorFingerprint other) =>
      schemaVersion == other.schemaVersion &&
      endpointIdentity == other.endpointIdentity &&
      requestedModelId == other.requestedModelId &&
      responseModelId == other.responseModelId &&
      dimension == other.dimension;

  static String normalizeEndpointIdentity(String raw) {
    return normalizeRag3EndpointIdentity(raw);
  }
}

final class Rag3VectorRankingInput {
  const Rag3VectorRankingInput({
    required this.queryFingerprint,
    required this.corpusFingerprint,
    required this.queryVector,
    required this.corpusVectors,
    required this.unavailableReason,
    required this.latencyMs,
  });

  factory Rag3VectorRankingInput.available({
    required Rag3VectorFingerprint queryFingerprint,
    required Rag3VectorFingerprint corpusFingerprint,
    required List<double> queryVector,
    required Map<String, List<double>> corpusVectors,
    int latencyMs = 0,
  }) => Rag3VectorRankingInput(
    queryFingerprint: queryFingerprint,
    corpusFingerprint: corpusFingerprint,
    queryVector: queryVector,
    corpusVectors: corpusVectors,
    unavailableReason: null,
    latencyMs: latencyMs,
  );

  factory Rag3VectorRankingInput.unavailable({
    required Rag3VectorFingerprint fingerprint,
    required String reason,
    int latencyMs = 0,
  }) => Rag3VectorRankingInput(
    queryFingerprint: fingerprint,
    corpusFingerprint: fingerprint,
    queryVector: null,
    corpusVectors: const {},
    unavailableReason: reason,
    latencyMs: latencyMs,
  );

  final Rag3VectorFingerprint queryFingerprint;
  final Rag3VectorFingerprint corpusFingerprint;
  final List<double>? queryVector;
  final Map<String, List<double>> corpusVectors;
  final String? unavailableReason;
  final int latencyMs;
}

final class Rag3CandidateCaseInput {
  const Rag3CandidateCaseInput({
    required this.caseId,
    required this.submitted,
    required this.lexicalRankedChunkIds,
    required this.vector,
    required this.lexicalLatencyMs,
    required this.peakRssBytes,
    required this.peakVramBytes,
  });

  final String caseId;
  final bool submitted;
  final List<String> lexicalRankedChunkIds;
  final Rag3VectorRankingInput vector;
  final int lexicalLatencyMs;
  final int peakRssBytes;
  final int peakVramBytes;
}

final class Rag3CandidateRunProducer {
  const Rag3CandidateRunProducer();

  Map<String, Object?> produce({
    required Rag3HybridFixture fixture,
    required String runId,
    required Map<String, Object?> metadata,
    required List<Rag3CandidateCaseInput> cases,
  }) {
    final byId = <String, Rag3CandidateCaseInput>{};
    for (final item in cases) {
      if (byId.putIfAbsent(item.caseId, () => item) != item) {
        throw StateError('Duplicate RAG3 producer case: ${item.caseId}');
      }
    }
    if (byId.keys.toSet().difference(fixture.cases.keys.toSet()).isNotEmpty ||
        fixture.cases.keys.toSet().difference(byId.keys.toSet()).isNotEmpty) {
      throw StateError(
        'RAG3 producer requires every fixture case exactly once.',
      );
    }
    final json = <String, Object?>{
      'schemaName': rag3RunSchema,
      'schemaVersion': rag3SchemaVersion,
      'runId': runId,
      'contractId': fixture.contractId,
      'candidateId': rag3CandidateId,
      'fixtureId': fixture.fixtureId,
      'corpusHash': fixture.corpusHash,
      'metadata': Map<String, Object?>.from(metadata),
      'cases': [
        for (final fixtureCase in fixture.cases.values)
          _produceCase(fixture, fixtureCase, byId[fixtureCase.id]!),
      ],
    };
    Rag3CandidateRun.fromJson(json).validate(fixture);
    return json;
  }

  Map<String, Object?> _produceCase(
    Rag3HybridFixture fixture,
    Rag3FixtureCase fixtureCase,
    Rag3CandidateCaseInput input,
  ) {
    if (input.lexicalLatencyMs < 0 ||
        input.vector.latencyMs < 0 ||
        input.peakRssBytes < 0 ||
        input.peakVramBytes < 0) {
      throw StateError('RAG3 measurements cannot be negative.');
    }
    final lexical = _deduplicate(
      input.lexicalRankedChunkIds,
    ).take(rag3MaxInputDepth).toList();
    final vector = _produceVector(input.vector);
    return {
      'caseId': fixtureCase.id,
      'submitted': input.submitted,
      'lexicalRankedChunkIds': input.submitted ? lexical : <String>[],
      'lexicalLatencyMs': input.lexicalLatencyMs,
      'vector': input.submitted
          ? vector
          : {
              ...vector,
              'status': 'not_available',
              'degradedReason': 'not_submitted',
              'rankedChunkIds': <String>[],
            },
      'resource': {
        'peakRssBytes': input.peakRssBytes,
        'peakVramBytes': input.peakVramBytes,
      },
    };
  }

  Map<String, Object?> _produceVector(Rag3VectorRankingInput input) {
    final unavailableReason = input.unavailableReason;
    if (unavailableReason != null) {
      return {
        'status': 'not_available',
        'degradedReason': unavailableReason,
        'rankedChunkIds': <String>[],
        'validationReceipt': {
          'finiteValues': true,
          'nonZeroMagnitude': true,
          'uniformDimensions': true,
          'fingerprintMatch': true,
        },
        'fingerprint': input.queryFingerprint.toJson(),
        'latencyMs': input.latencyMs,
      };
    }

    final query = input.queryVector;
    if (query == null) {
      throw StateError('Available RAG3 vector input requires a query vector.');
    }
    final vectors = [query, ...input.corpusVectors.values];
    final finiteValues = vectors.every(
      (vector) => vector.every((value) => value.isFinite),
    );
    final nonZeroMagnitude = vectors.every(
      (vector) => _magnitudeSquared(vector) > 0,
    );
    final uniformDimensions =
        query.isNotEmpty &&
        query.length == input.queryFingerprint.dimension &&
        input.corpusVectors.isNotEmpty &&
        input.corpusVectors.values.every(
          (vector) => vector.length == query.length,
        );
    final fingerprintMatch = input.queryFingerprint.hasSameIdentity(
      input.corpusFingerprint,
    );
    final receipt = {
      'finiteValues': finiteValues,
      'nonZeroMagnitude': nonZeroMagnitude,
      'uniformDimensions': uniformDimensions,
      'fingerprintMatch': fingerprintMatch,
    };
    String? invalidReason;
    if (!fingerprintMatch) {
      invalidReason = 'fingerprint_mismatch';
    } else if (!finiteValues) {
      invalidReason = 'non_finite_vector';
    } else if (!nonZeroMagnitude) {
      invalidReason = 'zero_magnitude_vector';
    } else if (!uniformDimensions) {
      invalidReason = 'dimension_mismatch';
    }
    if (invalidReason != null) {
      return {
        'status': 'invalid',
        'degradedReason': invalidReason,
        'rankedChunkIds': <String>[],
        'validationReceipt': receipt,
        'fingerprint': input.queryFingerprint.toJson(),
        'latencyMs': input.latencyMs,
      };
    }

    final ranked =
        <({String id, double score})>[
          for (final entry in input.corpusVectors.entries)
            (id: entry.key, score: _cosine(query, entry.value)),
        ]..sort((left, right) {
          final score = right.score.compareTo(left.score);
          return score != 0 ? score : left.id.compareTo(right.id);
        });
    return {
      'status': 'available',
      'degradedReason': null,
      'rankedChunkIds': [
        for (final item in ranked.take(rag3MaxInputDepth)) item.id,
      ],
      'validationReceipt': receipt,
      'fingerprint': input.queryFingerprint.toJson(),
      'latencyMs': input.latencyMs,
    };
  }
}

List<String> _deduplicate(List<String> values) {
  final seen = <String>{};
  return [
    for (final value in values)
      if (seen.add(value)) value,
  ];
}

double _magnitudeSquared(List<double> vector) =>
    vector.fold(0, (sum, value) => sum + value * value);

double _cosine(List<double> left, List<double> right) {
  var dot = 0.0;
  for (var index = 0; index < left.length; index++) {
    dot += left[index] * right[index];
  }
  return dot / math.sqrt(_magnitudeSquared(left) * _magnitudeSquared(right));
}
