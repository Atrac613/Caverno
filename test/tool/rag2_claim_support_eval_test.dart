import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/rag2_claim_support_eval.dart';

void main() {
  test(
    'keeps retrieval relevance separate from oracle claim support',
    () async {
      final directory = Directory.systemTemp.createTempSync('rag2-support-');
      addTearDown(() => directory.deleteSync(recursive: true));

      final report = await runRag2ClaimSupportEval(
        Rag2ClaimSupportOptions(
          seedFixturePath: 'tool/fixtures/rag_retrieval_eval/fixture.json',
          holdoutFixturePath: 'tool/fixtures/rag2_lexical_holdout/fixture.json',
          outDir: directory.path,
        ),
      );

      expect(report.toJson()['runtimeEligible'], isFalse);
      expect(report.seed.answerableCases, 16);
      expect(report.holdout.answerableCases, 16);
      expect(report.seed.noAnswerCases, 4);
      expect(report.holdout.noAnswerCases, 4);
      expect(report.seed.retrievalRelevantCases, 15);
      expect(report.seed.fullySupportedCases, 14);
      expect(report.seed.partialSupportCases, 1);
      expect(report.seed.absentSupportCases, 1);
      expect(report.seed.topicalButInsufficientCases, 2);
      expect(report.holdout.retrievalRelevantCases, 15);
      expect(report.holdout.fullySupportedCases, 15);
      expect(report.holdout.partialSupportCases, 0);
      expect(report.holdout.absentSupportCases, 1);
      expect(report.holdout.topicalButInsufficientCases, 2);
      expect(
        report.holdout.cases
            .where((item) => item.topicalButInsufficient)
            .map((item) => item.caseId),
        containsAll(['holdout-none-password', 'holdout-none-execute']),
      );
    },
  );

  test('writes deterministic JSON and Markdown reports', () async {
    final directory = Directory.systemTemp.createTempSync('rag2-support-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final options = Rag2ClaimSupportOptions(
      seedFixturePath: 'tool/fixtures/rag_retrieval_eval/fixture.json',
      holdoutFixturePath: 'tool/fixtures/rag2_lexical_holdout/fixture.json',
      outDir: directory.path,
    );

    final report = await runRag2ClaimSupportEval(options);

    expect(
      jsonDecode(
        File(
          '${directory.path}/rag2_claim_support_eval.json',
        ).readAsStringSync(),
      ),
      report.toJson(),
    );
    expect(
      File('${directory.path}/rag2_claim_support_eval.md').readAsStringSync(),
      report.toMarkdown(),
    );
  });
}
