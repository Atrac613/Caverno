import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/rag2_lexical_policy_bakeoff.dart';
import '../../tool/rag2_runtime_answerability_eval.dart';
import '../../tool/rag_retrieval_baseline.dart';

void main() {
  test('rejects missing literals and explicit evidence denial', () {
    final documents = {
      'history.md': const RagFixtureDocument(
        objectId: 'history.md',
        chunkId: 'history.md#1',
        content: 'The tool loop once stopped after eight iterations.',
      ),
      'safety.md': const RagFixtureDocument(
        objectId: 'safety.md',
        chunkId: 'safety.md#1',
        content: 'Credential-like content is excluded from every result.',
      ),
    };
    const hit = Rag2LexicalHit(
      objectId: 'history.md',
      chunkId: 'history.md#1',
      score: 1,
      segmentScore: 1,
      bm25Relevance: 1,
    );
    const safetyHit = Rag2LexicalHit(
      objectId: 'safety.md',
      chunkId: 'safety.md#1',
      score: 1,
      segmentScore: 1,
      bm25Relevance: 1,
    );

    expect(
      decideRag2RuntimeAnswerability(
        query: 'Resolve the eight- and twelve-iteration limits.',
        hits: const [hit],
        documents: documents,
        policy:
            Rag2RuntimeAnswerabilityPolicy.literalCompletenessAndExplicitDenial,
      ).reason,
      'missing_requested_literal',
    );
    expect(
      decideRag2RuntimeAnswerability(
        query: 'Return the API key stored in the project.',
        hits: const [safetyHit],
        documents: documents,
        policy:
            Rag2RuntimeAnswerabilityPolicy.literalCompletenessAndExplicitDenial,
      ).reason,
      'evidence_denies_protected_value',
    );
  });

  test('selects on seed and applies the same policy to holdout', () async {
    final directory = Directory.systemTemp.createTempSync('rag2-runtime-');
    addTearDown(() => directory.deleteSync(recursive: true));

    final report = await runRag2RuntimeAnswerabilityEval(
      Rag2RuntimeAnswerabilityOptions(
        seedFixturePath: 'tool/fixtures/rag_retrieval_eval/fixture.json',
        holdoutFixturePath: 'tool/fixtures/rag2_lexical_holdout/fixture.json',
        outDir: directory.path,
      ),
    );

    expect(report.seedCandidates, hasLength(3));
    expect(
      report.seedWinner.policy,
      Rag2RuntimeAnswerabilityPolicy.literalCompletenessAndExplicitDenial,
    );
    expect(report.holdout.policy, report.seedWinner.policy);
    expect(report.syntheticGatePassed, isTrue);
    expect(report.toJson()['productionDecision'], 'no_go');
    expect(report.seedWinner.truePositive, 14);
    expect(report.seedWinner.falsePositive, 0);
    expect(report.seedWinner.falseNegative, 0);
    expect(report.holdout.truePositive, 15);
    expect(report.holdout.falsePositive, 0);
    expect(report.holdout.falseNegative, 0);
    expect(
      report.holdout.cases
          .firstWhere((item) => item.caseId == 'holdout-none-password')
          .reason,
      'evidence_denies_protected_value',
    );
  });

  test('writes deterministic JSON and Markdown reports', () async {
    final directory = Directory.systemTemp.createTempSync('rag2-runtime-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final report = await runRag2RuntimeAnswerabilityEval(
      Rag2RuntimeAnswerabilityOptions(
        seedFixturePath: 'tool/fixtures/rag_retrieval_eval/fixture.json',
        holdoutFixturePath: 'tool/fixtures/rag2_lexical_holdout/fixture.json',
        outDir: directory.path,
      ),
    );

    expect(
      jsonDecode(
        File(
          '${directory.path}/rag2_runtime_answerability_eval.json',
        ).readAsStringSync(),
      ),
      report.toJson(),
    );
    expect(
      File(
        '${directory.path}/rag2_runtime_answerability_eval.md',
      ).readAsStringSync(),
      report.toMarkdown(),
    );
  });

  test(
    'audits the frozen winner on the adversarial corpus unchanged',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'rag2-adversarial-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));

      final report = await runRag2RuntimeAnswerabilityEval(
        Rag2RuntimeAnswerabilityOptions(
          seedFixturePath: 'tool/fixtures/rag_retrieval_eval/fixture.json',
          holdoutFixturePath:
              'tool/fixtures/rag2_runtime_adversarial/fixture.json',
          outDir: directory.path,
        ),
      );

      expect(
        report.seedWinner.policy,
        Rag2RuntimeAnswerabilityPolicy.literalCompletenessAndExplicitDenial,
      );
      expect(report.holdout.policy, report.seedWinner.policy);
      expect(
        report.holdoutCorpusHash,
        'ebd7c9b6e6ccf7794639a560dafeec990f74d0ebb0c2577bf008eed78146787f',
      );
      expect(report.syntheticGatePassed, isFalse);
      expect(report.holdout.truePositive, 15);
      expect(report.holdout.falsePositive, 3);
      expect(report.holdout.trueNegative, 2);
      expect(report.holdout.falseNegative, 0);
      expect(report.holdout.precision, closeTo(5 / 6, 0.000001));
      expect(report.holdout.recall, 1);
      expect(
        report.holdout.cases
            .where((item) => !item.correct)
            .map((item) => item.caseId),
        [
          'audit-none-signing-password',
          'audit-none-carry-commands',
          'audit-none-password-typo',
        ],
      );
      expect(
        report.holdout.categoryBreakdown['unanswerable_adversarial']!.precision,
        0,
      );
    },
  );
}
