import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('LL37 worktree-agent runner is consent gated and report backed', () {
    final runner = File(
      'tool/run_ll37_worktree_agent_live_canary.sh',
    ).readAsStringSync();
    final canary = File(
      'tool/canaries/ll37_worktree_agent_live_canary_test.dart',
    ).readAsStringSync();

    expect(runner, contains('CAVERNO_LL37_PERSONAL_EVAL_RECORDING_CONSENT=1'));
    expect(runner, contains('CAVERNO_LL37_WORKTREE_AGENT_LIVE_CANARY=1'));
    expect(runner, contains('ll37_worktree_agent_history_export.dart'));
    expect(runner, contains('ll37_verifier_fidelity_probe.dart'));
    expect(runner, contains('candidate-a_case.json'));
    expect(runner, contains('candidate-b_case.json'));
    expect(runner, contains('invalidCount'));
    expect(runner, contains('unverifiableCount'));
    expect(runner, contains('matchesExpected'));
    expect(canary, contains('private_scratch'));
    expect(canary, contains("'write_file', 'edit_file', 'delete_file'"));
    expect(canary, contains('production LL13 delegate'));
    expect(canary, contains('controlled_live_canary'));
  });
}
