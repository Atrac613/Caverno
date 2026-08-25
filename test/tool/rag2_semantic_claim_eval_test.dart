import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/rag2_post_answer_claim_eval.dart';
import '../../tool/rag2_semantic_claim_eval.dart';
import '../../tool/rag2_structured_claim_eval.dart';

void main() {
  const verifier = Rag2DeterministicSemanticSupportVerifier();

  test('normalizes code, URL ports, and negated boolean state', () {
    expect(
      verifier
          .verify(
            claim: 'The initial tool-loop limit is 12.',
            evidence: 'const defaultToolLoopIterations = 12;',
          )
          .verdict,
      Rag2ClaimVerdict.supported,
    );
    expect(
      verifier
          .verify(
            claim: 'The initial tool-loop limit is 99.',
            evidence: 'const defaultToolLoopIterations = 12;',
          )
          .verdict,
      Rag2ClaimVerdict.contradicted,
    );
    expect(
      verifier
          .verify(
            claim: 'The default MCP port is 8081.',
            evidence: 'The MCP endpoint defaults to http://localhost:8081.',
          )
          .verdict,
      Rag2ClaimVerdict.supported,
    );
    expect(
      verifier
          .verify(
            claim: 'safeMode is currently disabled.',
            evidence: 'The safeMode feature is not disabled.',
          )
          .verdict,
      Rag2ClaimVerdict.contradicted,
    );
  });

  test('fails closed when the semantic verifier is unavailable', () async {
    final directory = Directory.systemTemp.createTempSync(
      'rag2-semantic-unavailable-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final report = await runRag2SemanticClaimEval(
      _options(directory.path),
      verifier: const Rag2DeterministicSemanticSupportVerifier(
        available: false,
      ),
    );

    expect(report.verifierAvailable, isFalse);
    expect(report.passed, isFalse);
    expect(
      report.results
          .expand((item) => item.decisions.values)
          .where(
            (item) => item.reason == 'semantic_verifier_unavailable',
          )
          .length,
      24,
    );
    expect(
      report.results
          .expand((item) => item.result.cases)
          .every((item) => item.predicted == Rag2ClaimVerdict.absent),
      isTrue,
    );
  });

  test('evaluates all fixed claims deterministically', () async {
    final directory = Directory.systemTemp.createTempSync('rag2-semantic-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final report = await runRag2SemanticClaimEval(_options(directory.path));

    expect(report.results, hasLength(3));
    expect(
      report.results.every((item) => item.result.cases.length == 12),
      isTrue,
    );
    expect(report.toJson()['productionDecision'], 'no_go');
    expect(report.passed, isTrue);
    expect(
      report.results.map((item) => item.result.macroF1),
      everyElement(1.0),
    );
    expect(
      report.results
          .expand((item) => item.result.cases)
          .where((item) => !item.correct),
      isEmpty,
    );
    expect(
      jsonDecode(
        File(
          '${directory.path}/rag2_semantic_claim_eval.json',
        ).readAsStringSync(),
      ),
      report.toJson(),
    );
    expect(
      File(
        '${directory.path}/rag2_semantic_claim_eval.md',
      ).readAsStringSync(),
      report.toMarkdown(),
    );
  });
}

Rag2StructuredClaimOptions _options(String outDir) =>
    Rag2StructuredClaimOptions(
      claimsPath: 'tool/fixtures/rag2_claim_verification/candidates.json',
      envelopesPath:
          'tool/fixtures/rag2_claim_verification/claim_envelopes.json',
      authorityPath:
          'tool/fixtures/rag2_claim_verification/evidence_authority.json',
      seedFixturePath: 'tool/fixtures/rag_retrieval_eval/fixture.json',
      holdoutFixturePath: 'tool/fixtures/rag2_lexical_holdout/fixture.json',
      auditFixturePath: 'tool/fixtures/rag2_runtime_adversarial/fixture.json',
      outDir: outDir,
    );
