import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('LL37 Routine runner is consent gated and report backed', () {
    final runner = File(
      'tool/run_ll37_routine_live_canary.sh',
    ).readAsStringSync();
    final canary = File(
      'tool/canaries/ll37_routine_live_canary_test.dart',
    ).readAsStringSync();

    expect(runner, contains('CAVERNO_LL37_PERSONAL_EVAL_RECORDING_CONSENT=1'));
    expect(runner, contains('CAVERNO_LL37_ROUTINE_LIVE_CANARY=1'));
    expect(runner, contains('CAVERNO_LL37_ROUTINE_SCENARIO'));
    expect(runner, contains('ll37_routine_history_export.dart'));
    expect(runner, contains('ll37_verifier_fidelity_probe.dart'));
    expect(runner, contains('candidate-a_case.json'));
    expect(runner, contains('candidate-b_case.json'));
    expect(runner, contains('invalidCount'));
    expect(runner, contains('unverifiableCount'));
    expect(runner, contains('matchesExpected'));
    expect(runner, contains('mechanicalVerificationPassed'));
    expect(runner, contains('metrics.get("totalCount") != 2'));
    expect(canary, contains('RoutineRunTrigger.scheduled'));
    expect(canary, contains('getOpenAiToolDefinitions'));
    expect(canary, contains('private_scratch'));
    expect(canary, contains('Process.run'));
    expect(canary, contains('write_tools_disabled_mechanically_green'));
    expect(canary, contains('expect(brokenVerification.exitCode, 0)'));
  });

  test('LL37 remaining-pairs runner requires five pairs and Go', () {
    final runner = File(
      'tool/run_ll37_remaining_pairs_live_canary.sh',
    ).readAsStringSync();

    expect(runner, contains('CAVERNO_LL37_PERSONAL_EVAL_RECORDING_CONSENT=1'));
    expect(runner, contains('feature_flag retry_limit display_format'));
    expect(runner, contains('CAVERNO_LL37_LL13_CORRECT_CASE'));
    expect(runner, contains('CAVERNO_LL37_ROUTINE_BASELINE_CORRECT_CASE'));
    expect(runner, contains('len(results) != 10'));
    expect(runner, contains('correctCaseCount") != 5'));
    expect(runner, contains('brokenCaseCount") != 5'));
    expect(runner, contains('eligiblePairCount") != 5'));
    expect(runner, contains('eligibleObjectiveCount") != 5'));
    expect(runner, contains('eligibleSourceSurfaces", 0) < 2'));
    expect(runner, contains('Reusing completed LL37 scenario'));
    expect(runner, contains('Refusing to replace incomplete LL37 scenario'));
    expect(runner, contains(r'RUN_DIR="${ROOT_DIR}/${RUN_DIR}"'));
    expect(runner, contains('report.get("gate") != "go"'));
    expect(runner, contains('falseRefuteRate'));
    expect(runner, contains('brokenRecall'));
  });
}
