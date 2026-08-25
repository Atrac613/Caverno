import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/rag2_post_answer_claim_eval.dart';
import '../../tool/rag2_semantic_holdout_eval.dart';

void main() {
  test('audits the frozen semantic verifier on independent controls', () async {
    final directory = Directory.systemTemp.createTempSync(
      'rag2-semantic-holdout-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final report = await runRag2SemanticHoldoutEval(
      Rag2SemanticHoldoutOptions(
        claimsPath: 'tool/fixtures/rag2_semantic_holdout/claims.json',
        envelopesPath: 'tool/fixtures/rag2_semantic_holdout/envelopes.json',
        authorityPath: 'tool/fixtures/rag2_semantic_holdout/authority.json',
        fixturePath: 'tool/fixtures/rag2_semantic_holdout/fixture.json',
        outDir: directory.path,
      ),
    );

    expect(report.verifierId, 'deterministic-atomic-facts-v1');
    expect(report.result.result.cases, hasLength(12));
    expect(report.passed, isFalse);
    expect(report.result.result.macroF1, closeTo(0.672222, 0.000001));
    expect(
      report.result.result.metrics[Rag2ClaimVerdict.supported]!.f1,
      closeTo(0.6, 0.000001),
    );
    expect(
      report.result.result.metrics[Rag2ClaimVerdict.contradicted]!.f1,
      closeTo(0.75, 0.000001),
    );
    expect(
      report.result.result.metrics[Rag2ClaimVerdict.absent]!.f1,
      closeTo(2 / 3, 0.000001),
    );
    expect(
      report.result.result.cases
          .where((item) => !item.correct)
          .map((item) => item.candidateId),
      [
        'semantic-supported-double-negative',
        'semantic-contradicted-unrelated-number',
        'semantic-absent-unassigned-port',
        'semantic-absent-modal-state',
      ],
    );
    expect(report.toJson()['productionDecision'], 'no_go');
    expect(
      jsonDecode(
        File(
          '${directory.path}/rag2_semantic_holdout_eval.json',
        ).readAsStringSync(),
      ),
      report.toJson(),
    );
    expect(
      File(
        '${directory.path}/rag2_semantic_holdout_eval.md',
      ).readAsStringSync(),
      report.toMarkdown(),
    );
  });
}
