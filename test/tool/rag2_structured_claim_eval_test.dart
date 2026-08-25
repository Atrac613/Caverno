import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/rag2_authority_claim_eval.dart';
import '../../tool/rag2_structured_claim_eval.dart';

void main() {
  test('fails closed for missing, mismatched, and superseded citations', () {
    const current = Rag2AuthorityEvidence(
      objectId: 'current.md',
      content: 'The current limit is 12.',
      authority: Rag2EvidenceAuthority.current,
      revision: 3,
    );
    const old = Rag2AuthorityEvidence(
      objectId: 'old.md',
      content: 'The old limit is 8.',
      authority: Rag2EvidenceAuthority.historical,
      revision: 1,
    );
    const newerHistory = Rag2AuthorityEvidence(
      objectId: 'newer-history.md',
      content: 'The later old limit is 10.',
      authority: Rag2EvidenceAuthority.historical,
      revision: 2,
    );

    expect(
      verifyRag2StructuredClaim(
        claim: 'Any claim.',
        envelope: const Rag2ClaimEnvelope(
          candidateId: 'missing',
          scope: Rag2ClaimScope.unspecified,
          citedSourceIds: [],
        ),
        retrievedEvidence: const [current],
      ).reason,
      'missing_citation',
    );
    expect(
      verifyRag2StructuredClaim(
        claim: 'The old limit is 8.',
        envelope: const Rag2ClaimEnvelope(
          candidateId: 'mismatch',
          scope: Rag2ClaimScope.current,
          citedSourceIds: ['old.md'],
        ),
        retrievedEvidence: const [old],
      ).reason,
      'authority_mismatch',
    );
    expect(
      verifyRag2StructuredClaim(
        claim: 'The old limit is 8.',
        envelope: const Rag2ClaimEnvelope(
          candidateId: 'superseded',
          scope: Rag2ClaimScope.historical,
          citedSourceIds: ['old.md'],
        ),
        retrievedEvidence: const [old, newerHistory],
      ).reason,
      'superseded_revision',
    );
  });

  test('evaluates all fixed structured claim envelopes', () async {
    final directory = Directory.systemTemp.createTempSync('rag2-structured-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final report = await runRag2StructuredClaimEval(
      Rag2StructuredClaimOptions(
        claimsPath: 'tool/fixtures/rag2_claim_verification/candidates.json',
        envelopesPath:
            'tool/fixtures/rag2_claim_verification/claim_envelopes.json',
        authorityPath:
            'tool/fixtures/rag2_claim_verification/evidence_authority.json',
        seedFixturePath: 'tool/fixtures/rag_retrieval_eval/fixture.json',
        holdoutFixturePath: 'tool/fixtures/rag2_lexical_holdout/fixture.json',
        auditFixturePath: 'tool/fixtures/rag2_runtime_adversarial/fixture.json',
        outDir: directory.path,
      ),
    );

    expect(report.results, hasLength(3));
    expect(
      report.results.every((item) => item.result.cases.length == 12),
      isTrue,
    );
    expect(report.toJson()['productionDecision'], 'no_go');
    expect(report.passed, isFalse);
    expect(report.results[0].result.macroF1, closeTo(0.838095, 0.000001));
    expect(report.results[1].result.macroF1, closeTo(0.915344, 0.000001));
    expect(report.results[2].result.macroF1, closeTo(0.915344, 0.000001));
    expect(report.results[0].result.meetsGate, isFalse);
    expect(report.results[1].result.meetsGate, isTrue);
    expect(report.results[2].result.meetsGate, isTrue);
    expect(
      report.results
          .expand((item) => item.result.cases)
          .where((item) => !item.correct)
          .map((item) => item.candidateId),
      [
        'seed-supported-loop',
        'seed-contradicted-loop',
        'holdout-supported-mcp',
        'audit-contradicted-safe-mode',
      ],
    );
    expect(
      jsonDecode(
        File(
          '${directory.path}/rag2_structured_claim_eval.json',
        ).readAsStringSync(),
      ),
      report.toJson(),
    );
    expect(
      File(
        '${directory.path}/rag2_structured_claim_eval.md',
      ).readAsStringSync(),
      report.toMarkdown(),
    );
  });
}
