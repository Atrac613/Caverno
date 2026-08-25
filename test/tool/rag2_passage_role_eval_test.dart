import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/rag2_passage_role_eval.dart';

void main() {
  const oraclePath = 'tool/fixtures/rag2_passage_role_oracle/oracle.json';
  const fixturePaths = [
    'tool/fixtures/rag2_semantic_holdout/fixture.json',
    'tool/fixtures/rag2_compositional_holdout/fixture.json',
  ];

  test('re-scores frozen retrieval with all four passage roles', () async {
    final directory = Directory.systemTemp.createTempSync('rag2-role-');
    addTearDown(() => directory.deleteSync(recursive: true));

    final report = await runRag2PassageRoleEval(
      Rag2PassageRoleOptions(
        oraclePath: oraclePath,
        fixturePaths: fixturePaths,
        outDir: directory.path,
      ),
    );

    expect(report.toJson()['rankingChanged'], isFalse);
    expect(report.toJson()['runtimeRoleClassifier'], 'not_available');
    expect(report.toJson()['typedFactsDecision'], 'close_as_diagnostic');
    expect(report.toJson()['productionDecision'], 'no_go');
    expect(report.datasets, hasLength(2));
    expect(report.datasets[0].returnedRoleCounts, {
      'answer_support': 17,
      'abstention_support': 2,
      'topical_only': 8,
      'irrelevant': 1,
    });
    expect(report.datasets[1].returnedRoleCounts, {
      'answer_support': 14,
      'abstention_support': 3,
      'topical_only': 13,
      'irrelevant': 1,
    });
  });

  test('separates answer, abstention, and unavailable cases', () async {
    final directory = Directory.systemTemp.createTempSync('rag2-role-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final report = await runRag2PassageRoleEval(
      Rag2PassageRoleOptions(
        oraclePath: oraclePath,
        fixturePaths: fixturePaths,
        outDir: directory.path,
      ),
    );
    final semantic = report.datasets[0];
    final compositional = report.datasets[1];

    expect(semantic.answerCases, 14);
    expect(semantic.abstentionCases, 2);
    expect(semantic.unavailableCases, 4);
    expect(compositional.answerCases, 13);
    expect(compositional.abstentionCases, 3);
    expect(compositional.unavailableCases, 4);
    expect(semantic.answerSupportRetrieved, 14);
    expect(semantic.abstentionSupportRetrieved, 1);
    expect(compositional.answerSupportRetrieved, 13);
    expect(compositional.abstentionSupportRetrieved, 3);
    expect(semantic.unavailableWithAbstentionSupport, 1);
    expect(compositional.unavailableWithAbstentionSupport, 0);
  });

  test('writes deterministic reports', () async {
    final directory = Directory.systemTemp.createTempSync('rag2-role-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final report = await runRag2PassageRoleEval(
      Rag2PassageRoleOptions(
        oraclePath: oraclePath,
        fixturePaths: fixturePaths,
        outDir: directory.path,
      ),
    );

    expect(
      jsonDecode(
        File(
          '${directory.path}/rag2_passage_role_eval.json',
        ).readAsStringSync(),
      ),
      report.toJson(),
    );
    expect(
      File('${directory.path}/rag2_passage_role_eval.md').readAsStringSync(),
      report.toMarkdown(),
    );
  });

  test('rejects a corpus hash mismatch', () async {
    final source = jsonDecode(File(oraclePath).readAsStringSync()) as Map;
    final datasets = source['datasets'] as List;
    (datasets.first as Map)['corpusHash'] = 'wrong';
    final directory = Directory.systemTemp.createTempSync('rag2-role-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final oracle = File('${directory.path}/oracle.json')
      ..writeAsStringSync(jsonEncode(source));

    expect(
      () => runRag2PassageRoleEval(
        Rag2PassageRoleOptions(
          oraclePath: oracle.path,
          fixturePaths: fixturePaths,
          outDir: directory.path,
        ),
      ),
      throwsA(isA<StateError>()),
    );
  });
}
