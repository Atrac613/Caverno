import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/rag3_instrument_eval.dart';

void main() {
  test('requires one RAG1 fixture and two RAG2 fixtures', () {
    expect(
      Rag3InstrumentEvalOptions.parse(const [
        '--rag1-fixture',
        'rag1.json',
        '--rag2-fixture',
        'semantic.json',
        '--rag2-fixture',
        'compositional.json',
        '--passage-role-oracle',
        'oracle.json',
        '--out-dir',
        'out',
      ]),
      isNotNull,
    );
    expect(
      Rag3InstrumentEvalOptions.parse(const [
        '--rag1-fixture',
        'rag1.json',
        '--rag2-fixture',
        'semantic.json',
        '--passage-role-oracle',
        'oracle.json',
        '--out-dir',
        'out',
      ]),
      isNull,
    );
  });

  test('rejects promotion inputs before reading them', () async {
    final output = await Directory.systemTemp.createTemp(
      'rag3-instrument-reject-',
    );
    addTearDown(() => output.delete(recursive: true));
    final options = Rag3InstrumentEvalOptions(
      rag1FixturePath: 'tool/fixtures/rag3_offline_hybrid_holdout/fixture.json',
      rag2FixturePaths: const ['semantic.json', 'compositional.json'],
      passageRoleOraclePath: 'oracle.json',
      outDir: output.path,
    );

    await expectLater(
      runRag3InstrumentEval(
        options,
        buildCommit: 'test-build',
        buildDirty: false,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('cannot use promotion artifacts'),
        ),
      ),
    );
  });

  test(
    'adapts inspected RAG1 and RAG2 rankings without promotion data',
    () async {
      final output = await Directory.systemTemp.createTemp('rag3-instrument-');
      addTearDown(() => output.delete(recursive: true));
      final report = await runRag3InstrumentEval(
        Rag3InstrumentEvalOptions(
          rag1FixturePath: 'tool/fixtures/rag_retrieval_eval/fixture.json',
          rag2FixturePaths: const [
            'tool/fixtures/rag2_semantic_holdout/fixture.json',
            'tool/fixtures/rag2_compositional_holdout/fixture.json',
          ],
          passageRoleOraclePath:
              'tool/fixtures/rag2_passage_role_oracle/oracle.json',
          outDir: output.path,
        ),
        buildCommit: 'test-build',
        buildDirty: false,
      );

      expect(report.instrumentValidated, isTrue);
      expect(report.datasets, hasLength(3));
      expect(report.toJson(), containsPair('promotionFixtureAccessed', false));
      expect(report.toJson(), containsPair('promotionDecision', 'not_run'));
      expect(report.toJson(), containsPair('productionDecision', 'no_go'));

      final rag1 = report.datasets[0];
      final semantic = report.datasets[1];
      final compositional = report.datasets[2];
      expect(rag1.passageRoleOracleApplied, isFalse);
      expect(semantic.passageRoleOracleApplied, isTrue);
      expect(compositional.passageRoleOracleApplied, isTrue);
      expect(rag1.report.passed, isFalse);
      expect(semantic.report.passed, isTrue);
      expect(compositional.report.passed, isFalse);
      expect(semantic.report.core.answerSupportCount, 14);
      expect(semantic.report.core.answerSupportCases, 14);
      expect(semantic.report.core.japaneseSupportCount, 4);
      expect(semantic.report.core.abstentionSupportCount, 2);
      expect(compositional.report.core.answerSupportCount, 13);
      expect(compositional.report.core.abstentionSupportCount, 3);
      for (final dataset in report.datasets) {
        expect(dataset.report.deterministicReplayPassed, isTrue);
        expect(
          dataset.report.core.hybridMetrics.objectRecallAt10,
          dataset.report.core.lexicalMetrics.objectRecallAt10,
        );
        expect(
          dataset.report.core.cases.every(
            (item) =>
                item.status == 'degraded' &&
                item.degradedReason == rag3InstrumentVectorReason,
          ),
          isTrue,
        );
      }

      final combinedOutput = await File(
        '${output.path}/rag3_instrument_eval.json',
      ).readAsString();
      expect(combinedOutput, isNot(contains('What is the default model?')));
      expect(combinedOutput, isNot(contains('initial retry attempt limit')));
      expect(combinedOutput, isNot(contains('rag3_offline_hybrid_holdout')));

      final semanticRun =
          (jsonDecode(
                    await File(
                      '${output.path}/rag2-semantic-holdout-v1/'
                      'rag3_instrument_run.json',
                    ).readAsString(),
                  )
                  as Map)
              .cast<String, Object?>();
      final cases = (semanticRun['cases'] as List).cast<Map>();
      expect(
        cases.every((item) {
          final vector = item['vector'] as Map;
          return vector['status'] == 'not_available' &&
              vector['degradedReason'] == rag3InstrumentVectorReason &&
              (vector['rankedChunkIds'] as List).isEmpty;
        }),
        isTrue,
      );
    },
  );
}
