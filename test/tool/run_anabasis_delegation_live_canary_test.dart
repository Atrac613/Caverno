import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/test_support/plan_mode_scenario_spec.dart';

void main() {
  test('the scenario the runner names exists and holds the queue open', () {
    final scenario = buildLivePlanModeScenarios().singleWhere(
      (candidate) => candidate.name == 'live_anabasis_delegation_admission',
    );

    // A scenario that waits for execution, or does not stop it, observes the
    // queue after its tasks are worked -- which is always empty.
    expect(scenario.waitForExecutionCompletion, isFalse);
    // Starting execution closes the only window in which a chained plan has a
    // delegatable task, so the plan must reach the parent approved and
    // unworked.
    expect(scenario.startExecutionAfterApproval, isFalse);
    expect(scenario.followUpPrompt, isNotNull);
    expect(scenario.followUpPrompt, startsWith('@anabasis'));
    expect(scenario.savedWorkflowExpectation?.minTaskCount, isNotNull);
    // The queue size must be recorded, because the runner's verdict reads it.
    expect(
      scenario.logExpectations.map((expectation) => expectation.pattern),
      contains('[Scenario] Delegation queue offers'),
    );
    // And delegation must NOT be asserted here: whether the queue is non-empty
    // depends on the plan the model wrote, so failing the scenario on it would
    // blame the parent for a plan shape.
    expect(
      scenario.logExpectations.map((expectation) => expectation.pattern),
      isNot(contains('[Subagent] Spawning')),
    );
  });

  test('a follow-up prompt is opt-in, so other scenarios are unchanged', () {
    final others = buildLivePlanModeScenarios().where(
      (candidate) => candidate.name != 'live_anabasis_delegation_admission',
    );

    expect(others, isNotEmpty);
    for (final scenario in others) {
      expect(scenario.followUpPrompt, isNull, reason: scenario.name);
      expect(
        scenario.cancelExecutionBeforeFollowUp,
        isFalse,
        reason: scenario.name,
      );
      expect(
        scenario.startExecutionAfterApproval,
        isTrue,
        reason: scenario.name,
      );
      expect(
        scenario.resolveOpenQuestionsBeforeFollowUp,
        isFalse,
        reason: scenario.name,
      );
    }
  });
  test('the Anabasis canary runs the queue-holding scenario headless', () {
    final runner = File(
      'tool/run_anabasis_delegation_live_canary.sh',
    ).readAsStringSync();

    expect(
      runner,
      contains(
        'CAVERNO_PLAN_MODE_SCENARIOS=live_anabasis_delegation_admission',
      ),
    );
    expect(runner, contains('CAVERNO_PLAN_MODE_DEVICE=headless'));
    expect(runner, contains('CAVERNO_SESSION_LOG_DIR'));
    expect(runner, contains('tool/run_plan_mode_live_test.sh'));
  });

  test('it decides the Anabasis half from this run\'s own session logs', () {
    final runner = File(
      'tool/run_anabasis_delegation_live_canary.sh',
    ).readAsStringSync();

    // Pointing check_fix_firings.py at the default corpus would let an
    // unrelated historical log decide this run, so --dir must carry the run's
    // own log root.
    expect(
      runner,
      contains('check_fix_firings.py" --dir "\${SESSION_LOG_ROOT}'),
    );
    expect(runner, contains(r'^\[FIRED\] anabasis_delegation_admitted'));
  });

  test('an empty queue is inconclusive, not a failure', () {
    final runner = File(
      'tool/run_anabasis_delegation_live_canary.sh',
    ).readAsStringSync();

    // Only a queue that was offered and not taken may exit 1. Reporting an
    // empty one as a regression blames the parent for a plan shape.
    expect(runner, contains('exit 77'));
    expect(runner, contains('inconclusive'));
    expect(runner.indexOf('exit 77'), lessThan(runner.lastIndexOf('exit 1')));
  });

  test('the scenario may fail without skipping the verdict', () {
    final runner = File(
      'tool/run_anabasis_delegation_live_canary.sh',
    ).readAsStringSync();

    // pipefail would abort on the scenario's own failure, which is exactly the
    // run the three-way verdict exists to classify.
    expect(runner, contains('set +e'));
    expect(runner, contains(r'PIPESTATUS[0]'));
    expect(runner.indexOf('set +e'), lessThan(runner.indexOf('exit 77')));
  });

  test('acceptance is reported but never gated', () {
    final runner = File(
      'tool/run_anabasis_delegation_live_canary.sh',
    ).readAsStringSync();

    // Delegation is the one thing a run can demand. Whether the parent also
    // records a judgement depends on a longer chain the canary does not
    // control, so gating on it would retire a working gate for a model's
    // pacing -- but a run that stopped short has to say why.
    expect(runner, contains('anabasis_acceptance_recorded'));
    expect(runner, contains('Acceptance recorded:'));
    expect(runner, contains('Acceptance refused with:'));
    expect(runner, contains('never attempted an acceptance'));
    final acceptIndex = runner.indexOf('ACCEPTED=0');
    expect(acceptIndex, isNonNegative);
    expect(runner.indexOf('exit 1', acceptIndex), isNot(acceptIndex + 1));
  });

  test('the follow-up asks for the outcome, not for the tool name', () {
    final scenario = buildLivePlanModeScenarios().singleWhere(
      (candidate) => candidate.name == 'live_anabasis_delegation_admission',
    );

    // A probe that names the mechanism measures its own wording: a capable
    // model once scored 0/30 for six runs because the prompt asked it to "emit
    // a tool call" rather than asking for the task.
    expect(scenario.followUpPrompt, isNot(contains('accept_task')));
    expect(scenario.followUpPrompt, isNot(contains('spawn_subagent')));
  });

  test('the shared live runner stamps build provenance into session logs', () {
    final runner = File('tool/run_plan_mode_live_test.sh').readAsStringSync();

    // Without this every canary log records an unknown build, and a finding
    // qualified by git ancestry cannot be counted as evidence.
    expect(runner, contains('caverno_load_build_provenance_define_args'));
    expect(runner, contains(r'${CAVERNO_BUILD_DART_DEFINE_ARGS[@]}'));
  });
}
