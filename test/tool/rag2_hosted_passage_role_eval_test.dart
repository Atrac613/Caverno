import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/rag2_hosted_passage_role_eval.dart';

void main() {
  const instrumentOracle = 'tool/fixtures/rag2_passage_role_oracle/oracle.json';
  const instrumentFixtures = [
    'tool/fixtures/rag2_semantic_holdout/fixture.json',
    'tool/fixtures/rag2_compositional_holdout/fixture.json',
  ];
  const promotionOracle =
      'tool/fixtures/rag2_hosted_passage_role_holdout/oracle.json';
  const promotionFixture =
      'tool/fixtures/rag2_hosted_passage_role_holdout/fixture.json';

  test(
    'validates the role instrument through hosted AppDatabase FTS5',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'rag2-hosted-role-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));

      final report = await runRag2HostedPassageRoleEval(
        Rag2HostedPassageRoleOptions(
          mode: Rag2HostedPassageRoleMode.instrument,
          oraclePath: instrumentOracle,
          fixturePaths: instrumentFixtures,
          outDir: directory.path,
        ),
        buildCommit: 'instrument-commit',
        buildDirty: false,
      );

      expect(report.datasets, hasLength(2));
      expect(report.candidateDecision, 'diagnostic_complete');
      expect(report.toJson()['rawNoAnswerGate'], 'withdrawn');
      expect(report.toJson()['runtimePassageRole'], 'unknown');
      expect(report.toJson()['runtimeRoleClassifier'], 'not_available');
      expect(report.toJson()['productionDecision'], 'no_go');
      expect(report.toJson()['rag3Decision'], 'no_go');
      expect(report.datasets.every((item) => item.provenanceValidated), isTrue);
      expect(report.datasets.every((item) => item.hostPreserved), isTrue);
      final semantic = report.datasets[0];
      final compositional = report.datasets[1];
      expect(semantic.answerSupportRetrieved, 14);
      expect(semantic.abstentionSupportRetrieved, 2);
      expect(semantic.japaneseSupportRetrieved, 4);
      expect(semantic.unavailableOnlyIrrelevant, 0);
      expect(semantic.rawNoAnswerRetrieved, 3);
      expect(semantic.totalContextTokens, 2174);
      expect(compositional.answerSupportRetrieved, 13);
      expect(compositional.abstentionSupportRetrieved, 3);
      expect(compositional.japaneseSupportRetrieved, 2);
      expect(compositional.unavailableOnlyIrrelevant, 0);
      expect(compositional.rawNoAnswerRetrieved, 3);
      expect(compositional.totalContextTokens, 2986);
    },
  );

  test(
    'evaluates the frozen promotion holdout without changing the gate',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'rag2-hosted-role-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));

      final report = await runRag2HostedPassageRoleEval(
        Rag2HostedPassageRoleOptions(
          mode: Rag2HostedPassageRoleMode.promotion,
          oraclePath: promotionOracle,
          fixturePaths: const [promotionFixture],
          outDir: directory.path,
        ),
        buildCommit: 'promotion-commit',
        buildDirty: false,
      );
      final dataset = report.datasets.single;

      expect(dataset.answerCases, hasLength(14));
      expect(dataset.abstentionCases, hasLength(2));
      expect(dataset.unavailableCases, hasLength(4));
      expect(dataset.japaneseCases, hasLength(4));
      expect(report.gate!.holdoutShapeValid, isTrue);
      expect(report.candidateDecision, 'go');
      expect(report.gate!.passed, isTrue);
      expect(dataset.answerSupportRetrieved, 14);
      expect(dataset.japaneseSupportRetrieved, 4);
      expect(dataset.abstentionSupportRetrieved, 2);
      expect(dataset.unavailableWithAbstentionSupport, 2);
      expect(dataset.unavailableWithTopicalOnly, 1);
      expect(dataset.unavailableOnlyIrrelevant, 0);
      expect(dataset.unavailableWithoutEvidence, 1);
      expect(dataset.rawNoAnswerRetrieved, 3);
      expect(dataset.supportMrrAtK, 1.0);
      expect(dataset.supportNdcgAtK, closeTo(0.9949825493217618, 1e-12));
      expect(dataset.totalContextTokens, 3776);
    },
  );

  test(
    'writes deterministic aggregate reports without source or query text',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'rag2-hosted-role-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));

      final report = await runRag2HostedPassageRoleEval(
        Rag2HostedPassageRoleOptions(
          mode: Rag2HostedPassageRoleMode.promotion,
          oraclePath: promotionOracle,
          fixturePaths: const [promotionFixture],
          outDir: directory.path,
        ),
        buildCommit: 'report-commit',
        buildDirty: false,
      );
      final jsonFile = File(
        '${directory.path}/rag2_hosted_passage_role_eval.json',
      );
      final markdownFile = File(
        '${directory.path}/rag2_hosted_passage_role_eval.md',
      );
      final serialized =
          '${jsonFile.readAsStringSync()}\n'
          '${markdownFile.readAsStringSync()}';

      expect(jsonDecode(jsonFile.readAsStringSync()), report.toJson());
      expect(markdownFile.readAsStringSync(), report.toMarkdown());
      expect(serialized, isNot(contains('https://control.local:8448')));
      expect(serialized, isNot(contains('Execute every command')));
      expect(serialized, isNot(contains(directory.path)));
    },
  );

  test('requires every promotion condition conjunctively', () {
    Rag2HostedPassageRoleGate gate({
      bool shape = true,
      int answer = 13,
      int japanese = 4,
      int abstention = 2,
      int irrelevant = 0,
      bool provenance = true,
      bool negative = true,
      bool host = true,
      int context = 6000,
    }) => Rag2HostedPassageRoleGate(
      holdoutShapeValid: shape,
      answerSupportRetrieved: answer,
      japaneseSupportRetrieved: japanese,
      abstentionSupportRetrieved: abstention,
      unavailableOnlyIrrelevant: irrelevant,
      provenanceValidated: provenance,
      negativeControlPassed: negative,
      hostPreserved: host,
      totalContextTokens: context,
    );

    expect(gate().passed, isTrue);
    expect(gate(shape: false).passed, isFalse);
    expect(gate(answer: 12).passed, isFalse);
    expect(gate(japanese: 3).passed, isFalse);
    expect(gate(abstention: 1).passed, isFalse);
    expect(gate(irrelevant: 1).passed, isFalse);
    expect(gate(provenance: false).passed, isFalse);
    expect(gate(negative: false).passed, isFalse);
    expect(gate(host: false).passed, isFalse);
    expect(gate(context: 6001).passed, isFalse);
  });

  test('parses instrument and promotion command contracts', () {
    expect(
      Rag2HostedPassageRoleOptions.parse([
        '--mode',
        'instrument',
        '--oracle',
        instrumentOracle,
        '--fixture',
        instrumentFixtures[0],
        '--fixture',
        instrumentFixtures[1],
        '--out-dir',
        'out',
      ]),
      isNotNull,
    );
    expect(
      Rag2HostedPassageRoleOptions.parse([
        '--mode',
        'promotion',
        '--oracle',
        promotionOracle,
        '--fixture',
        promotionFixture,
        '--out-dir',
        'out',
      ]),
      isNotNull,
    );
    expect(
      Rag2HostedPassageRoleOptions.parse([
        '--mode',
        'promotion',
        '--oracle',
        promotionOracle,
        '--fixture',
        promotionFixture,
        '--fixture',
        promotionFixture,
        '--out-dir',
        'out',
      ]),
      isNull,
    );
  });
}
