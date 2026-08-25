import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/rag2_authority_claim_eval.dart';

void main() {
  test('selects the requested authority and highest revision', () {
    const evidence = [
      Rag2AuthorityEvidence(
        objectId: 'current-old',
        content: 'Current old.',
        authority: Rag2EvidenceAuthority.current,
        revision: 1,
      ),
      Rag2AuthorityEvidence(
        objectId: 'current-new',
        content: 'Current new.',
        authority: Rag2EvidenceAuthority.current,
        revision: 3,
      ),
      Rag2AuthorityEvidence(
        objectId: 'history',
        content: 'History.',
        authority: Rag2EvidenceAuthority.historical,
        revision: 2,
      ),
    ];

    final current = selectRag2AuthorityEvidence(
      claim: 'The current value is new.',
      query: 'What is the value now?',
      evidence: evidence,
    );
    final historical = selectRag2AuthorityEvidence(
      claim: 'The former value was old.',
      query: 'What did the prototype use?',
      evidence: evidence,
    );

    expect(current.evidence.single.objectId, 'current-new');
    expect(historical.evidence.single.objectId, 'history');
  });

  test('evaluates the frozen verifier with authority metadata', () async {
    final directory = Directory.systemTemp.createTempSync('rag2-authority-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final report = await runRag2AuthorityClaimEval(
      Rag2AuthorityClaimOptions(
        claimsPath: 'tool/fixtures/rag2_claim_verification/candidates.json',
        authorityPath:
            'tool/fixtures/rag2_claim_verification/evidence_authority.json',
        seedFixturePath: 'tool/fixtures/rag_retrieval_eval/fixture.json',
        holdoutFixturePath: 'tool/fixtures/rag2_lexical_holdout/fixture.json',
        auditFixturePath: 'tool/fixtures/rag2_runtime_adversarial/fixture.json',
        outDir: directory.path,
      ),
    );

    expect(report.results, hasLength(3));
    expect(report.toJson()['productionDecision'], 'no_go');
    expect(report.passed, isFalse);
    expect(report.results[0].baseline.macroF1, closeTo(0.757936, 0.000001));
    expect(
      report.results[0].authorityAware.macroF1,
      closeTo(0.666667, 0.000001),
    );
    expect(report.results[1].baseline.macroF1, closeTo(0.674603, 0.000001));
    expect(
      report.results[1].authorityAware.macroF1,
      closeTo(0.838095, 0.000001),
    );
    expect(report.results[2].baseline.macroF1, closeTo(0.542424, 0.000001));
    expect(
      report.results[2].authorityAware.macroF1,
      closeTo(0.672222, 0.000001),
    );
    expect(
      report.results.every(
        (item) => identical(
          item.authorityAware.policy,
          rag2FrozenClaimVerifierPolicy,
        ),
      ),
      isTrue,
    );
    expect(
      jsonDecode(
        File(
          '${directory.path}/rag2_authority_claim_eval.json',
        ).readAsStringSync(),
      ),
      report.toJson(),
    );
    expect(
      File('${directory.path}/rag2_authority_claim_eval.md').readAsStringSync(),
      report.toMarkdown(),
    );
  });
}
