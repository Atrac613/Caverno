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
    // The two Anabasis scenarios are the ones that address the parent; every
    // other live scenario must stay a plain plan-mode run.
    const addressesParent = <String>{
      'live_anabasis_delegation_admission',
      'live_anabasis_acceptance',
      'live_anabasis_worktree',
    };
    final others = buildLivePlanModeScenarios().where(
      (candidate) => !addressesParent.contains(candidate.name),
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

    // The default is still the queue-holding scenario; the acceptance sibling
    // opts in through CAVERNO_ANABASIS_SCENARIO, so a bare run measures what it
    // always did.
    expect(
      runner,
      contains(
        'SCENARIO="\${CAVERNO_ANABASIS_SCENARIO:-live_anabasis_delegation_admission}"',
      ),
    );
    expect(runner, contains('CAVERNO_PLAN_MODE_SCENARIOS="\${SCENARIO}"'));
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
    // "Never attempted" is a claim about the model, and a run only earns it if
    // the question reached the model. The elicitation prompt is queued rather
    // than sent while the delegation turn still streams, so the two cases have
    // to read differently.
    expect(runner, contains('never asked'));
    // And "refused by something the acceptance codes cannot name" is a third
    // case: the parent authority guard refused accept_task before the handler,
    // so neither an acceptance_* code nor a recorded acceptance existed.
    expect(runner, contains('Acceptance attempted'));
    // Declining and never being asked are different answers, and only one of
    // them is about the model. The eleventh worktree run had the evidence and
    // the time and reported in prose, because nothing had asked it for the
    // bookkeeping call -- which read as "never attempted" and was not.
    expect(runner, contains('anabasis_acceptance_elicited'));
    expect(runner, contains('Acceptance elicited:'));
    expect(runner, contains('asked and declined'));
    // Which route it took, for every run: a subagent acceptance passes no audit
    // level, so "accepted" alone does not say what it rested on.
    expect(runner, contains('Worktree children enqueued'));
    expect(runner, contains('Extra follow-up turns delivered='));
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

  test('only the worktree scenario makes its workspace a repository', () {
    // A repository the model can see changes what it does -- it starts reading
    // git state and reporting diffs -- so this stays off wherever a branch is not
    // the point.
    final scenarios = buildLivePlanModeScenarios();
    final withGit = scenarios
        .where((candidate) => candidate.initializeGitRepository)
        .map((candidate) => candidate.name);

    expect(withGit, ['live_anabasis_worktree']);
  });

  test('a worktree enqueue counts as delegation', () {
    final runner = File(
      'tool/run_anabasis_delegation_live_canary.sh',
    ).readAsStringSync();

    // The admitted signature matches the saved contract in a *child's request*,
    // and a worktree child's contract goes into a branch instead. A run that
    // enqueued one and was reported as "delegated none" is the instrument being
    // wrong, not the parent -- which is exactly what the first such run said.
    final enqueueIndex = runner.indexOf('WORKTREE_ENQUEUED=');
    expect(enqueueIndex, isNonNegative);
    expect(
      runner.indexOf('ADMITTED=1', enqueueIndex),
      isNonNegative,
      reason: 'The enqueue count has to be able to set ADMITTED.',
    );
  });

  test('every capture tolerates finding nothing', () {
    final runner = File(
      'tool/run_anabasis_delegation_live_canary.sh',
    ).readAsStringSync();

    // Under `set -e`, assigning from a grep or sed that matched nothing aborts
    // the script. That killed the inconclusive branch once and reported a run
    // with no ready task as a failure -- the exact confusion the three-way
    // verdict exists to prevent.
    for (final capture in [
      'QUEUE_SIZE="\$(',
      'REFUSALS="\$(',
      'DELIVERED="\$(',
      'ATTEMPTS="\$(',
      'WORKTREE_ENQUEUED="\$(',
    ]) {
      final start = runner.indexOf(capture);
      expect(start, isNonNegative, reason: capture);
      final line = runner.substring(start, runner.indexOf('\n', start));
      expect(line, contains('|| true'), reason: capture);
    }
  });

  test('the elicitation turn is separate, and is not leading', () {
    final scenario = buildLivePlanModeScenarios().singleWhere(
      (candidate) => candidate.name == 'live_anabasis_delegation_admission',
    );

    // Separate from the first turn on purpose: the first measures whether the
    // model volunteers the judgement, this one whether it makes it when told.
    // Collapsing them destroys the distinction, which for update_goal was the
    // whole finding -- never volunteered, reliable when instructed.
    expect(scenario.extraFollowUpPrompts, hasLength(1));
    final elicitation = scenario.extraFollowUpPrompts.single;
    expect(elicitation, startsWith('@anabasis'));
    expect(elicitation, isNot(contains('accept_task')));
    // Reporting that the work is not acceptable has to be as available as
    // accepting it, or the probe is leading and a false acceptance is the
    // expensive direction.
    expect(elicitation, contains('\u3057\u306a\u3044'));
  });

  test('the shared live runner stamps build provenance into session logs', () {
    final runner = File('tool/run_plan_mode_live_test.sh').readAsStringSync();

    // Without this every canary log records an unknown build, and a finding
    // qualified by git ancestry cannot be counted as evidence.
    expect(runner, contains('caverno_load_build_provenance_define_args'));
    expect(runner, contains(r'${CAVERNO_BUILD_DART_DEFINE_ARGS[@]}'));
  });
}
