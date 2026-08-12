import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/personal_eval/data/personal_eval_authored_corpus.dart';
import 'package:caverno/features/personal_eval/domain/entities/personal_eval_case.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/personal_eval_authored_operator.dart';
import '../../tool/personal_eval_experiment_protocol.dart';

void main() {
  const protocolPath =
      'tool/personal_eval_corpus/reconstruction_expansion_protocol_config.json';
  const corpusPath = 'tool/personal_eval_corpus/corpus.json';
  const expectedCaseIds = {
    'authored_datekit_rebuild_parse',
    'authored_textkit_rebuild_slug',
    'authored_taskflow_rebuild_state_and_budget',
  };

  test('locks a balanced corpus-design protocol to the three new tasks', () {
    final protocol = PersonalEvalExperimentProtocol.fromJson(
      jsonDecode(File(protocolPath).readAsStringSync()) as Map<String, dynamic>,
      path: protocolPath,
    );

    expect(protocol.studyIntent, PersonalEvalStudyIntent.corpusDesign);
    expect(protocol.decisionCriteria, isNull);
    expect(protocol.trialOrders, hasLength(6));
    expect(
      protocol.trialOrders.map((trial) => trial.caseId).toSet(),
      expectedCaseIds,
    );
    expect(
      protocol.trialOrders.where(
        (trial) => trial.first == PersonalEvalModelRole.incumbent,
      ),
      hasLength(3),
    );
    expect(
      protocol.trialOrders.where(
        (trial) => trial.first == PersonalEvalModelRole.candidate,
      ),
      hasLength(3),
    );
    for (final caseId in expectedCaseIds) {
      final trials = protocol.trialOrders
          .where((trial) => trial.caseId == caseId)
          .toList(growable: false);
      expect(trials, hasLength(2), reason: caseId);
      expect(trials.map((trial) => trial.first).toSet(), {
        PersonalEvalModelRole.incumbent,
        PersonalEvalModelRole.candidate,
      }, reason: caseId);
    }
    expect(protocol.executionBudget.maxDurationMs, 900000);
    expect(protocol.executionBudget.maxTurns, 24);
    expect(protocol.executionBudget.maxToolCalls, 100);
  });

  test('targets only held-out reconstruction cases', () {
    final corpus = PersonalEvalAuthoredCorpus.parse(
      File(corpusPath).readAsStringSync(),
    );
    final selected = corpus.cases
        .where((evalCase) => expectedCaseIds.contains(evalCase.caseId))
        .toList(growable: false);

    expect(selected, hasLength(expectedCaseIds.length));
    for (final evalCase in selected) {
      expect(evalCase.split, PersonalEvalCaseSplit.heldOut);
      expect(evalCase.classifiedTier, greaterThanOrEqualTo(2));
      expect(evalCase.promptStyle, PersonalEvalPromptStyle.unguided);
    }
  });

  test('operator dry run writes exactly twelve pending events', () async {
    final outputDirectory = Directory.systemTemp.createTempSync(
      'personal-eval-reconstruction-expansion-plan-',
    );
    addTearDown(() => outputDirectory.deleteSync(recursive: true));
    final operator = await PersonalEvalAuthoredOperator.load(
      options: PersonalEvalAuthoredOperatorOptions(
        protocolPath: File(protocolPath).absolute.path,
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

    expect(result.totalEvents, 12);
    expect(result.completedEvents, 0);
    expect(events.map((event) => event['caseId']).toSet(), expectedCaseIds);
    for (final caseId in expectedCaseIds) {
      final caseEvents = events
          .where((event) => event['caseId'] == caseId)
          .toList(growable: false);
      expect(caseEvents, hasLength(4), reason: caseId);
      expect(caseEvents.map((event) => event['role']).toSet(), {
        'incumbent',
        'candidate',
      }, reason: caseId);
    }
    expect(checkpoint['completedCount'], 0);
    expect(
      (checkpoint['events'] as List).cast<Map<String, dynamic>>(),
      everyElement(containsPair('status', 'pending')),
    );
  });
}
