import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/rag_answer_baseline.dart';
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

  test('builds a stable fact catalog and evidence-scoped prompt', () {
    final catalog = buildRagFactCatalog(fixture);
    final run = captureRagRetrievalBaseline(
      fixture: fixture,
      documents: documents,
      metadata: const RagRetrievalBaselineMetadata(
        buildCommit: 'test',
        buildDirty: false,
        hardware: 'test',
      ),
      runId: 'test',
      warmState: 'cold',
    );
    final full = (run['arms'] as List).cast<Map>().singleWhere(
      (item) => item['id'] == 'FULL',
    );
    final prompt = buildRagAnswerPrompt(
      fixture: fixture,
      documents: documents,
      results: (full['results'] as List).cast<Map<String, Object?>>(),
      factCatalog: catalog,
    );

    expect(catalog, hasLength(14));
    expect(prompt, contains('current-default-model'));
    expect(prompt, contains('lib/runtime_defaults.dart#1'));
  });

  test('scores selected facts and citations against the answer key', () {
    final catalog = buildRagFactCatalog(fixture);
    final fixtureCase = fixture.cases.first;
    final factId = catalog.entries
        .singleWhere((entry) => entry.value == fixtureCase.answerFacts.first)
        .key;
    final results = [
      for (final item in fixture.cases)
        {'caseId': item.id, 'hits': <Object?>[]},
    ];
    final selections = [
      for (final item in fixture.cases)
        RagAnswerSelection(
          caseId: item.id,
          factIds: item.id == fixtureCase.id ? [factId] : const [],
          citations: item.id == fixtureCase.id
              ? fixtureCase.citations
              : const [],
        ),
    ];

    applyRagAnswerSelections(
      fixture: fixture,
      results: results,
      selections: selections,
      factCatalog: catalog,
      promptTokens: 100,
      completionTokens: 20,
      latencyMs: 5,
    );

    expect(results.first['answerEvaluation'], {
      'groundedClaims': 1,
      'totalClaims': 1,
      'validCitations': 1,
      'totalCitations': 1,
    });
    expect(results.first['promptTokens'], 120);
    expect(results.first['latencyMs'], 5);
  });
}
