import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/rag2_post_answer_claim_eval.dart';
import '../../tool/rag2_relation_aware_claim_eval.dart';
import '../../tool/rag2_semantic_holdout_eval.dart';

void main() {
  const verifier = Rag2RelationAwareSemanticSupportVerifier();

  test('binds code, URL, boolean, and modal relations', () {
    expect(
      verifier
          .verify(
            claim: 'The initial retry limit is 9.',
            evidence: 'const defaultRetryAttemptLimit = 7;',
          )
          .verdict,
      Rag2ClaimVerdict.contradicted,
    );
    expect(
      verifier
          .verify(
            claim: 'The dashboard port is 8081.',
            evidence:
                'The dashboard is at https://localhost:7443. Its build number is 8081.',
          )
          .verdict,
      Rag2ClaimVerdict.contradicted,
    );
    expect(
      verifier
          .verify(
            claim: 'The callback port is 9443.',
            evidence:
                'The callback uses https://localhost/callback. Port 9443 belongs to another service.',
          )
          .verdict,
      Rag2ClaimVerdict.absent,
    );
    expect(
      verifier
          .verify(
            claim: 'Staging safeMode is enabled.',
            evidence: 'Staging safeMode is not not enabled.',
          )
          .verdict,
      Rag2ClaimVerdict.supported,
    );
    expect(
      verifier
          .verify(
            claim: 'Production safeMode is disabled.',
            evidence:
                'Production safeMode may be\n disabled during an incident.',
          )
          .verdict,
      Rag2ClaimVerdict.absent,
    );
  });

  test('compares v1 and v2 across both frozen suites', () async {
    final directory = Directory.systemTemp.createTempSync('rag2-relation-v2-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final report = await runRag2RelationComparison(_options(directory.path));

    expect(report.passed, isTrue);
    expect(report.v1Original.results, hasLength(3));
    expect(
      report.v1Original.results.map((item) => item.result.macroF1),
      everyElement(1.0),
    );
    expect(report.v1Holdout.result.result.macroF1, closeTo(0.672222, 0.000001));
    expect(
      report.v2Original.results.map((item) => item.result.macroF1),
      everyElement(1.0),
    );
    expect(report.v2Holdout.result.result.macroF1, 1.0);
    expect(report.toJson()['productionDecision'], 'no_go');
    expect(
      jsonDecode(
        File(
          '${directory.path}/rag2_relation_aware_claim_comparison.json',
        ).readAsStringSync(),
      ),
      report.toJson(),
    );
    expect(
      File(
        '${directory.path}/rag2_relation_aware_claim_comparison.md',
      ).readAsStringSync(),
      report.toMarkdown(),
    );
  });

  test(
    'fails closed when relation-aware verification is unavailable',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'rag2-relation-unavailable-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final report = await runRag2SemanticHoldoutEval(
        _options(directory.path).semanticOptions(directory.path),
        verifier: const Rag2RelationAwareSemanticSupportVerifier(
          available: false,
        ),
      );

      expect(report.passed, isFalse);
      expect(
        report.result.result.cases.every(
          (item) => item.predicted == Rag2ClaimVerdict.absent,
        ),
        isTrue,
      );
      expect(
        report.result.decisions.values.where(
          (item) => item.reason == 'semantic_verifier_unavailable',
        ),
        isNotEmpty,
      );
      expect(
        report.result.decisions.values
            .where((item) => item.reason != 'semantic_verifier_unavailable')
            .every(
              (item) =>
                  item.verifierDecision.verdict == Rag2ClaimVerdict.absent,
            ),
        isTrue,
      );
    },
  );
}

Rag2RelationComparisonOptions _options(
  String outDir,
) => Rag2RelationComparisonOptions(
  claimsPath: 'tool/fixtures/rag2_claim_verification/candidates.json',
  envelopesPath: 'tool/fixtures/rag2_claim_verification/claim_envelopes.json',
  authorityPath:
      'tool/fixtures/rag2_claim_verification/evidence_authority.json',
  seedFixturePath: 'tool/fixtures/rag_retrieval_eval/fixture.json',
  holdoutFixturePath: 'tool/fixtures/rag2_lexical_holdout/fixture.json',
  auditFixturePath: 'tool/fixtures/rag2_runtime_adversarial/fixture.json',
  semanticClaimsPath: 'tool/fixtures/rag2_semantic_holdout/claims.json',
  semanticEnvelopesPath: 'tool/fixtures/rag2_semantic_holdout/envelopes.json',
  semanticAuthorityPath: 'tool/fixtures/rag2_semantic_holdout/authority.json',
  semanticFixturePath: 'tool/fixtures/rag2_semantic_holdout/fixture.json',
  outDir: outDir,
);
