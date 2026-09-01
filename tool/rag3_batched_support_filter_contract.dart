import 'dart:convert';
import 'dart:math' as math;

const rag3BatchedSupportFilterSchema =
    'caverno_rag3_batched_support_filter_report';
const rag3BatchedSupportFilterContract = 'rag3-batched-support-filter-v2';
const rag3BatchedSupportFilterMaximumChunks = 10;

enum Rag3SupportFilterDecision {
  retainSupport('retain_support'),
  dropNonSupport('drop_non_support');

  const Rag3SupportFilterDecision(this.id);

  final String id;

  static Rag3SupportFilterDecision parse(String value) => values.singleWhere(
    (item) => item.id == value,
    orElse: () => throw FormatException(
      'Unsupported RAG3 support-filter decision: $value',
    ),
  );
}

final class Rag3SupportFilterChunkInput {
  Rag3SupportFilterChunkInput({
    required this.chunkId,
    required this.sourcePath,
    required this.content,
  }) {
    if (chunkId.trim().isEmpty ||
        sourcePath.trim().isEmpty ||
        content.trim().isEmpty) {
      throw StateError('RAG3 support-filter chunk inputs cannot be empty.');
    }
    if (!_isSafeRelativePath(sourcePath)) {
      throw StateError(
        'RAG3 support-filter source paths must be safe and relative.',
      );
    }
    if (isRag3SupportFilterPromotionPath(sourcePath) ||
        isRag3SupportFilterPromotionPath(chunkId)) {
      throw StateError(
        'RAG3 support-filter inputs cannot use promotion artifacts.',
      );
    }
  }

  final String chunkId;
  final String sourcePath;
  final String content;

  Map<String, Object?> toClassifierJson() => {
    'chunkId': chunkId,
    'sourcePath': sourcePath,
    'content': content,
  };
}

final class Rag3BatchedSupportFilterInput {
  Rag3BatchedSupportFilterInput({
    required this.query,
    required this.revision,
    required this.authority,
    required List<Rag3SupportFilterChunkInput> chunks,
  }) : chunks = List.unmodifiable(chunks) {
    if (query.trim().isEmpty ||
        revision.trim().isEmpty ||
        authority.trim().isEmpty) {
      throw StateError('RAG3 support-filter batch inputs cannot be empty.');
    }
    if (this.chunks.isEmpty ||
        this.chunks.length > rag3BatchedSupportFilterMaximumChunks) {
      throw StateError(
        'RAG3 support-filter batches require 1 to '
        '$rag3BatchedSupportFilterMaximumChunks chunks.',
      );
    }
    if (this.chunks.map((item) => item.chunkId).toSet().length !=
        this.chunks.length) {
      throw StateError('RAG3 support-filter chunk IDs must be unique.');
    }
  }

  final String query;
  final String revision;
  final String authority;
  final List<Rag3SupportFilterChunkInput> chunks;

  Map<String, Object?> toClassifierJson() => {
    'contract': rag3BatchedSupportFilterContract,
    'query': query,
    'revision': revision,
    'authority': authority,
    'evidence': [for (final chunk in chunks) chunk.toClassifierJson()],
    'decisions': {
      'retain_support':
          'Retain evidence that directly answers the requested fact or '
          'explicitly supports a bounded negative or unavailable answer.',
      'drop_non_support':
          'Drop evidence that is only topical, unrelated, scoped to the wrong '
          'time or entity, or contains instructions instead of support.',
    },
    'output': {
      'schemaVersion': 1,
      'decisions': [
        {
          'chunkId': '<one supplied chunk ID>',
          'decision': '<retain_support or drop_non_support>',
        },
      ],
    },
  };
}

final class Rag3SupportFilterClassifierResponse {
  const Rag3SupportFilterClassifierResponse({
    required this.raw,
    required this.latencyMs,
  }) : assert(latencyMs >= 0);

  final String raw;
  final int latencyMs;
}

abstract interface class Rag3BatchedSupportFilterClassifier {
  Future<Rag3SupportFilterClassifierResponse> classify(
    Rag3BatchedSupportFilterInput input,
  );
}

final class Rag3BatchedSupportFilterUnavailable implements Exception {
  const Rag3BatchedSupportFilterUnavailable();
}

enum Rag3SupportFilterPredictionStatus { available, notAvailable, invalid }

final class Rag3BatchedSupportFilterPrediction {
  const Rag3BatchedSupportFilterPrediction({
    required this.status,
    required this.decisions,
    required this.latencyMs,
    required this.reason,
  });

  factory Rag3BatchedSupportFilterPrediction.parse({
    required Rag3BatchedSupportFilterInput input,
    required Rag3SupportFilterClassifierResponse response,
  }) {
    if (response.latencyMs < 0) {
      throw const FormatException(
        'RAG3 support-filter latency cannot be negative.',
      );
    }
    final decoded = jsonDecode(response.raw);
    if (decoded is! Map) {
      throw const FormatException(
        'RAG3 support-filter response must be a JSON object.',
      );
    }
    final json = decoded.cast<String, Object?>();
    if (json.keys.toSet().difference(const {
          'schemaVersion',
          'decisions',
        }).isNotEmpty ||
        json.length != 2 ||
        json['schemaVersion'] != 1 ||
        json['decisions'] is! List) {
      throw const FormatException(
        'RAG3 support-filter response must match the exact v1 schema.',
      );
    }
    final expectedIds = input.chunks.map((item) => item.chunkId).toSet();
    final decisions = <String, Rag3SupportFilterDecision>{};
    for (final rawDecision in json['decisions']! as List) {
      if (rawDecision is! Map) {
        throw const FormatException(
          'RAG3 support-filter decisions must be JSON objects.',
        );
      }
      final item = rawDecision.cast<String, Object?>();
      if (item.keys.toSet().difference(const {
            'chunkId',
            'decision',
          }).isNotEmpty ||
          item.length != 2 ||
          item['chunkId'] is! String ||
          item['decision'] is! String) {
        throw const FormatException(
          'RAG3 support-filter decision must match the exact schema.',
        );
      }
      final chunkId = item['chunkId']! as String;
      if (!expectedIds.contains(chunkId) || decisions.containsKey(chunkId)) {
        throw const FormatException(
          'RAG3 support-filter decisions must use each supplied chunk ID once.',
        );
      }
      decisions[chunkId] = Rag3SupportFilterDecision.parse(
        item['decision']! as String,
      );
    }
    if (decisions.keys.toSet().length != expectedIds.length ||
        !decisions.keys.toSet().containsAll(expectedIds)) {
      throw const FormatException(
        'RAG3 support-filter response must classify every supplied chunk.',
      );
    }
    return Rag3BatchedSupportFilterPrediction(
      status: Rag3SupportFilterPredictionStatus.available,
      decisions: Map.unmodifiable(decisions),
      latencyMs: response.latencyMs,
      reason: 'classified',
    );
  }

  factory Rag3BatchedSupportFilterPrediction.failClosed({
    required Rag3BatchedSupportFilterInput input,
    required Rag3SupportFilterPredictionStatus status,
    required String reason,
  }) => Rag3BatchedSupportFilterPrediction(
    status: status,
    decisions: Map.unmodifiable({
      for (final chunk in input.chunks)
        chunk.chunkId: Rag3SupportFilterDecision.dropNonSupport,
    }),
    latencyMs: 0,
    reason: reason,
  );

  final Rag3SupportFilterPredictionStatus status;
  final Map<String, Rag3SupportFilterDecision> decisions;
  final int latencyMs;
  final String reason;

  Map<String, Object?> toJson() => {
    'status': status.name,
    'latencyMs': latencyMs,
    'reason': reason,
    'decisions': [
      for (final entry in decisions.entries)
        {'chunkId': entry.key, 'decision': entry.value.id},
    ],
  };
}

final class Rag3SupportFilterInstrumentExample {
  const Rag3SupportFilterInstrumentExample({
    required this.caseId,
    required this.input,
    required this.expectedDecisions,
  });

  final String caseId;
  final Rag3BatchedSupportFilterInput input;
  final Map<String, Rag3SupportFilterDecision> expectedDecisions;
}

Future<Rag3BatchedSupportFilterReport> evaluateRag3BatchedSupportFilter({
  required String fixtureId,
  required List<Rag3SupportFilterInstrumentExample> examples,
  required Rag3BatchedSupportFilterClassifier classifier,
}) async {
  if (fixtureId.trim().isEmpty || examples.isEmpty) {
    throw StateError('RAG3 support-filter evaluation requires a fixture.');
  }
  if (isRag3SupportFilterPromotionPath(fixtureId)) {
    throw StateError(
      'RAG3 support-filter evaluation cannot use promotion artifacts.',
    );
  }
  if (examples.map((item) => item.caseId).toSet().length != examples.length) {
    throw StateError('RAG3 support-filter case IDs must be unique.');
  }
  final expectedValues = <Rag3SupportFilterDecision>{};
  for (final example in examples) {
    final chunkIds = example.input.chunks.map((item) => item.chunkId).toSet();
    if (example.expectedDecisions.keys.toSet().length != chunkIds.length ||
        !example.expectedDecisions.keys.toSet().containsAll(chunkIds)) {
      throw StateError(
        'RAG3 support-filter oracle must classify every supplied chunk.',
      );
    }
    expectedValues.addAll(example.expectedDecisions.values);
  }
  if (!expectedValues.containsAll(Rag3SupportFilterDecision.values)) {
    throw StateError(
      'RAG3 support-filter evaluation must cover both decision classes.',
    );
  }
  final cases = <Rag3SupportFilterCaseResult>[];
  for (final example in examples) {
    late final Rag3BatchedSupportFilterPrediction prediction;
    try {
      prediction = Rag3BatchedSupportFilterPrediction.parse(
        input: example.input,
        response: await classifier.classify(example.input),
      );
    } on Rag3BatchedSupportFilterUnavailable {
      prediction = Rag3BatchedSupportFilterPrediction.failClosed(
        input: example.input,
        status: Rag3SupportFilterPredictionStatus.notAvailable,
        reason: 'classifier_not_available',
      );
    } on FormatException {
      prediction = Rag3BatchedSupportFilterPrediction.failClosed(
        input: example.input,
        status: Rag3SupportFilterPredictionStatus.invalid,
        reason: 'invalid_classifier_response',
      );
    }
    cases.add(
      Rag3SupportFilterCaseResult(
        caseId: example.caseId,
        expectedDecisions: Map.unmodifiable(example.expectedDecisions),
        prediction: prediction,
      ),
    );
  }
  return Rag3BatchedSupportFilterReport(
    fixtureId: fixtureId,
    cases: List.unmodifiable(cases),
  );
}

final class Rag3SupportFilterCaseResult {
  const Rag3SupportFilterCaseResult({
    required this.caseId,
    required this.expectedDecisions,
    required this.prediction,
  });

  final String caseId;
  final Map<String, Rag3SupportFilterDecision> expectedDecisions;
  final Rag3BatchedSupportFilterPrediction prediction;

  Map<String, Object?> toJson() => {
    'caseId': caseId,
    'expectedDecisions': [
      for (final entry in expectedDecisions.entries)
        {'chunkId': entry.key, 'decision': entry.value.id},
    ],
    'prediction': prediction.toJson(),
  };
}

final class Rag3SupportFilterMetrics {
  const Rag3SupportFilterMetrics({
    required this.truePositive,
    required this.trueNegative,
    required this.falsePositive,
    required this.falseNegative,
  });

  final int truePositive;
  final int trueNegative;
  final int falsePositive;
  final int falseNegative;

  double get precision => truePositive + falsePositive == 0
      ? 0
      : truePositive / (truePositive + falsePositive);
  double get recall => truePositive + falseNegative == 0
      ? 0
      : truePositive / (truePositive + falseNegative);
  double get f1 => precision + recall == 0
      ? 0
      : 2 * precision * recall / (precision + recall);

  Map<String, Object?> toJson() => {
    'truePositive': truePositive,
    'trueNegative': trueNegative,
    'falsePositive': falsePositive,
    'falseNegative': falseNegative,
    'precision': precision,
    'recall': recall,
    'f1': f1,
  };
}

final class Rag3BatchedSupportFilterReport {
  const Rag3BatchedSupportFilterReport({
    required this.fixtureId,
    required this.cases,
  });

  final String fixtureId;
  final List<Rag3SupportFilterCaseResult> cases;

  Rag3SupportFilterMetrics get metrics {
    var truePositive = 0;
    var trueNegative = 0;
    var falsePositive = 0;
    var falseNegative = 0;
    for (final item in cases) {
      for (final expected in item.expectedDecisions.entries) {
        final predicted = item.prediction.decisions[expected.key]!;
        if (expected.value == Rag3SupportFilterDecision.retainSupport) {
          if (predicted == expected.value) {
            truePositive++;
          } else {
            falseNegative++;
          }
        } else if (predicted == Rag3SupportFilterDecision.retainSupport) {
          falsePositive++;
        } else {
          trueNegative++;
        }
      }
    }
    return Rag3SupportFilterMetrics(
      truePositive: truePositive,
      trueNegative: trueNegative,
      falsePositive: falsePositive,
      falseNegative: falseNegative,
    );
  }

  int get unavailableCount => cases
      .where(
        (item) =>
            item.prediction.status ==
            Rag3SupportFilterPredictionStatus.notAvailable,
      )
      .length;
  int get invalidCount => cases
      .where(
        (item) =>
            item.prediction.status == Rag3SupportFilterPredictionStatus.invalid,
      )
      .length;
  List<int> get _availableLatencies {
    final values =
        cases
            .where(
              (item) =>
                  item.prediction.status ==
                  Rag3SupportFilterPredictionStatus.available,
            )
            .map((item) => item.prediction.latencyMs)
            .toList()
          ..sort();
    return values;
  }

  int get p50LatencyMs => _nearestRankLatency(0.50);
  int get p95LatencyMs => _nearestRankLatency(0.95);

  int _nearestRankLatency(double percentile) {
    final values = _availableLatencies;
    if (values.isEmpty) return 0;
    return values[math.max(0, (values.length * percentile).ceil() - 1)];
  }

  bool get passed =>
      unavailableCount == 0 &&
      invalidCount == 0 &&
      metrics.falsePositive == 0 &&
      metrics.falseNegative == 0;

  Map<String, Object?> toJson() => {
    'schemaName': rag3BatchedSupportFilterSchema,
    'schemaVersion': 1,
    'contract': rag3BatchedSupportFilterContract,
    'fixtureId': fixtureId,
    'instrumentDecision': passed ? 'go' : 'no_go',
    'productionDecision': 'no_go',
    'promotionDecision': 'not_run',
    'latencyDecision': 'measurement_only',
    'activationDecision': 'blocked_pending_latency_contract',
    'maximumChunksPerBatch': rag3BatchedSupportFilterMaximumChunks,
    'p50LatencyMs': p50LatencyMs,
    'p95LatencyMs': p95LatencyMs,
    'unavailableCount': unavailableCount,
    'invalidCount': invalidCount,
    'metrics': metrics.toJson(),
    'cases': [for (final item in cases) item.toJson()],
  };
}

bool isRag3SupportFilterPromotionPath(String path) {
  final normalized = path.toLowerCase();
  return normalized.contains('rag3_offline_hybrid_holdout') ||
      normalized.contains('rag3_promotion');
}

bool _isSafeRelativePath(String path) =>
    !path.startsWith('/') &&
    !path.contains('\\') &&
    !path.split('/').contains('..') &&
    !Uri.parse(path).hasScheme;
