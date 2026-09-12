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
    expect(scenario.cancelExecutionBeforeFollowUp, isTrue);
    expect(scenario.followUpPrompt, isNotNull);
    expect(scenario.followUpPrompt, startsWith('@anabasis'));
    expect(scenario.savedWorkflowExpectation?.minTaskCount, isNotNull);
    expect(
      scenario.logExpectations.map((expectation) => expectation.pattern),
      contains('[Subagent] Spawning'),
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
    // unrelated historical log decide this run, so the --dir must carry the
    // run's own log root.
    expect(
      runner,
      contains('check_fix_firings.py" --dir "\${SESSION_LOG_ROOT}'),
    );
    expect(runner, contains(r'^\[FIRED\] anabasis_delegation_admitted'));
    expect(runner, contains('exit 1'));
  });

  test('a spawned child alone does not pass the canary', () {
    final runner = File(
      'tool/run_anabasis_delegation_live_canary.sh',
    ).readAsStringSync();

    // The scenario asserts "[Subagent] Spawning"; that proves delegation
    // happened, not that planned work was selected from the ready queue. Only
    // the admitted signature closes ANA2's gap, so the script must fail when
    // it is absent even though the scenario itself passed.
    final gateIndex = runner.indexOf('anabasis_delegation_admitted');
    final exitIndex = runner.indexOf('exit 1');
    expect(gateIndex, isNonNegative);
    expect(exitIndex, greaterThan(gateIndex));
  });

  test('the shared live runner stamps build provenance into session logs', () {
    final runner = File('tool/run_plan_mode_live_test.sh').readAsStringSync();

    // Without this every canary log records an unknown build, and a finding
    // qualified by git ancestry cannot be counted as evidence.
    expect(runner, contains('caverno_load_build_provenance_define_args'));
    expect(runner, contains(r'${CAVERNO_BUILD_DART_DEFINE_ARGS[@]}'));
  });
}
