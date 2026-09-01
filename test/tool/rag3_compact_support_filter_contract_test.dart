import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/rag3_batched_support_filter_contract.dart';
import '../../tool/rag3_compact_support_filter_contract.dart';

void main() {
  test('maps the compact mask to ordered chunk decisions', () {
    final input = _input('case-0');
    final prediction = parseRag3CompactSupportFilterPrediction(
      input: input,
      response: const Rag3CompactSupportFilterClassifierResponse(
        raw: '{"schemaVersion":1,"mask":"10"}',
        latencyMs: 100,
      ),
    );

    expect(prediction.decisions, {
      'case-0-retain': Rag3SupportFilterDecision.retainSupport,
      'case-0-drop': Rag3SupportFilterDecision.dropNonSupport,
    });
  });

  test('keeps oracle fields out of the compact classifier request', () {
    final encoded = jsonEncode(
      rag3CompactSupportFilterClassifierJson(_input('case-0')),
    );

    expect(encoded, contains('orderedEvidence'));
    expect(encoded, contains('requiredLength'));
    expect(encoded, isNot(contains('expected')));
    expect(encoded, isNot(contains('oracle')));
    expect(encoded, isNot(contains('qrel')));
    expect(encoded, isNot(contains('answerKey')));
  });

  test('rejects wrapped, incomplete, invalid, and expanded responses', () {
    final input = _input('case-0');
    for (final raw in const [
      '```json\n{"schemaVersion":1,"mask":"10"}\n```',
      '{"schemaVersion":1,"mask":"1"}',
      '{"schemaVersion":1,"mask":"100"}',
      '{"schemaVersion":1,"mask":"1x"}',
      '{"schemaVersion":1,"mask":"10","reason":"yes"}',
      '{"schemaVersion":2,"mask":"10"}',
    ]) {
      expect(
        () => parseRag3CompactSupportFilterPrediction(
          input: input,
          response: Rag3CompactSupportFilterClassifierResponse(
            raw: raw,
            latencyMs: 1,
          ),
        ),
        throwsFormatException,
      );
    }
  });

  test('requires zero errors and p95 at most 1200 ms', () async {
    final atBoundary = await evaluateRag3CompactSupportFilter(
      fixtureId: 'rag2-compositional-instrument-v1',
      examples: _examples(),
      classifier: _MaskClassifier(const [900, 1000, 1100, 1200]),
    );
    final overBoundary = await evaluateRag3CompactSupportFilter(
      fixtureId: 'rag2-compositional-instrument-v1',
      examples: _examples(),
      classifier: _MaskClassifier(const [900, 1000, 1100, 1201]),
    );

    expect(atBoundary.qualityPassed, isTrue);
    expect(atBoundary.latencyPassed, isTrue);
    expect(atBoundary.passed, isTrue);
    expect(atBoundary.p95LatencyMs, 1200);
    expect(overBoundary.qualityPassed, isTrue);
    expect(overBoundary.latencyPassed, isFalse);
    expect(overBoundary.passed, isFalse);
  });

  test('rejects all-retain and all-drop shortcuts', () async {
    final allRetain = await evaluateRag3CompactSupportFilter(
      fixtureId: 'rag2-compositional-instrument-v1',
      examples: _examples(),
      classifier: _MaskClassifier(const [1, 1, 1, 1], mask: '11'),
    );
    final allDrop = await evaluateRag3CompactSupportFilter(
      fixtureId: 'rag2-compositional-instrument-v1',
      examples: _examples(),
      classifier: _MaskClassifier(const [1, 1, 1, 1], mask: '00'),
    );

    expect(allRetain.metrics.falsePositive, 4);
    expect(allRetain.passed, isFalse);
    expect(allDrop.metrics.falseNegative, 4);
    expect(allDrop.passed, isFalse);
  });

  test('fails closed on unavailable and invalid responses', () async {
    final unavailable = await evaluateRag3CompactSupportFilter(
      fixtureId: 'rag2-compositional-instrument-v1',
      examples: _examples(),
      classifier: _UnavailableClassifier(),
    );
    final invalid = await evaluateRag3CompactSupportFilter(
      fixtureId: 'rag2-compositional-instrument-v1',
      examples: _examples(),
      classifier: _MaskClassifier(const [1, 1, 1, 1], mask: 'invalid'),
    );

    expect(unavailable.unavailableCount, 4);
    expect(unavailable.metrics.falseNegative, 4);
    expect(unavailable.passed, isFalse);
    expect(invalid.invalidCount, 4);
    expect(invalid.metrics.falseNegative, 4);
    expect(invalid.passed, isFalse);
  });

  test('rejects promotion fixtures before classifier calls', () async {
    final classifier = _MaskClassifier(const []);

    await expectLater(
      evaluateRag3CompactSupportFilter(
        fixtureId: 'rag3_offline_hybrid_holdout-v2',
        examples: _examples(),
        classifier: classifier,
      ),
      throwsStateError,
    );
    expect(classifier.callCount, 0);
  });
}

List<Rag3SupportFilterInstrumentExample> _examples() => [
  for (var index = 0; index < 4; index++)
    Rag3SupportFilterInstrumentExample(
      caseId: 'case-$index',
      input: _input('case-$index'),
      expectedDecisions: {
        'case-$index-retain': Rag3SupportFilterDecision.retainSupport,
        'case-$index-drop': Rag3SupportFilterDecision.dropNonSupport,
      },
    ),
];

Rag3BatchedSupportFilterInput _input(String id) =>
    Rag3BatchedSupportFilterInput(
      query: 'private query $id',
      revision: 'abc123',
      authority: 'current',
      chunks: [
        Rag3SupportFilterChunkInput(
          chunkId: '$id-retain',
          sourcePath: 'docs/retain.md',
          content: 'sensitive supporting evidence',
        ),
        Rag3SupportFilterChunkInput(
          chunkId: '$id-drop',
          sourcePath: 'docs/drop.md',
          content: 'sensitive topical evidence',
        ),
      ],
    );

final class _MaskClassifier implements Rag3CompactSupportFilterClassifier {
  _MaskClassifier(this.latencies, {this.mask = '10'});

  final List<int> latencies;
  final String mask;
  int callCount = 0;

  @override
  Future<Rag3CompactSupportFilterClassifierResponse> classify(
    Rag3BatchedSupportFilterInput input,
  ) async {
    final latency = latencies.isEmpty ? 0 : latencies[callCount];
    callCount++;
    return Rag3CompactSupportFilterClassifierResponse(
      raw: jsonEncode({'schemaVersion': 1, 'mask': mask}),
      latencyMs: latency,
    );
  }
}

final class _UnavailableClassifier
    implements Rag3CompactSupportFilterClassifier {
  @override
  Future<Rag3CompactSupportFilterClassifierResponse> classify(
    Rag3BatchedSupportFilterInput input,
  ) {
    throw const Rag3BatchedSupportFilterUnavailable();
  }
}
