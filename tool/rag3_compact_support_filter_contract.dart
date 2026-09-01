import 'dart:convert';

import 'rag3_batched_support_filter_contract.dart';

const rag3CompactSupportFilterSchema =
    'caverno_rag3_compact_support_filter_report';
const rag3CompactSupportFilterContract = 'rag3-compact-support-filter-v3';
const rag3CompactSupportFilterMaximumOutputTokens = 32;
const rag3CompactSupportFilterMaximumP95LatencyMs = 1200;

Map<String, Object?> rag3CompactSupportFilterClassifierJson(
  Rag3BatchedSupportFilterInput input,
) => {
  'contract': rag3CompactSupportFilterContract,
  'query': input.query,
  'revision': input.revision,
  'authority': input.authority,
  'orderedEvidence': [
    for (final chunk in input.chunks) chunk.toClassifierJson(),
  ],
  'mask': {
    'position': 'Each character corresponds to orderedEvidence at that index.',
    '1': 'Retain direct answer or bounded-abstention support.',
    '0': 'Drop topical-only, irrelevant, wrong-scope, or instructional text.',
    'requiredLength': input.chunks.length,
  },
  'output': {'schemaVersion': 1, 'mask': '<exact 0/1 mask>'},
};

final class Rag3CompactSupportFilterClassifierResponse {
  const Rag3CompactSupportFilterClassifierResponse({
    required this.raw,
    required this.latencyMs,
  });

  final String raw;
  final int latencyMs;
}

abstract interface class Rag3CompactSupportFilterClassifier {
  Future<Rag3CompactSupportFilterClassifierResponse> classify(
    Rag3BatchedSupportFilterInput input,
  );
}

Rag3BatchedSupportFilterPrediction parseRag3CompactSupportFilterPrediction({
  required Rag3BatchedSupportFilterInput input,
  required Rag3CompactSupportFilterClassifierResponse response,
}) {
  if (response.latencyMs < 0) {
    throw const FormatException(
      'RAG3 compact support-filter latency cannot be negative.',
    );
  }
  final decoded = jsonDecode(response.raw);
  if (decoded is! Map) {
    throw const FormatException(
      'RAG3 compact support-filter response must be a JSON object.',
    );
  }
  final json = decoded.cast<String, Object?>();
  if (json.keys.toSet().difference(const {
        'schemaVersion',
        'mask',
      }).isNotEmpty ||
      json.length != 2 ||
      json['schemaVersion'] != 1 ||
      json['mask'] is! String) {
    throw const FormatException(
      'RAG3 compact support-filter response must match the exact v1 schema.',
    );
  }
  final mask = json['mask']! as String;
  if (mask.length != input.chunks.length ||
      !RegExp(r'^[01]+$').hasMatch(mask)) {
    throw const FormatException(
      'RAG3 compact support-filter mask must classify every supplied chunk.',
    );
  }
  return Rag3BatchedSupportFilterPrediction(
    status: Rag3SupportFilterPredictionStatus.available,
    decisions: Map.unmodifiable({
      for (var index = 0; index < input.chunks.length; index++)
        input.chunks[index].chunkId: mask[index] == '1'
            ? Rag3SupportFilterDecision.retainSupport
            : Rag3SupportFilterDecision.dropNonSupport,
    }),
    latencyMs: response.latencyMs,
    reason: 'compact_mask_classified',
  );
}

Future<Rag3CompactSupportFilterReport> evaluateRag3CompactSupportFilter({
  required String fixtureId,
  required List<Rag3SupportFilterInstrumentExample> examples,
  required Rag3CompactSupportFilterClassifier classifier,
}) async {
  if (fixtureId.trim().isEmpty || examples.isEmpty) {
    throw StateError(
      'RAG3 compact support-filter evaluation requires a fixture.',
    );
  }
  if (isRag3SupportFilterPromotionPath(fixtureId)) {
    throw StateError(
      'RAG3 compact support-filter evaluation cannot use promotion artifacts.',
    );
  }
  if (examples.map((item) => item.caseId).toSet().length != examples.length) {
    throw StateError('RAG3 compact support-filter case IDs must be unique.');
  }
  final expectedValues = <Rag3SupportFilterDecision>{};
  for (final example in examples) {
    final chunkIds = example.input.chunks.map((item) => item.chunkId).toSet();
    if (example.expectedDecisions.keys.toSet().length != chunkIds.length ||
        !example.expectedDecisions.keys.toSet().containsAll(chunkIds)) {
      throw StateError(
        'RAG3 compact support-filter oracle must classify every chunk.',
      );
    }
    expectedValues.addAll(example.expectedDecisions.values);
  }
  if (!expectedValues.containsAll(Rag3SupportFilterDecision.values)) {
    throw StateError(
      'RAG3 compact support-filter evaluation must cover both classes.',
    );
  }

  final cases = <Rag3SupportFilterCaseResult>[];
  for (final example in examples) {
    late final Rag3BatchedSupportFilterPrediction prediction;
    try {
      prediction = parseRag3CompactSupportFilterPrediction(
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
  return Rag3CompactSupportFilterReport(
    fixtureId: fixtureId,
    cases: List.unmodifiable(cases),
  );
}

final class Rag3CompactSupportFilterReport {
  const Rag3CompactSupportFilterReport({
    required this.fixtureId,
    required this.cases,
  });

  final String fixtureId;
  final List<Rag3SupportFilterCaseResult> cases;

  Rag3BatchedSupportFilterReport get _qualityReport =>
      Rag3BatchedSupportFilterReport(fixtureId: fixtureId, cases: cases);

  Rag3SupportFilterMetrics get metrics => _qualityReport.metrics;
  int get unavailableCount => _qualityReport.unavailableCount;
  int get invalidCount => _qualityReport.invalidCount;
  int get p50LatencyMs => _qualityReport.p50LatencyMs;
  int get p95LatencyMs => _qualityReport.p95LatencyMs;
  bool get qualityPassed => _qualityReport.passed;
  bool get latencyPassed =>
      p95LatencyMs <= rag3CompactSupportFilterMaximumP95LatencyMs;
  bool get passed => qualityPassed && latencyPassed;

  Map<String, Object?> toJson() => {
    'schemaName': rag3CompactSupportFilterSchema,
    'schemaVersion': 1,
    'contract': rag3CompactSupportFilterContract,
    'fixtureId': fixtureId,
    'outputProtocol': 'ordered_binary_mask',
    'maximumOutputTokens': rag3CompactSupportFilterMaximumOutputTokens,
    'maximumP95LatencyMs': rag3CompactSupportFilterMaximumP95LatencyMs,
    'p50LatencyMs': p50LatencyMs,
    'p95LatencyMs': p95LatencyMs,
    'qualityDecision': qualityPassed ? 'go' : 'no_go',
    'latencyDecision': latencyPassed ? 'go' : 'no_go',
    'instrumentDecision': passed ? 'go' : 'no_go',
    'productionDecision': 'no_go',
    'promotionDecision': 'not_run',
    'unavailableCount': unavailableCount,
    'invalidCount': invalidCount,
    'metrics': metrics.toJson(),
    'cases': [for (final item in cases) item.toJson()],
  };
}
