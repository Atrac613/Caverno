import 'dart:convert';

import 'package:caverno/features/personal_eval/domain/entities/personal_eval_case.dart';
import 'package:caverno/features/personal_eval/domain/services/personal_eval_replay_orchestrator.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRunner implements PersonalEvalCaseRunner {
  _FakeRunner(this._outcomes);

  final Map<String, PersonalEvalCaseRunOutcome> _outcomes;
  final List<String> ranCaseIds = [];

  @override
  Future<PersonalEvalCaseRunOutcome> run(PersonalEvalCase evalCase) async {
    ranCaseIds.add(evalCase.caseId);
    final outcome = _outcomes[evalCase.caseId];
    if (outcome == null) {
      throw StateError('no outcome configured for ${evalCase.caseId}');
    }
    return outcome;
  }
}

void main() {
  const orchestrator = PersonalEvalReplayOrchestrator();

  PersonalEvalCase evalCase(
    String id, {
    PersonalEvalCaseSplit split = PersonalEvalCaseSplit.heldIn,
  }) {
    return PersonalEvalCase(
      caseId: id,
      prompt: 'p',
      repoStateRef: 'r',
      consentGranted: true,
      split: split,
    );
  }

  String completeLog() => jsonEncode({
    'operation': 'chat',
    'durationMs': 90,
    'request': {'messages': []},
    'response': {'content': 'Done.', 'finishReason': 'stream_end'},
  });

  test('runs every case and assembles the run with summaries', () async {
    final runner = _FakeRunner({
      'a': PersonalEvalCaseRunOutcome(
        verificationResult: PersonalEvalVerificationResult.passed,
        sessionLogContents: completeLog(),
        logPath: '/replay/a.jsonl',
      ),
      'b': const PersonalEvalCaseRunOutcome(
        verificationResult: PersonalEvalVerificationResult.failed,
        sessionLogContents: '',
      ),
    });

    final run = await orchestrator.run(
      label: 'candidate',
      model: 'qwen-test',
      cases: [
        evalCase('a'),
        evalCase('b', split: PersonalEvalCaseSplit.heldOut),
      ],
      runner: runner,
    );

    expect(runner.ranCaseIds, ['a', 'b']);
    expect(run.caseCount, 2);
    expect(run.passedCount, 1);
    expect(run.failedCount, 1);
    expect(run.model, 'qwen-test');

    final caseA = run.cases.firstWhere((c) => c.caseId == 'a');
    expect(caseA.logPath, '/replay/a.jsonl');
    expect(caseA.summary.result, 'complete');
    expect(caseA.summary.totalDurationMs, 90);
    expect(run.casesForSplit(PersonalEvalCaseSplit.heldOut).single.caseId, 'b');
  });

  test(
    'a throwing runner yields an inconclusive case, not an aborted run',
    () async {
      final runner = _FakeRunner({
        'a': PersonalEvalCaseRunOutcome(
          verificationResult: PersonalEvalVerificationResult.passed,
          sessionLogContents: completeLog(),
        ),
        // 'crash' has no configured outcome -> runner throws.
      });

      final run = await orchestrator.run(
        label: 'candidate',
        cases: [evalCase('a'), evalCase('crash')],
        runner: runner,
      );

      expect(run.caseCount, 2);
      final crashed = run.cases.firstWhere((c) => c.caseId == 'crash');
      expect(
        crashed.verificationResult,
        PersonalEvalVerificationResult.inconclusive,
      );
      expect(crashed.error, contains('no outcome configured'));
      // The healthy case still recorded its result.
      expect(run.passedCount, 1);
    },
  );
}
