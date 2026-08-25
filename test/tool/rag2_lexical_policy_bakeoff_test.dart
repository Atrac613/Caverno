import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/rag2_lexical_policy_bakeoff.dart';
import '../../tool/rag_retrieval_baseline.dart';

void main() {
  test('tokenizes words and Unicode character n-grams', () {
    expect(tokenizeRag2Lexical('Alpha beta', Rag2LexicalPolicy.word), {
      'alpha',
      'beta',
    });
    expect(tokenizeRag2Lexical('保存先', Rag2LexicalPolicy.bigram), {'保存', '存先'});
    expect(tokenizeRag2Lexical('保存先', Rag2LexicalPolicy.trigram), {'保存先'});
  });

  test('ranks shared rare terms before partial generic overlap', () {
    final scorer = Rag2LexicalScorer(
      policy: Rag2LexicalPolicy.word,
      documents: const [
        RagFixtureDocument(
          objectId: 'a',
          chunkId: 'a#1',
          content: 'common rareterm',
        ),
        RagFixtureDocument(
          objectId: 'b',
          chunkId: 'b#1',
          content: 'common only',
        ),
      ],
    );
    addTearDown(scorer.close);

    final hits = scorer.rank('common rareterm', limit: 2);

    expect(hits.map((item) => item.objectId), ['a', 'b']);
    expect(hits.first.score, 1);
    expect(hits.first.segmentScore, 1);
    expect(hits.first.bm25Relevance, greaterThan(0));
    expect(hits.last.score, lessThan(1));
  });

  test('prefers a gate-passing candidate over higher unsafe recall', () {
    final safe = _candidate(answerableHits: 15, noAnswerRetrieved: 1);
    final unsafe = _candidate(answerableHits: 16, noAnswerRetrieved: 4);
    final candidates = [unsafe, safe]..sort(compareRag2LexicalCandidates);

    expect(candidates.first, same(safe));
  });

  test('writes deterministic JSON and Markdown artifacts', () async {
    final directory = Directory.systemTemp.createTempSync('rag2-lexical-');
    addTearDown(() => directory.deleteSync(recursive: true));

    final report = await runRag2LexicalBakeoff(
      Rag2LexicalBakeoffOptions(
        fixturePath: 'tool/fixtures/rag_retrieval_eval/fixture.json',
        outDir: directory.path,
      ),
    );

    final jsonFile = File('${directory.path}/rag2_lexical_policy_bakeoff.json');
    final markdownFile = File(
      '${directory.path}/rag2_lexical_policy_bakeoff.md',
    );
    expect(jsonDecode(jsonFile.readAsStringSync()), report.toJson());
    expect(markdownFile.readAsStringSync(), report.toMarkdown());
    expect(report.candidates, hasLength(39));
  });
}

Rag2LexicalCandidateResult _candidate({
  required int answerableHits,
  required int noAnswerRetrieved,
}) => Rag2LexicalCandidateResult(
  policy: Rag2LexicalPolicy.word,
  threshold: 0.2,
  answerableHits: answerableHits,
  noAnswerRetrieved: noAnswerRetrieved,
  mrr: 1,
  category: const {},
  authority: const {},
  cases: const [],
);
