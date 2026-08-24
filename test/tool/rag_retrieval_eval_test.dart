import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/rag_retrieval_eval.dart';

void main() {
  late RagRetrievalFixture fixture;

  setUpAll(() async {
    fixture = await RagRetrievalFixture.load(
      File('tool/fixtures/rag_retrieval_eval/fixture.json'),
    );
  });

  test(
    'loads the versioned 20-case seed and verifies its corpus hash',
    () async {
      fixture.validate();

      expect(fixture.cases, hasLength(20));
      expect(await fixture.computeCorpusHash(), fixture.corpusHash);
      expect(
        fixture.cases.map((fixtureCase) => fixtureCase.category).toSet(),
        containsAll({
          'current_source',
          'historical_decision',
          'cross_source_conflict',
          'japanese_query',
          'unanswerable_adversarial',
        }),
      );
      expect(
        fixture.cases.map((fixtureCase) => fixtureCase.authority).toSet(),
        containsAll({'current', 'historical', 'conflict', 'none'}),
      );
    },
  );

  test('computes recall, hit rate, reciprocal rank, and nDCG at K', () {
    final metrics = RetrievalMetrics.compute(
      ranking: ['irrelevant', 'secondary', 'primary'],
      relevance: {'primary': 3, 'secondary': 1},
      k: 3,
    );

    expect(metrics.scorable, isTrue);
    expect(metrics.recallAtK, 1);
    expect(metrics.hitAtK, 1);
    expect(metrics.mrrAtK, closeTo(0.5, 0.000001));
    expect(metrics.ndcgAtK, closeTo(0.5869, 0.001));
  });

  test(
    'reports unavailable arms separately and detects an empty control',
    () async {
      final run = RagRetrievalRun.fromJson(_buildRunJson(fixture));

      final report = await evaluateRagRetrievalRun(fixture: fixture, run: run);

      expect(report.passed, isTrue);
      expect(report.negativeControlsPassed, isTrue);
      expect(report.evaluatedArmsPassed, isTrue);
      final vector = report.arms.singleWhere((arm) => arm['id'] == 'V');
      expect(vector['status'], 'not_available');
      expect(vector['aggregate'], isNull);
      final lexical = report.arms.singleWhere((arm) => arm['id'] == 'L');
      final lexicalAggregate = (lexical['aggregate'] as Map)
          .cast<String, Object?>();
      expect(lexicalAggregate['objectHitAtK'], 1);
      expect(lexicalAggregate['unanswerableFalsePositiveRate'], 0);
      expect(lexicalAggregate['answerableHitCount'], 16);
      expect(lexicalAggregate['answerableCaseCount'], 16);
      expect(lexicalAggregate['unanswerableCaseCount'], 4);
      expect(lexicalAggregate['unanswerableRetrievedCount'], 0);
      expect(lexicalAggregate['categoryBreakdown'], isNotEmpty);
      expect(lexicalAggregate['authorityBreakdown'], isNotEmpty);
      expect(report.toJson()['schemaVersion'], 1);
      expect(report.toMarkdown(), contains('not_available'));
      expect(report.toMarkdown(), contains('16/16'));
      expect(report.toMarkdown(), contains('L diagnostics'));
    },
  );

  test('fails when the known-bad arm is no longer detected as bad', () async {
    final json = _buildRunJson(fixture);
    final arms = (json['arms'] as List<Object?>).cast<Map<String, Object?>>();
    final negative = arms.singleWhere((arm) => arm['id'] == 'NEG-EMPTY');
    negative['results'] = _perfectResults(fixture);
    final run = RagRetrievalRun.fromJson(json);

    final report = await evaluateRagRetrievalRun(fixture: fixture, run: run);

    expect(report.negativeControlsPassed, isFalse);
    expect(report.passed, isFalse);
  });

  test('requires every unavailable arm to carry a reason', () {
    final json = _buildRunJson(fixture);
    final arms = (json['arms'] as List<Object?>).cast<Map<String, Object?>>();
    arms.singleWhere((arm) => arm['id'] == 'AK').remove('unavailableReason');
    final run = RagRetrievalRun.fromJson(json);

    expect(() => run.validate(fixture), throwsFormatException);
  });

  test('requires Japanese lexical misses to name tokenizer or ranking', () {
    final json = _buildRunJson(fixture);
    final arms = (json['arms'] as List<Object?>).cast<Map<String, Object?>>();
    final lexical = arms.singleWhere((arm) => arm['id'] == 'L');
    final results = (lexical['results'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final japanese = results.firstWhere(
      (result) => result['caseId'] == 'ja-current-storage',
    );
    japanese['hits'] = <Object?>[];
    final run = RagRetrievalRun.fromJson(json);

    expect(() => run.validate(fixture), throwsStateError);

    japanese['missReason'] = 'tokenization';
    final attributedRun = RagRetrievalRun.fromJson(json);
    expect(() => attributedRun.validate(fixture), returnsNormally);
  });

  test('rejects run metadata that cannot reproduce the measurement', () {
    final json = _buildRunJson(fixture);
    (json['metadata'] as Map<String, Object?>).remove('warmState');
    final run = RagRetrievalRun.fromJson(json);

    expect(() => run.validate(fixture), throwsStateError);
  });

  test('parses the command-line contract', () {
    final options = RagRetrievalEvalOptions.parse([
      '--fixture',
      'fixture.json',
      '--run',
      'run.json',
      '--out-dir',
      'reports',
    ]);

    expect(options, isNotNull);
    expect(options!.fixturePath, 'fixture.json');
    expect(options.runPath, 'run.json');
    expect(options.outDir, 'reports');
    expect(
      RagRetrievalEvalOptions.parse(['--fixture', 'fixture.json']),
      isNull,
    );
  });

  test('writes deterministic JSON and Markdown report artifacts', () async {
    final directory = Directory.systemTemp.createTempSync('rag-eval-report-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final runFile = File('${directory.path}/run.json')
      ..writeAsStringSync(jsonEncode(_buildRunJson(fixture)));
    final outDirectory = Directory('${directory.path}/report');

    final report = await runRagRetrievalEval(
      RagRetrievalEvalOptions(
        fixturePath: 'tool/fixtures/rag_retrieval_eval/fixture.json',
        runPath: runFile.path,
        outDir: outDirectory.path,
      ),
    );

    expect(report.passed, isTrue);
    final jsonReport = File('${outDirectory.path}/rag_retrieval_eval.json');
    final markdownReport = File('${outDirectory.path}/rag_retrieval_eval.md');
    expect(jsonReport.existsSync(), isTrue);
    expect(markdownReport.existsSync(), isTrue);
    expect(jsonDecode(jsonReport.readAsStringSync()), report.toJson());
    expect(markdownReport.readAsStringSync(), report.toMarkdown());
  });
}

Map<String, Object?> _buildRunJson(RagRetrievalFixture fixture) =>
    jsonDecode(
          jsonEncode({
            'schemaName': ragRetrievalRunSchema,
            'schemaVersion': ragRetrievalSchemaVersion,
            'runId': 'test-run',
            'fixtureId': fixture.fixtureId,
            'metadata': {
              'buildCommit': '01234567',
              'buildDirty': false,
              'embeddingFingerprint': 'not_available',
              'hardware': 'test-host',
              'warmState': 'cold',
              'tokenEstimateMethod': 'test_exact',
            },
            'arms': [
              _availableArm('L', _perfectResults(fixture), minimumHitAtK: 1),
              _unavailableArm('V', 'No embedding endpoint configured.'),
              _unavailableArm('H', 'Vector arm is unavailable.'),
              _unavailableArm('AK', 'agent-kb is not running.'),
              _unavailableArm('H+AK', 'Federation is unavailable.'),
              _availableArm('NONE', _emptyResults(fixture)),
              _availableArm('FULL', _perfectResults(fixture), minimumHitAtK: 1),
              _availableArm(
                'NEG-EMPTY',
                _emptyResults(fixture),
                minimumHitAtK: 0.5,
                negativeControl: true,
              ),
            ],
          }),
        )
        as Map<String, Object?>;

Map<String, Object?> _availableArm(
  String id,
  List<Map<String, Object?>> results, {
  double minimumHitAtK = 0,
  bool negativeControl = false,
}) => {
  'id': id,
  'status': 'available',
  'negativeControl': negativeControl,
  'minimumHitAtK': minimumHitAtK,
  'resource': {'peakRssBytes': 1024, 'peakVramBytes': null},
  'results': results,
};

Map<String, Object?> _unavailableArm(String id, String reason) => {
  'id': id,
  'status': 'not_available',
  'unavailableReason': reason,
  'results': <Object?>[],
};

List<Map<String, Object?>> _perfectResults(RagRetrievalFixture fixture) => [
  for (final fixtureCase in fixture.cases)
    {
      'caseId': fixtureCase.id,
      'hits': fixtureCase.objectRelevance.isEmpty
          ? <Object?>[]
          : [
              for (
                var index = 0;
                index < fixtureCase.objectRelevance.length;
                index++
              )
                {
                  'objectId': fixtureCase.objectRelevance.keys.elementAt(index),
                  'chunkId': fixtureCase.chunkRelevance.keys.elementAt(index),
                },
            ],
      'answerEvaluation': {
        'groundedClaims': fixtureCase.answerFacts.length,
        'totalClaims': fixtureCase.answerFacts.length,
        'validCitations': fixtureCase.citations.length,
        'totalCitations': fixtureCase.citations.length,
      },
      'latencyMs': 2,
      'promptTokens': 10,
      'contextTokens': 20,
    },
];

List<Map<String, Object?>> _emptyResults(RagRetrievalFixture fixture) => [
  for (final fixtureCase in fixture.cases)
    {
      'caseId': fixtureCase.id,
      'hits': <Object?>[],
      'latencyMs': 1,
      'promptTokens': 0,
      'contextTokens': 0,
      if (fixtureCase.category == 'japanese_query')
        'missReason': 'tokenization',
    },
];
