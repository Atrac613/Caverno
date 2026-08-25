import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/rag2_compositional_holdout_eval.dart';
import '../../tool/rag2_post_answer_claim_eval.dart';
import '../../tool/rag2_relation_aware_claim_eval.dart';
import '../../tool/rag2_semantic_holdout_eval.dart';

void main() {
  test('compares frozen v1 and v2 on compositional controls', () async {
    final directory = Directory.systemTemp.createTempSync(
      'rag2-compositional-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final report = await runRag2CompositionalHoldoutComparison(
      _options(directory.path),
    );

    expect(report.passed, isFalse);
    expect(report.v1.verifierId, 'deterministic-atomic-facts-v1');
    expect(report.v2.verifierId, 'relation-aware-atomic-facts-v2');
    expect(report.v1.result.result.cases, hasLength(12));
    expect(report.v2.result.result.cases, hasLength(12));
    expect(report.v1.result.result.macroF1, closeTo(0.153846, 0.000001));
    expect(report.v2.result.result.macroF1, closeTo(0.327778, 0.000001));
    expect(
      report.v2.result.result.cases
          .where((item) => !item.correct)
          .map((item) => item.candidateId),
      [
        'composition-supported-api-port',
        'composition-supported-default-port',
        'composition-contradicted-report-format',
        'composition-contradicted-preview-state',
        'composition-contradicted-worker-mode',
        'composition-absent-production-condition',
        'composition-absent-backup-norm',
        'composition-absent-owner',
      ],
    );
    expect(report.toJson()['productionDecision'], 'no_go');
    expect(
      jsonDecode(
        File(
          '${directory.path}/rag2_compositional_holdout_comparison.json',
        ).readAsStringSync(),
      ),
      report.toJson(),
    );
    expect(
      File(
        '${directory.path}/rag2_compositional_holdout_comparison.md',
      ).readAsStringSync(),
      report.toMarkdown(),
    );
  });

  test(
    'keeps compositional verification fail closed when unavailable',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'rag2-compositional-unavailable-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final report = await runRag2SemanticHoldoutEval(
        _options(directory.path),
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
    },
  );
}

Rag2SemanticHoldoutOptions _options(String outDir) =>
    Rag2SemanticHoldoutOptions(
      claimsPath: 'tool/fixtures/rag2_compositional_holdout/claims.json',
      envelopesPath: 'tool/fixtures/rag2_compositional_holdout/envelopes.json',
      authorityPath: 'tool/fixtures/rag2_compositional_holdout/authority.json',
      fixturePath: 'tool/fixtures/rag2_compositional_holdout/fixture.json',
      outDir: outDir,
    );
