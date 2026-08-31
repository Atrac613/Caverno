import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/rag3_candidate_run_producer.dart';
import '../../tool/rag3_offline_hybrid_eval.dart';

void main() {
  late Rag3HybridFixture fixture;
  late Rag3VectorFingerprint fingerprint;
  late List<Rag3CandidateCaseInput> inputs;

  setUp(() {
    fixture = _buildSyntheticFixture();
    fingerprint = Rag3VectorFingerprint(
      schemaVersion: 1,
      endpointIdentity: Rag3VectorFingerprint.normalizeEndpointIdentity(
        'HTTP://user:secret@Embedding.Local:80/v1/?api_key=hidden#fragment',
      ),
      requestedModelId: 'fixture-embed-v1',
      responseModelId: 'fixture-embed-v1',
      dimension: 2,
    );
    inputs = _buildInputs(fixture, fingerprint);
  });

  test('produces a bound run and passes the synthetic promotion shape', () {
    final runJson = const Rag3CandidateRunProducer().produce(
      fixture: fixture,
      runId: 'synthetic-green',
      metadata: _metadata(extra: {'endpoint': 'must-not-leak'}),
      cases: inputs,
    );
    final report = evaluateRag3HybridRun(
      fixture: fixture,
      run: Rag3CandidateRun.fromJson(runJson),
    );

    expect(runJson['contractId'], rag3ContractId);
    expect(runJson['candidateId'], rag3CandidateId);
    expect(report.passed, isTrue);
    expect(report.deterministicReplayPassed, isTrue);
    expect(report.core.hybridMetrics.objectRecallAt10, greaterThan(0.85));
    expect(report.core.answerSupportCount, 14);
    expect(report.core.japaneseSupportCount, 4);
    expect(report.core.abstentionSupportCount, 2);
    expect(report.core.unavailableIrrelevantOnlyCount, 0);
    expect(report.core.negativeControls.emptyFusionDetected, isTrue);
    expect(report.core.negativeControls.budgetBypassDetected, isTrue);
    expect(report.core.hybridMetrics.totalLatencyMs, greaterThan(0));
    expect(report.core.hybridMetrics.peakRssBytes, 1024);

    final budget = report.core.cases.singleWhere(
      (item) => item.caseId == 'answer-13-budget',
    );
    expect(budget.totalContextTokens, lessThanOrEqualTo(6000));
    expect(
      budget.exclusions,
      contains(containsPair('reason', 'context_budget')),
    );

    final encoded = jsonEncode(report.toJson());
    expect(encoded, isNot(contains('HTTP://Embedding.Local')));
    expect(encoded, isNot(contains('http://embedding.local')));
    expect(encoded, isNot(contains('must-not-leak')));
    expect(encoded, isNot(contains('synthetic query')));
    expect(report.toMarkdown(), contains('Result: `go`'));
  });

  test('deduplicates RRF inputs and applies merge and diversity ordering', () {
    final runJson = const Rag3CandidateRunProducer().produce(
      fixture: fixture,
      runId: 'synthetic-selection',
      metadata: _metadata(),
      cases: inputs,
    );
    final mutable = _deepCopy(runJson);
    final runCase = _runCase(mutable, 'answer-00');
    runCase['lexicalRankedChunkIds'] = [
      'docs/answer.md#1',
      'docs/answer.md#2',
      'docs/answer.md#1',
      'docs/answer.md#3',
      'docs/answer.md#4',
    ];
    final vector = (runCase['vector'] as Map).cast<String, Object?>();
    vector['rankedChunkIds'] = [
      'docs/answer.md#2',
      'docs/answer.md#1',
      'docs/answer.md#3',
      'docs/answer.md#4',
    ];

    final report = evaluateRag3HybridRun(
      fixture: fixture,
      run: Rag3CandidateRun.fromJson(mutable),
    );
    final result = report.core.cases.singleWhere(
      (item) => item.caseId == 'answer-00',
    );

    expect(result.fusedRanking.map((item) => item.chunkId), [
      'docs/answer.md#1',
      'docs/answer.md#2',
      'docs/answer.md#3',
      'docs/answer.md#4',
    ]);
    expect(result.groups, hasLength(2));
    expect(result.groups.first.chunkIds, [
      'docs/answer.md#1',
      'docs/answer.md#2',
    ]);
    expect(
      result.exclusions,
      contains(containsPair('reason', 'object_diversity_cap')),
    );
  });

  test('invalid vector identities degrade to lexical with an exact reason', () {
    final mismatched = Rag3VectorFingerprint(
      schemaVersion: 1,
      endpointIdentity: fingerprint.endpointIdentity,
      requestedModelId: 'other-model',
      responseModelId: 'other-model',
      dimension: 2,
    );
    inputs = _replaceVector(
      inputs,
      'answer-00',
      Rag3VectorRankingInput.available(
        queryFingerprint: fingerprint,
        corpusFingerprint: mismatched,
        queryVector: const [1, 0],
        corpusVectors: const {
          'docs/answer.md#1': [1, 0],
        },
      ),
    );
    final runJson = const Rag3CandidateRunProducer().produce(
      fixture: fixture,
      runId: 'synthetic-degraded',
      metadata: _metadata(),
      cases: inputs,
    );
    final vector = (_runCase(runJson, 'answer-00')['vector'] as Map)
        .cast<String, Object?>();
    expect(vector['status'], 'invalid');
    expect(vector['degradedReason'], 'fingerprint_mismatch');
    expect(vector['rankedChunkIds'], isEmpty);

    final report = evaluateRag3HybridRun(
      fixture: fixture,
      run: Rag3CandidateRun.fromJson(runJson),
    );
    final result = report.core.cases.singleWhere(
      (item) => item.caseId == 'answer-00',
    );
    expect(result.status, 'degraded');
    expect(result.degradedReason, 'fingerprint_mismatch');
    expect(result.groups.first.objectId, 'docs/answer.md');
  });

  test('rejects non-finite, zero, and mismatched-dimension vectors', () {
    final scenarios = <String, List<double>>{
      'non_finite_vector': [double.nan, 1],
      'zero_magnitude_vector': [0, 0],
      'dimension_mismatch': [1],
    };
    for (final entry in scenarios.entries) {
      final scenarioInputs = _replaceVector(
        inputs,
        'answer-00',
        Rag3VectorRankingInput.available(
          queryFingerprint: fingerprint,
          corpusFingerprint: fingerprint,
          queryVector: entry.value,
          corpusVectors: const {
            'docs/answer.md#1': [1, 0],
          },
        ),
      );
      final run = const Rag3CandidateRunProducer().produce(
        fixture: fixture,
        runId: 'invalid-${entry.key}',
        metadata: _metadata(),
        cases: scenarioInputs,
      );
      final vector = (_runCase(run, 'answer-00')['vector'] as Map)
          .cast<String, Object?>();
      expect(vector['status'], 'invalid', reason: entry.key);
      expect(vector['degradedReason'], entry.key);
      expect(vector['rankedChunkIds'], isEmpty);
    }
  });

  test('rejects identity drift and retrieval on a no-search case', () {
    final runJson = const Rag3CandidateRunProducer().produce(
      fixture: fixture,
      runId: 'synthetic-invalid',
      metadata: _metadata(),
      cases: inputs,
    );
    final wrongCandidate = _deepCopy(runJson)..['candidateId'] = 'other';
    expect(
      () => Rag3CandidateRun.fromJson(wrongCandidate).validate(fixture),
      throwsStateError,
    );

    final submitted = _deepCopy(runJson);
    _runCase(submitted, 'no-search-00')['submitted'] = true;
    expect(
      () => Rag3CandidateRun.fromJson(submitted).validate(fixture),
      throwsStateError,
    );
  });

  test('normalizes endpoint identity and parses the evaluator CLI', () {
    expect(fingerprint.endpointIdentity, 'http://embedding.local/v1');
    final options = Rag3HybridEvalOptions.parse([
      '--fixture',
      'fixture.json',
      '--oracle',
      'oracle.json',
      '--run',
      'run.json',
      '--out-dir',
      'reports',
    ]);
    expect(options, isNotNull);
    expect(options!.oraclePath, 'oracle.json');
    expect(Rag3HybridEvalOptions.parse(['--fixture', 'fixture.json']), isNull);
    final schema =
        (jsonDecode(
                  File(
                    'tool/rag3_offline_hybrid_run.schema.json',
                  ).readAsStringSync(),
                )
                as Map)
            .cast<String, Object?>();
    expect(schema['\$id'], 'caverno://evaluation/rag3-offline-hybrid-run/v1');
    expect(
      ((schema['properties'] as Map)['candidateId'] as Map)['const'],
      rag3CandidateId,
    );
  });
}

Rag3HybridFixture _buildSyntheticFixture() {
  final objects = <String, Rag3KnowledgeObject>{};
  void add(Rag3KnowledgeObject object) => objects[object.id] = object;
  add(
    _object(
      'docs/answer.md',
      [
        'answer alpha',
        'answer beta',
        'gap one',
        'answer gamma',
        'gap two',
        'answer delta',
      ],
      const [(1, 1), (2, 2), (4, 4), (6, 6)],
    ),
  );
  add(
    _object(
      'docs/abstention.md',
      ['the release date is unknown', 'the incident commander is not recorded'],
      const [(1, 1), (2, 2)],
    ),
  );
  add(
    _object(
      'docs/topical.md',
      ['worker capacity has no exact limit'],
      const [(1, 1)],
    ),
  );
  add(
    _object(
      'docs/budget_primary.md',
      [List.filled(23400, 'p').join()],
      const [(1, 1)],
    ),
  );
  add(
    _object(
      'docs/budget_tail.md',
      [List.filled(1000, 't').join()],
      const [(1, 1)],
    ),
  );

  final fixtureCases = <Map<String, Object?>>[];
  final oracleCases = <Map<String, Object?>>[];
  for (var index = 0; index < 14; index++) {
    final id = index == 13
        ? 'answer-13-budget'
        : 'answer-${index.toString().padLeft(2, '0')}';
    final budget = index == 13;
    fixtureCases.add({
      'id': id,
      'query': 'synthetic query $id',
      'language': index >= 10 ? 'ja' : 'en',
      'shouldSearch': true,
      'strata': [
        'answerable',
        if (index >= 10) 'japanese',
        if (budget) 'budget_pressure',
      ],
    });
    oracleCases.add({
      'id': id,
      'expectedEvidenceRole': 'answer_support',
      'qrels': budget
          ? {
              'objects': {
                'docs/budget_primary.md': 3,
                'docs/budget_tail.md': 3,
              },
              'chunks': {
                'docs/budget_primary.md#1': 3,
                'docs/budget_tail.md#1': 3,
              },
            }
          : {
              'objects': {'docs/answer.md': 3},
              'chunks': {'docs/answer.md#1': 3},
            },
      'passageRoles': budget
          ? {
              'docs/budget_primary.md#1': 'answer_support',
              'docs/budget_tail.md#1': 'answer_support',
            }
          : {'docs/answer.md#1': 'answer_support'},
    });
  }
  for (var index = 0; index < 4; index++) {
    final id = 'unavailable-${index.toString().padLeft(2, '0')}';
    final expected = index < 2
        ? 'abstention_support'
        : index == 2
        ? 'topical_only'
        : 'no_evidence';
    fixtureCases.add({
      'id': id,
      'query': 'synthetic query $id',
      'language': 'en',
      'shouldSearch': true,
      'strata': ['unavailable', expected],
    });
    oracleCases.add({
      'id': id,
      'expectedEvidenceRole': expected,
      'qrels': index < 2
          ? {
              'objects': {'docs/abstention.md': 3},
              'chunks': {'docs/abstention.md#${index + 1}': 3},
            }
          : {'objects': <String, int>{}, 'chunks': <String, int>{}},
      'passageRoles': index < 2
          ? {'docs/abstention.md#${index + 1}': 'abstention_support'}
          : index == 2
          ? {'docs/topical.md#1': 'topical_only'}
          : <String, String>{},
    });
  }
  for (var index = 0; index < 2; index++) {
    final id = 'no-search-${index.toString().padLeft(2, '0')}';
    fixtureCases.add({
      'id': id,
      'query': 'synthetic query $id',
      'language': 'en',
      'shouldSearch': false,
      'strata': ['no_search'],
    });
    oracleCases.add({
      'id': id,
      'expectedEvidenceRole': 'not_applicable',
      'qrels': {'objects': <String, int>{}, 'chunks': <String, int>{}},
      'passageRoles': <String, String>{},
    });
  }
  final fixtureJson = <String, Object?>{
    'schemaName': rag3FixtureSchema,
    'schemaVersion': 1,
    'contractId': rag3ContractId,
    'fixtureId': 'synthetic-rag3-v1',
    'corpusHash': List.filled(64, 'a').join(),
    'selectionPolicy': {
      'contextBudgetTokens': 6000,
      'maxGroupsPerObject': 2,
      'estimatedRunesPerToken': 4,
      'citationFormatVersion': 'rag3-citation-v1',
    },
    'negativeControls': [
      {'id': 'empty-shuffled-fusion', 'expectedOutcome': 'fails_quality_gate'},
      {
        'id': 'budget-bypass',
        'expectedOutcome': 'fails_zero_budget_violation_gate',
      },
    ],
    'cases': fixtureCases,
  };
  final oracleJson = <String, Object?>{
    'schemaName': rag3OracleSchema,
    'schemaVersion': 1,
    'contractId': rag3ContractId,
    'fixtureId': 'synthetic-rag3-v1',
    'corpusHash': List.filled(64, 'a').join(),
    'defaultPassageRole': 'irrelevant',
    'cases': oracleCases,
  };
  return Rag3HybridFixture.fromJson(
    fixtureJson: fixtureJson,
    oracleJson: oracleJson,
    objects: objects,
  );
}

Rag3KnowledgeObject _object(
  String id,
  List<String> lines,
  List<(int, int)> spans,
) {
  final objectHash = sha256.convert(utf8.encode(lines.join('\n'))).toString();
  return Rag3KnowledgeObject(
    id: id,
    sourcePath: id,
    revision: 'synthetic-rev-1',
    objectContentHash: objectHash,
    sourceTrust: 'high',
    authority: 'current',
    sourceLines: lines,
    chunks: [
      for (var index = 0; index < spans.length; index++)
        Rag3Chunk(
          id: '$id#${index + 1}',
          objectId: id,
          lineStart: spans[index].$1,
          lineEnd: spans[index].$2,
          contentHash: sha256
              .convert(
                utf8.encode(
                  lines
                      .sublist(spans[index].$1 - 1, spans[index].$2)
                      .join('\n'),
                ),
              )
              .toString(),
        ),
    ],
  );
}

List<Rag3CandidateCaseInput> _buildInputs(
  Rag3HybridFixture fixture,
  Rag3VectorFingerprint fingerprint,
) => [
  for (final fixtureCase in fixture.cases.values)
    _inputForCase(fixtureCase, fingerprint),
];

Rag3CandidateCaseInput _inputForCase(
  Rag3FixtureCase fixtureCase,
  Rag3VectorFingerprint fingerprint,
) {
  late final List<String> ranking;
  if (!fixtureCase.shouldSearch || fixtureCase.id == 'unavailable-03') {
    ranking = const [];
  } else if (fixtureCase.id == 'answer-13-budget') {
    ranking = const ['docs/budget_primary.md#1', 'docs/budget_tail.md#1'];
  } else if (fixtureCase.id.startsWith('answer-')) {
    ranking = const ['docs/answer.md#1'];
  } else if (fixtureCase.id == 'unavailable-00') {
    ranking = const ['docs/abstention.md#1'];
  } else if (fixtureCase.id == 'unavailable-01') {
    ranking = const ['docs/abstention.md#2'];
  } else {
    ranking = const ['docs/topical.md#1'];
  }
  final unavailable =
      !fixtureCase.shouldSearch || fixtureCase.id == 'unavailable-03';
  return Rag3CandidateCaseInput(
    caseId: fixtureCase.id,
    submitted: fixtureCase.shouldSearch,
    lexicalRankedChunkIds: ranking,
    vector: unavailable
        ? Rag3VectorRankingInput.unavailable(
            fingerprint: fingerprint,
            reason: fixtureCase.shouldSearch
                ? 'embeddings_not_available'
                : 'not_submitted',
          )
        : Rag3VectorRankingInput.available(
            queryFingerprint: fingerprint,
            corpusFingerprint: fingerprint,
            queryVector: const [1, 0],
            corpusVectors: {
              for (var index = 0; index < ranking.length; index++)
                ranking[index]: [1, index * 0.1],
            },
          ),
    lexicalLatencyMs: 1,
    peakRssBytes: 1024,
    peakVramBytes: 0,
  );
}

List<Rag3CandidateCaseInput> _replaceVector(
  List<Rag3CandidateCaseInput> inputs,
  String caseId,
  Rag3VectorRankingInput vector,
) => [
  for (final item in inputs)
    item.caseId == caseId
        ? Rag3CandidateCaseInput(
            caseId: item.caseId,
            submitted: item.submitted,
            lexicalRankedChunkIds: item.lexicalRankedChunkIds,
            vector: vector,
            lexicalLatencyMs: item.lexicalLatencyMs,
            peakRssBytes: item.peakRssBytes,
            peakVramBytes: item.peakVramBytes,
          )
        : item,
];

Map<String, Object?> _metadata({Map<String, Object?> extra = const {}}) => {
  'buildCommit': '01234567',
  'buildDirty': false,
  'hardware': 'synthetic-host',
  'warmState': 'cold',
  'tokenEstimateMethod': 'unicode_code_points_div_4_v1',
  ...extra,
};

Map<String, Object?> _deepCopy(Map<String, Object?> value) =>
    (jsonDecode(jsonEncode(value)) as Map).cast<String, Object?>();

Map<String, Object?> _runCase(Map<String, Object?> run, String id) =>
    ((run['cases'] as List).cast<Map>())
        .map((item) => item.cast<String, Object?>())
        .singleWhere((item) => item['caseId'] == id);
