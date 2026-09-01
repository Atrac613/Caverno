import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/rag3_batched_support_filter_contract.dart';

void main() {
  test('passes exact cross-bucket predictions and records latency', () async {
    final classifier = _RecordingClassifier(_exactResponse, const [
      900,
      1200,
      1800,
      3000,
    ]);

    final report = await evaluateRag3BatchedSupportFilter(
      fixtureId: 'rag2-compositional-instrument-v1',
      examples: _examples(),
      classifier: classifier,
    );

    expect(report.passed, isTrue);
    expect(report.metrics.truePositive, 4);
    expect(report.metrics.trueNegative, 4);
    expect(report.metrics.falsePositive, 0);
    expect(report.metrics.falseNegative, 0);
    expect(report.metrics.f1, 1);
    expect(report.p50LatencyMs, 1200);
    expect(report.p95LatencyMs, 3000);
    expect(report.toJson(), containsPair('productionDecision', 'no_go'));
    expect(report.toJson(), containsPair('promotionDecision', 'not_run'));
    expect(
      report.toJson(),
      containsPair('latencyDecision', 'measurement_only'),
    );
    expect(
      report.toJson(),
      containsPair('activationDecision', 'blocked_pending_latency_contract'),
    );
  });

  test('keeps expected decisions and oracle fields out of requests', () async {
    final firstClassifier = _RecordingClassifier(_exactResponse, const [
      100,
      100,
      100,
      100,
    ]);
    final secondClassifier = _RecordingClassifier(_exactResponse, const [
      100,
      100,
      100,
      100,
    ]);
    final examples = _examples();
    final changedOracle = [
      for (final example in examples)
        Rag3SupportFilterInstrumentExample(
          caseId: example.caseId,
          input: example.input,
          expectedDecisions: {
            for (final entry in example.expectedDecisions.entries)
              entry.key: entry.value == Rag3SupportFilterDecision.retainSupport
                  ? Rag3SupportFilterDecision.dropNonSupport
                  : Rag3SupportFilterDecision.retainSupport,
          },
        ),
    ];

    final first = await evaluateRag3BatchedSupportFilter(
      fixtureId: 'rag2-compositional-instrument-v1',
      examples: examples,
      classifier: firstClassifier,
    );
    final second = await evaluateRag3BatchedSupportFilter(
      fixtureId: 'rag2-compositional-instrument-v1',
      examples: changedOracle,
      classifier: secondClassifier,
    );

    expect(firstClassifier.requests, secondClassifier.requests);
    expect(
      firstClassifier.requests.every((request) {
        final encoded = jsonEncode(request);
        return !encoded.contains('expected') &&
            !encoded.contains('oracle') &&
            !encoded.contains('qrel') &&
            !encoded.contains('answerKey');
      }),
      isTrue,
    );
    expect(first.passed, isTrue);
    expect(second.passed, isFalse);
  });

  test('accepts only exact complete decisions for supplied chunk IDs', () {
    final input = _input('case-0');
    final valid = Rag3BatchedSupportFilterPrediction.parse(
      input: input,
      response: Rag3SupportFilterClassifierResponse(
        raw: _exactResponse(input),
        latencyMs: 1,
      ),
    );
    expect(valid.decisions, hasLength(2));

    for (final raw in [
      '```json\n${_exactResponse(input)}\n```',
      '{"schemaVersion":1,"decisions":[]}',
      '{"schemaVersion":1,"decisions":['
          '{"chunkId":"case-0-retain","decision":"retain_support"},'
          '{"chunkId":"case-0-retain","decision":"drop_non_support"}]}',
      '{"schemaVersion":1,"decisions":['
          '{"chunkId":"case-0-retain","decision":"retain_support"},'
          '{"chunkId":"unknown","decision":"drop_non_support"}]}',
      '{"schemaVersion":1,"decisions":['
          '{"chunkId":"case-0-retain","decision":"retain_support",'
          '"reason":"yes"},'
          '{"chunkId":"case-0-drop","decision":"drop_non_support"}]}',
    ]) {
      expect(
        () => Rag3BatchedSupportFilterPrediction.parse(
          input: input,
          response: Rag3SupportFilterClassifierResponse(raw: raw, latencyMs: 1),
        ),
        throwsFormatException,
      );
    }
  });

  test(
    'fails closed on unavailable and invalid classifier responses',
    () async {
      final unavailable = await evaluateRag3BatchedSupportFilter(
        fixtureId: 'rag2-compositional-instrument-v1',
        examples: _examples(),
        classifier: _UnavailableClassifier(),
      );
      final invalid = await evaluateRag3BatchedSupportFilter(
        fixtureId: 'rag2-compositional-instrument-v1',
        examples: _examples(),
        classifier: _ConstantClassifier('not-json'),
      );

      expect(unavailable.passed, isFalse);
      expect(unavailable.unavailableCount, 4);
      expect(unavailable.metrics.falseNegative, 4);
      expect(invalid.passed, isFalse);
      expect(invalid.invalidCount, 4);
      expect(invalid.metrics.falseNegative, 4);
      for (final report in [unavailable, invalid]) {
        expect(
          report.cases.every(
            (item) => item.prediction.decisions.values.every(
              (decision) =>
                  decision == Rag3SupportFilterDecision.dropNonSupport,
            ),
          ),
          isTrue,
        );
      }
    },
  );

  test('keeps ungrounded latency out of the quality decision', () async {
    final report = await evaluateRag3BatchedSupportFilter(
      fixtureId: 'rag2-compositional-instrument-v1',
      examples: _examples(),
      classifier: _RecordingClassifier(_exactResponse, const [
        1000,
        2000,
        3000,
        3001,
      ]),
    );

    expect(report.metrics.f1, 1);
    expect(report.p95LatencyMs, 3001);
    expect(report.passed, isTrue);
    expect(report.toJson(), isNot(contains('maximumP95LatencyMs')));
  });

  test('rejects an all-retain shortcut with false positives', () async {
    final report = await evaluateRag3BatchedSupportFilter(
      fixtureId: 'rag2-compositional-instrument-v1',
      examples: _examples(),
      classifier: _RecordingClassifier(
        (input) => jsonEncode({
          'schemaVersion': 1,
          'decisions': [
            for (final chunk in input.chunks)
              {'chunkId': chunk.chunkId, 'decision': 'retain_support'},
          ],
        }),
        const [1, 1, 1, 1],
      ),
    );

    expect(report.metrics.falsePositive, 4);
    expect(report.metrics.falseNegative, 0);
    expect(report.passed, isFalse);
  });

  test('rejects unsafe, oversized, duplicate, and promotion inputs', () async {
    expect(
      () =>
          _chunk('bad', sourcePath: 'tool/fixtures/rag3_promotion/document.md'),
      throwsStateError,
    );
    expect(
      () => Rag3BatchedSupportFilterInput(
        query: 'query',
        revision: 'abc123',
        authority: 'current',
        chunks: [for (var index = 0; index < 11; index++) _chunk('$index')],
      ),
      throwsStateError,
    );
    expect(
      () => Rag3BatchedSupportFilterInput(
        query: 'query',
        revision: 'abc123',
        authority: 'current',
        chunks: [_chunk('same'), _chunk('same')],
      ),
      throwsStateError,
    );
    await expectLater(
      evaluateRag3BatchedSupportFilter(
        fixtureId: 'rag3_offline_hybrid_holdout-v2',
        examples: _examples(),
        classifier: _RecordingClassifier(_exactResponse, const []),
      ),
      throwsStateError,
    );
  });

  test('omits query and evidence content from reports', () async {
    final report = await evaluateRag3BatchedSupportFilter(
      fixtureId: 'rag2-compositional-instrument-v1',
      examples: _examples(),
      classifier: _RecordingClassifier(_exactResponse, const [1, 1, 1, 1]),
    );
    final encoded = jsonEncode(report.toJson());

    expect(encoded, isNot(contains('private query')));
    expect(encoded, isNot(contains('sensitive evidence')));
    expect(encoded, contains('case-0-retain'));
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
        _chunk('$id-retain', content: 'sensitive evidence retain $id'),
        _chunk('$id-drop', content: 'sensitive evidence drop $id'),
      ],
    );

Rag3SupportFilterChunkInput _chunk(
  String id, {
  String? sourcePath,
  String? content,
}) => Rag3SupportFilterChunkInput(
  chunkId: id,
  sourcePath: sourcePath ?? 'docs/$id.md',
  content: content ?? 'content $id',
);

String _exactResponse(Rag3BatchedSupportFilterInput input) => jsonEncode({
  'schemaVersion': 1,
  'decisions': [
    for (final chunk in input.chunks)
      {
        'chunkId': chunk.chunkId,
        'decision': chunk.chunkId.endsWith('-retain')
            ? 'retain_support'
            : 'drop_non_support',
      },
  ],
});

final class _RecordingClassifier implements Rag3BatchedSupportFilterClassifier {
  _RecordingClassifier(this.handler, this.latencies);

  final String Function(Rag3BatchedSupportFilterInput input) handler;
  final List<int> latencies;
  final requests = <Map<String, Object?>>[];
  int _index = 0;

  @override
  Future<Rag3SupportFilterClassifierResponse> classify(
    Rag3BatchedSupportFilterInput input,
  ) async {
    requests.add(input.toClassifierJson());
    final latency = latencies.isEmpty ? 0 : latencies[_index++];
    return Rag3SupportFilterClassifierResponse(
      raw: handler(input),
      latencyMs: latency,
    );
  }
}

final class _UnavailableClassifier
    implements Rag3BatchedSupportFilterClassifier {
  @override
  Future<Rag3SupportFilterClassifierResponse> classify(
    Rag3BatchedSupportFilterInput input,
  ) {
    throw const Rag3BatchedSupportFilterUnavailable();
  }
}

final class _ConstantClassifier implements Rag3BatchedSupportFilterClassifier {
  const _ConstantClassifier(this.raw);

  final String raw;

  @override
  Future<Rag3SupportFilterClassifierResponse> classify(
    Rag3BatchedSupportFilterInput input,
  ) async => Rag3SupportFilterClassifierResponse(raw: raw, latencyMs: 1);
}
