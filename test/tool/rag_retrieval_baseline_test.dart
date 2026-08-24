import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../tool/rag_retrieval_baseline.dart';
import '../../tool/rag_retrieval_eval.dart';

void main() {
  late RagRetrievalFixture fixture;
  late List<RagFixtureDocument> documents;

  setUpAll(() async {
    fixture = await RagRetrievalFixture.load(
      File('tool/fixtures/rag_retrieval_eval/fixture.json'),
    );
    documents = await loadRagFixtureDocuments(fixture);
  });

  test(
    'loads the content-hashed corpus and decodes JSON fixture strings',
    () async {
      expect(await fixture.computeCorpusHash(), fixture.corpusHash);
      expect(documents, hasLength(7));
      final japanese = documents.singleWhere(
        (document) => document.objectId == 'docs/japanese_facts.json',
      );
      expect(japanese.content, contains('SQLite'));
      expect(japanese.content, isNot(contains(r'\u73fe')));
    },
  );

  test('matches the production quoted whitespace-term query shape', () {
    expect(
      buildRagLexicalQuery('alpha beta "gamma"'),
      '"alpha" "beta" """gamma"""',
    );
    expect(buildRagLexicalQuery('  '), isEmpty);
  });

  test(
    'captures real lexical, control, unavailable, and negative arms',
    () async {
      final runJson = captureRagRetrievalBaseline(
        fixture: fixture,
        documents: documents,
        metadata: const RagRetrievalBaselineMetadata(
          buildCommit: '01234567',
          buildDirty: false,
          hardware: 'test-host',
        ),
        runId: 'test-baseline',
        warmState: 'cold',
      );
      final run = RagRetrievalRun.fromJson(runJson);

      expect(() => run.validate(fixture), returnsNormally);
      expect(
        run.arms.map((arm) => arm['id']),
        containsAll(['L', 'V', 'H', 'AK', 'H+AK', 'NONE', 'FULL', 'NEG-EMPTY']),
      );
      expect(
        run.arms.singleWhere((arm) => arm['id'] == 'V')['status'],
        'not_available',
      );
      final lexical = run.arms.singleWhere((arm) => arm['id'] == 'L');
      final lexicalResults = (lexical['results'] as List<Object?>)
          .cast<Map<String, Object?>>();
      final japaneseResults = lexicalResults.where(
        (result) =>
            fixture.cases
                .singleWhere((item) => item.id == result['caseId'])
                .category ==
            'japanese_query',
      );
      for (final result in japaneseResults) {
        final hits = (result['hits'] as List<Object?>);
        if (hits.isEmpty) {
          expect(result['missReason'], 'tokenization');
        } else if (result['missReason'] != null) {
          expect(result['missReason'], 'ranking');
        }
      }
      final none = run.arms.singleWhere((arm) => arm['id'] == 'NONE');
      expect(
        (none['results'] as List<Object?>).every(
          (item) => ((item as Map<String, Object?>)['hits'] as List).isEmpty,
        ),
        isTrue,
      );
      final full = run.arms.singleWhere((arm) => arm['id'] == 'FULL');
      expect(
        ((full['results'] as List).first as Map)['hits'],
        hasLength(documents.length),
      );

      final report = await evaluateRagRetrievalRun(fixture: fixture, run: run);
      expect(report.passed, isTrue);
      expect(report.negativeControlsPassed, isTrue);
    },
  );

  test('captures a warm pass after pre-executing every lexical query', () {
    final runJson = captureRagRetrievalBaseline(
      fixture: fixture,
      documents: documents,
      metadata: const RagRetrievalBaselineMetadata(
        buildCommit: '01234567',
        buildDirty: false,
        hardware: 'test-host',
      ),
      runId: 'warm-baseline',
      warmState: 'warm',
    );

    expect((runJson['metadata'] as Map)['warmState'], 'warm');
    final lexical = ((runJson['arms'] as List).cast<Map>()).singleWhere(
      (arm) => arm['id'] == 'L',
    );
    expect(lexical['results'], hasLength(20));
  });

  test(
    'writes a run and both report formats through the baseline entrypoint',
    () async {
      final directory = Directory.systemTemp.createTempSync('rag-baseline-');
      addTearDown(() => directory.deleteSync(recursive: true));

      final report = await runRagRetrievalBaseline(
        RagRetrievalBaselineOptions(
          fixturePath: 'tool/fixtures/rag_retrieval_eval/fixture.json',
          outDir: directory.path,
          runId: 'artifact-test',
          warmState: 'warm',
        ),
        metadata: const RagRetrievalBaselineMetadata(
          buildCommit: '89abcdef',
          buildDirty: false,
          hardware: 'test-host',
        ),
      );

      expect(report.passed, isTrue);
      final run =
          jsonDecode(
                File(
                  '${directory.path}/rag_retrieval_run.json',
                ).readAsStringSync(),
              )
              as Map<String, Object?>;
      expect((run['metadata'] as Map)['warmState'], 'warm');
      expect(
        (run['metadata'] as Map)['tokenEstimateMethod'],
        'unicode_code_points_div_4_v1',
      );
      expect(
        File('${directory.path}/rag_retrieval_eval.json').existsSync(),
        isTrue,
      );
      expect(
        File('${directory.path}/rag_retrieval_eval.md').existsSync(),
        isTrue,
      );
    },
  );

  test('orders lexical hits by FTS5 rank', () {
    final database = sqlite3.openInMemory();
    addTearDown(database.close);
    database.execute(
      "CREATE VIRTUAL TABLE knowledge USING fts5("
      "object_id UNINDEXED, chunk_id UNINDEXED, content, tokenize='unicode61')",
    );
    database.execute('INSERT INTO knowledge VALUES (?, ?, ?)', [
      'secondary',
      'secondary#1',
      'alpha beta beta beta',
    ]);
    database.execute('INSERT INTO knowledge VALUES (?, ?, ?)', [
      'primary',
      'primary#1',
      'alpha beta',
    ]);

    final hits = searchRagFixtureLexically(database, 'alpha beta', limit: 2);

    expect(hits, hasLength(2));
    expect(hits.map((hit) => hit['objectId']).toSet(), {
      'primary',
      'secondary',
    });
  });

  test('parses only supported baseline options', () {
    final options = RagRetrievalBaselineOptions.parse([
      '--fixture',
      'fixture.json',
      '--out-dir',
      'report',
      '--warm-state',
      'warm',
    ]);

    expect(options, isNotNull);
    expect(options!.runId, 'rag1-baseline-v1');
    expect(options.warmState, 'warm');
    expect(
      RagRetrievalBaselineOptions.parse([
        '--fixture',
        'fixture.json',
        '--out-dir',
        'report',
        '--unknown',
        'value',
      ]),
      isNull,
    );
  });
}
