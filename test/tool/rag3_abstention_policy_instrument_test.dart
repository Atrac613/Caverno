import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/rag3_abstention_policy_instrument.dart';
import '../../tool/rag3_offline_hybrid_eval.dart';

void main() {
  test('accepts only exact chunk agreement within the configured depth', () {
    const shallow = Rag3CrossArmConsensusPolicy(depth: 1);
    const deep = Rag3CrossArmConsensusPolicy(depth: 3);
    final input = _case(
      caseId: 'case-1',
      lexical: const ['docs/a.md#1', 'docs/b.md#1', 'docs/c.md#1'],
      vector: const ['docs/b.md#1', 'docs/a.md#1', 'docs/c.md#1'],
    );

    expect(shallow.decide(input).reason, 'cross_arm_disagreement');
    expect(deep.decide(input).selectedChunkIds, [
      'docs/a.md#1',
      'docs/b.md#1',
      'docs/c.md#1',
    ]);
  });

  test('abstains when vectors are unavailable or search is not submitted', () {
    const policy = Rag3CrossArmConsensusPolicy(depth: 3);
    final unavailable = _case(
      caseId: 'unavailable',
      lexical: const ['docs/a.md#1'],
      vector: const [],
      vectorStatus: 'not_available',
    );
    final notSubmitted = _case(
      caseId: 'not-submitted',
      lexical: const [],
      vector: const [],
      submitted: false,
      vectorStatus: 'not_available',
    );

    expect(policy.decide(unavailable).reason, 'vector_not_available');
    expect(policy.decide(notSubmitted).reason, 'not_submitted');
  });

  test('keeps predictions independent from qrels and passage roles', () {
    final fixture = _fixture();
    final changedOracle = _fixture(answerRole: 'irrelevant');
    final run = Rag3CandidateRun.fromJson(_run());
    const policy = Rag3CrossArmConsensusPolicy(depth: 3);

    final first = evaluateRag3AbstentionPolicy(
      fixture: fixture,
      run: run,
      policy: policy,
    );
    final second = evaluateRag3AbstentionPolicy(
      fixture: changedOracle,
      run: run,
      policy: policy,
    );

    expect(
      first.cases.map((item) => item.decision.toJson()),
      second.cases.map((item) => item.decision.toJson()),
    );
    expect(first.answerSupportCount, 2);
    expect(second.answerSupportCount, 1);
  });

  test(
    'measures the predeclared finite sweep without selecting a candidate',
    () {
      final report = evaluateRag3AbstentionPolicySweep(
        fixture: _fixture(),
        run: Rag3CandidateRun.fromJson(_run()),
      );

      expect(report.reports.map((item) => item.policy.depth), [1, 3, 5]);
      expect(report.reports.first.answerSupportCount, 1);
      expect(report.reports[1].answerSupportCount, 2);
      expect(report.reports[1].abstentionSupportCount, 1);
      expect(report.reports[1].unavailableIrrelevantOnlyCount, 0);
      expect(report.toJson(), containsPair('candidateSelection', 'not_run'));
      expect(report.toJson(), containsPair('productionDecision', 'no_go'));
      expect(report.toJson(), containsPair('promotionFixtureAccessed', false));
    },
  );

  test('rejects promotion paths before reading any input', () async {
    final root = await Directory.systemTemp.createTemp(
      'rag3-abstention-reject-',
    );
    addTearDown(() => root.delete(recursive: true));
    final output = File('${root.path}/report.json');

    await expectLater(
      runRag3AbstentionPolicyInstrument(
        Rag3AbstentionPolicyInstrumentOptions(
          fixturePath: 'missing-fixture.json',
          oraclePath: 'missing-oracle.json',
          runPath: 'build/rag3_promotion/run.json',
          outPath: output.path,
        ),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('cannot use promotion artifacts'),
        ),
      ),
    );
    expect(output.existsSync(), isFalse);
  });

  test('parses the instrument CLI contract', () {
    final options = Rag3AbstentionPolicyInstrumentOptions.parse(const [
      '--fixture',
      'fixture.json',
      '--oracle',
      'oracle.json',
      '--run',
      'run.json',
      '--out',
      'report.json',
    ]);

    expect(options, isNotNull);
    expect(options!.outPath, 'report.json');
    expect(
      Rag3AbstentionPolicyInstrumentOptions.parse(const [
        '--fixture',
        'fixture.json',
      ]),
      isNull,
    );
  });
}

Rag3HybridFixture _fixture({String answerRole = 'answer_support'}) {
  final objects = {
    for (final id in const ['a', 'b', 'c'])
      'docs/$id.md': _object('docs/$id.md'),
  };
  final cases = <Map<String, Object?>>[
    _fixtureCase('answer-en', 'en', const ['answerable']),
    _fixtureCase('answer-ja', 'ja', const ['answerable']),
    _fixtureCase('abstention', 'en', const ['unavailable']),
    _fixtureCase('unavailable', 'en', const ['unavailable']),
  ];
  final oracleCases = <Map<String, Object?>>[
    _oracleCase(
      'answer-en',
      expectedRole: 'answer_support',
      qrelChunk: 'docs/a.md#1',
      passageRole: answerRole,
    ),
    _oracleCase(
      'answer-ja',
      expectedRole: 'answer_support',
      qrelChunk: 'docs/a.md#1',
      passageRole: 'answer_support',
    ),
    _oracleCase(
      'abstention',
      expectedRole: 'abstention_support',
      qrelChunk: 'docs/b.md#1',
      passageRole: 'abstention_support',
    ),
    _oracleCase('unavailable', expectedRole: 'no_evidence'),
  ];
  return Rag3HybridFixture.fromJson(
    fixtureJson: {
      'schemaName': rag3FixtureSchema,
      'schemaVersion': rag3SchemaVersion,
      'contractId': rag3ContractId,
      'fixtureId': 'rag3-abstention-instrument-test',
      'corpusHash': List.filled(64, 'a').join(),
      'selectionPolicy': const {
        'contextBudgetTokens': rag3ContextBudgetTokens,
        'maxGroupsPerObject': rag3MaxGroupsPerObject,
        'estimatedRunesPerToken': 4,
        'citationFormatVersion': 'rag3-citation-v1',
      },
      'negativeControls': const [
        {
          'id': 'empty-shuffled-fusion',
          'expectedOutcome': 'fails_quality_gate',
        },
        {
          'id': 'budget-bypass',
          'expectedOutcome': 'fails_zero_budget_violation_gate',
        },
      ],
      'cases': cases,
    },
    oracleJson: {
      'schemaName': rag3OracleSchema,
      'schemaVersion': rag3SchemaVersion,
      'contractId': rag3ContractId,
      'fixtureId': 'rag3-abstention-instrument-test',
      'corpusHash': List.filled(64, 'a').join(),
      'defaultPassageRole': 'irrelevant',
      'cases': oracleCases,
    },
    objects: objects,
  );
}

Map<String, Object?> _fixtureCase(
  String id,
  String language,
  List<String> strata,
) => {'id': id, 'language': language, 'shouldSearch': true, 'strata': strata};

Map<String, Object?> _oracleCase(
  String id, {
  required String expectedRole,
  String? qrelChunk,
  String? passageRole,
}) {
  final objectId = qrelChunk?.split('#').first;
  return {
    'id': id,
    'expectedEvidenceRole': expectedRole,
    'qrels': {
      'objects': objectId == null ? <String, int>{} : {objectId: 3},
      'chunks': qrelChunk == null ? <String, int>{} : {qrelChunk: 3},
    },
    'passageRoles': qrelChunk == null
        ? <String, String>{}
        : {qrelChunk: passageRole!},
  };
}

Rag3KnowledgeObject _object(String id) {
  final content = 'content for $id';
  final hash = sha256.convert(utf8.encode(content)).toString();
  return Rag3KnowledgeObject(
    id: id,
    sourcePath: id,
    revision: 'test-revision',
    objectContentHash: hash,
    sourceTrust: 'fixture_attested',
    authority: 'instrument',
    sourceLines: [content],
    chunks: [
      Rag3Chunk(
        id: '$id#1',
        objectId: id,
        lineStart: 1,
        lineEnd: 1,
        contentHash: hash,
      ),
    ],
  );
}

Map<String, Object?> _run() => {
  'schemaName': rag3RunSchema,
  'schemaVersion': rag3SchemaVersion,
  'runId': 'rag3-abstention-instrument-test-run',
  'contractId': rag3ContractId,
  'candidateId': rag3CandidateId,
  'fixtureId': 'rag3-abstention-instrument-test',
  'corpusHash': List.filled(64, 'a').join(),
  'metadata': const {
    'buildCommit': 'test-build',
    'buildDirty': false,
    'hardware': 'test-host',
    'warmState': 'cold',
    'tokenEstimateMethod': 'unicode_code_points_div_4_v1',
  },
  'cases': [
    _case(
      caseId: 'answer-en',
      lexical: const ['docs/a.md#1'],
      vector: const ['docs/b.md#1', 'docs/a.md#1'],
    ),
    _case(
      caseId: 'answer-ja',
      lexical: const ['docs/a.md#1'],
      vector: const ['docs/a.md#1'],
    ),
    _case(
      caseId: 'abstention',
      lexical: const ['docs/b.md#1'],
      vector: const ['docs/b.md#1'],
    ),
    _case(
      caseId: 'unavailable',
      lexical: const ['docs/c.md#1'],
      vector: const ['docs/b.md#1'],
    ),
  ],
};

Map<String, Object?> _case({
  required String caseId,
  required List<String> lexical,
  required List<String> vector,
  bool submitted = true,
  String vectorStatus = 'available',
}) => {
  'caseId': caseId,
  'submitted': submitted,
  'lexicalRankedChunkIds': lexical,
  'lexicalLatencyMs': 1,
  'vector': {
    'status': vectorStatus,
    'degradedReason': vectorStatus == 'available' ? null : 'not_available',
    'rankedChunkIds': vector,
    'validationReceipt': const {
      'finiteValues': true,
      'nonZeroMagnitude': true,
      'uniformDimensions': true,
      'fingerprintMatch': true,
    },
    'fingerprint': const {
      'schemaVersion': 1,
      'endpointIdentity': 'https://embedding.invalid/v1',
      'requestedModelId': 'instrument-model',
      'responseModelId': 'instrument-model',
      'dimension': 2,
    },
    'latencyMs': 1,
  },
  'resource': const {'peakRssBytes': 1024, 'peakVramBytes': 0},
};
