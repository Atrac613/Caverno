import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/rag2_evidence_sufficiency_eval.dart';
import '../../tool/rag2_lexical_policy_bakeoff.dart';

void main() {
  test('computes a bounded BM25 margin', () {
    expect(rag2Bm25Margin(const []), 0);
    expect(rag2Bm25Margin([_hit(2)]), 1);
    expect(rag2Bm25Margin([_hit(2), _hit(1)]), 0.5);
  });

  test('writes a seed-selected and holdout-frozen report', () async {
    final directory = Directory.systemTemp.createTempSync('rag2-sufficiency-');
    addTearDown(() => directory.deleteSync(recursive: true));

    final report = await runRag2EvidenceSufficiency(
      Rag2EvidenceSufficiencyOptions(
        seedFixturePath: 'tool/fixtures/rag_retrieval_eval/fixture.json',
        holdoutFixturePath: 'tool/fixtures/rag2_lexical_holdout/fixture.json',
        outDir: directory.path,
      ),
    );

    final jsonFile = File(
      '${directory.path}/rag2_evidence_sufficiency_eval.json',
    );
    final markdownFile = File(
      '${directory.path}/rag2_evidence_sufficiency_eval.md',
    );
    expect(jsonDecode(jsonFile.readAsStringSync()), report.toJson());
    expect(markdownFile.readAsStringSync(), report.toMarkdown());
    expect(report.candidates, hasLength(100));
    expect(report.holdoutResult.policy, same(report.seedWinner.policy));
    expect(report.holdoutResult.answerableCases, 16);
    expect(report.holdoutResult.noAnswerCases, 4);
    expect(
      report.holdoutCorpusHash,
      'e5b9f6a7a9616afb7a8db42d625f3849da33e3a7c24880fd4c53c0c3c7e834c3',
    );
  });
}

Rag2LexicalHit _hit(double relevance) => Rag2LexicalHit(
  objectId: 'object-$relevance',
  chunkId: 'chunk-$relevance',
  score: 1,
  segmentScore: 1,
  bm25Relevance: relevance,
);
