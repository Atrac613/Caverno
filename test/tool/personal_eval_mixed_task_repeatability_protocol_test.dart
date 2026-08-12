import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/personal_eval/data/personal_eval_authored_corpus.dart';
import 'package:caverno/features/personal_eval/domain/entities/personal_eval_case.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/personal_eval_authored_operator.dart';
import '../../tool/personal_eval_experiment_protocol.dart';

void main() {
  const protocolPath =
      'tool/personal_eval_corpus/mixed_task_repeatability_protocol_config.json';
  const baselineProtocolPath =
      'tool/personal_eval_corpus/reconstruction_expansion_protocol_config.json';
  const corpusPath = 'tool/personal_eval_corpus/corpus.json';
  const expectedCaseIds = {
    'authored_datekit_rebuild_parse',
    'authored_taskflow_rebuild_state_and_budget',
  };
  const lockedSourceDigests = {
    corpusPath:
        'b466c5d0cded15833697d306ea9a7035b1ba99575c4d3095d93ea52697c0af8a',
    'tool/personal_eval_corpus/fixtures/datekit/bin/verify.dart':
        'e48b8f554e1b21496e3216b8402f841ae17744c3619104a7850d4d1f204b4ff3',
    'tool/personal_eval_corpus/fixtures/datekit/src/duration_text.dart':
        'beec46fe005df6b53e2cb345af5a2f898a2330093489fc1728e0b91f450c7983',
    'tool/personal_eval_corpus/fixtures/datekit/seeds/'
            'authored_datekit_rebuild_parse/src/duration_text.dart':
        '9ada8ef07aab7ba0f376792e9a4b90e1e92ab55230f9d72d9a874e34ff57f3e9',
    'tool/personal_eval_corpus/fixtures/taskflow/bin/verify.dart':
        '3d824c286a31f038ef08a53f569e05dfcd376290a8553017699677857a6ce61c',
    'tool/personal_eval_corpus/fixtures/taskflow/src/retry_policy.dart':
        'ae7694cb04ed76efd6babe9ef41fdb411d9b76f7123ae7719d45fc346ef23171',
    'tool/personal_eval_corpus/fixtures/taskflow/src/task_state.dart':
        '16c8b6a2f1f8eb61176bd57411424c2ec68518429e9e40b33a4cdd59c9405ca5',
    'tool/personal_eval_corpus/fixtures/taskflow/seeds/'
            'authored_taskflow_rebuild_state_and_budget/src/retry_policy.dart':
        '123130831f00d37642b70617b5a0792bfa3a07a830cbbf94046b61006569aa82',
    'tool/personal_eval_corpus/fixtures/taskflow/seeds/'
            'authored_taskflow_rebuild_state_and_budget/src/task_state.dart':
        'f71a2cf01af003fd6d1da9e8090b4246f5f8868252cb28260fb72f4cc4458e3d',
  };

  test('locks the mixed tasks to new balanced trial identities', () {
    final protocol = _loadProtocol(protocolPath);
    final baseline = _loadProtocol(baselineProtocolPath);

    expect(protocol.studyIntent, PersonalEvalStudyIntent.corpusDesign);
    expect(protocol.decisionCriteria, isNull);
    expect(protocol.incumbent.toJson(), baseline.incumbent.toJson());
    expect(protocol.candidate.toJson(), baseline.candidate.toJson());
    expect(
      protocol.executionBudget.toJson(),
      baseline.executionBudget.toJson(),
    );
    expect(protocol.trialOrders, hasLength(4));
    expect(
      protocol.trialOrders.map((trial) => trial.caseId).toSet(),
      expectedCaseIds,
    );
    for (final caseId in expectedCaseIds) {
      final trials = protocol.trialOrders
          .where((trial) => trial.caseId == caseId)
          .toList(growable: false);
      expect(trials.map((trial) => trial.trialId).toSet(), {
        'trial-3',
        'trial-4',
      }, reason: caseId);
      expect(trials.map((trial) => trial.first).toSet(), {
        PersonalEvalModelRole.incumbent,
        PersonalEvalModelRole.candidate,
      }, reason: caseId);
    }
  });

  test('locks the selected corpus and fixture source state', () {
    for (final entry in lockedSourceDigests.entries) {
      expect(
        sha256.convert(File(entry.key).readAsBytesSync()).toString(),
        entry.value,
        reason: entry.key,
      );
    }

    final corpus = PersonalEvalAuthoredCorpus.parse(
      File(corpusPath).readAsStringSync(),
    );
    final selected = corpus.cases
        .where((evalCase) => expectedCaseIds.contains(evalCase.caseId))
        .toList(growable: false);
    expect(selected, hasLength(2));
    expect(selected.map((evalCase) => evalCase.classifiedTier).toSet(), {2, 3});
    for (final evalCase in selected) {
      expect(evalCase.split, PersonalEvalCaseSplit.heldOut);
      expect(evalCase.promptStyle, PersonalEvalPromptStyle.unguided);
    }
  });

  test('operator dry run writes the exact eight-event pending plan', () async {
    final outputDirectory = Directory.systemTemp.createTempSync(
      'personal-eval-mixed-task-repeatability-plan-',
    );
    addTearDown(() => outputDirectory.deleteSync(recursive: true));
    final protocolFile = File(protocolPath);
    final protocolDigest = sha256
        .convert(utf8.encode(protocolFile.readAsStringSync()))
        .toString();
    final operator = await PersonalEvalAuthoredOperator.load(
      options: PersonalEvalAuthoredOperatorOptions(
        protocolPath: protocolFile.absolute.path,
        corpusPath: File(corpusPath).absolute.path,
        outDir: outputDirectory.path,
        execute: false,
        resume: false,
        apiKey: 'no-key',
        maxEvents: null,
      ),
    );

    final result = await operator.run();
    final plan =
        jsonDecode(result.planFile.readAsStringSync()) as Map<String, dynamic>;
    final checkpoint =
        jsonDecode(result.checkpointFile.readAsStringSync())
            as Map<String, dynamic>;
    final events = (plan['events'] as List).cast<Map<String, dynamic>>();

    expect(result.totalEvents, 8);
    expect(result.completedEvents, 0);
    expect(plan['protocolSha256'], protocolDigest);
    expect(checkpoint['protocolSha256'], protocolDigest);
    expect(
      events
          .map(
            (event) =>
                '${event['caseId']}#${event['trialId']}#${event['role']}',
          )
          .toList(),
      const [
        'authored_datekit_rebuild_parse#trial-3#incumbent',
        'authored_datekit_rebuild_parse#trial-3#candidate',
        'authored_datekit_rebuild_parse#trial-4#candidate',
        'authored_datekit_rebuild_parse#trial-4#incumbent',
        'authored_taskflow_rebuild_state_and_budget#trial-3#incumbent',
        'authored_taskflow_rebuild_state_and_budget#trial-3#candidate',
        'authored_taskflow_rebuild_state_and_budget#trial-4#candidate',
        'authored_taskflow_rebuild_state_and_budget#trial-4#incumbent',
      ],
    );
    expect(checkpoint['completedCount'], 0);
    expect(
      (checkpoint['events'] as List).cast<Map<String, dynamic>>(),
      everyElement(containsPair('status', 'pending')),
    );
  });
}

PersonalEvalExperimentProtocol _loadProtocol(String path) {
  return PersonalEvalExperimentProtocol.fromJson(
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>,
    path: path,
  );
}
