import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/rag2_post_answer_claim_eval.dart';

void main() {
  test('distinguishes numeric contradiction from absent evidence', () {
    const policy = Rag2ClaimVerifierPolicy(
      supportThreshold: 0.8,
      contradictionThreshold: 0.5,
    );
    expect(
      verifyRag2Claim(
        claim: 'The current limit is 99 tokens.',
        evidence: 'The current limit is 12 tokens.',
        policy: policy,
      ).verdict,
      Rag2ClaimVerdict.contradicted,
    );
    expect(
      verifyRag2Claim(
        claim: 'The maintainer is Alice.',
        evidence: '',
        policy: policy,
      ).verdict,
      Rag2ClaimVerdict.absent,
    );
  });

  test('selects on seed and applies one policy to both audits', () async {
    final directory = Directory.systemTemp.createTempSync('rag2-claims-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final report = await runRag2PostAnswerClaimEval(
      Rag2PostAnswerClaimOptions(
        claimsPath: 'tool/fixtures/rag2_claim_verification/candidates.json',
        seedFixturePath: 'tool/fixtures/rag_retrieval_eval/fixture.json',
        holdoutFixturePath: 'tool/fixtures/rag2_lexical_holdout/fixture.json',
        auditFixturePath: 'tool/fixtures/rag2_runtime_adversarial/fixture.json',
        outDir: directory.path,
      ),
    );

    expect(report.seedCandidates, hasLength(9));
    expect(report.audits, hasLength(2));
    expect(
      report.audits.every((item) => item.policy == report.seedWinner.policy),
      isTrue,
    );
    expect(report.toJson()['productionDecision'], 'no_go');
    expect(report.seedWinner.policy.supportThreshold, 0.9);
    expect(report.seedWinner.policy.contradictionThreshold, 0.5);
    expect(report.seedWinner.macroF1, closeTo(0.757936, 0.000001));
    expect(report.audits[0].macroF1, closeTo(0.674603, 0.000001));
    expect(report.audits[1].macroF1, closeTo(0.542424, 0.000001));
    expect(report.passed, isFalse);
    expect(
      report.audits[0].cases
          .where((item) => !item.correct)
          .map((item) => item.candidateId),
      contains('holdout-contradicted-tokens'),
    );
    expect(
      report.audits[1].cases
          .where((item) => !item.correct)
          .map((item) => item.candidateId),
      contains('audit-contradicted-safe-mode'),
    );
    expect(
      jsonDecode(
        File(
          '${directory.path}/rag2_post_answer_claim_eval.json',
        ).readAsStringSync(),
      ),
      report.toJson(),
    );
    expect(
      File(
        '${directory.path}/rag2_post_answer_claim_eval.md',
      ).readAsStringSync(),
      report.toMarkdown(),
    );
  });
}
