import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/coding/coding_command_output_issue_detector.dart';
import 'package:caverno/features/chat/domain/services/coding/coding_continuation_recovery_prompt_builder.dart';
import 'package:caverno/features/chat/domain/services/command_verification_reconciliation.dart';
import 'package:caverno/features/chat/domain/services/local_command/literal_environment_inspection_policy.dart';
import 'package:caverno/features/chat/domain/services/project_task_step_completion_policy.dart';
import 'package:caverno/features/chat/domain/services/python/compound_python_runtime_repair.dart';
import 'package:caverno/features/chat/domain/services/structured_task_status_evidence.dart';
import 'package:caverno/features/chat/domain/services/unresolved_verification_failure.dart';
import 'package:caverno/features/chat/domain/services/verification_metadata_query_policy.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

const probe =
    'python3 --version; python3 -m pip --version 2>&1 | head -2; '
    'python3.12 -m pytest --version 2>&1 | head -2; '
    'python3.11 -m pytest --version 2>&1 | head -2';
const source = "import os, json, tempfile\nassert os.name\nprint('checked')";
String chain(String runner, [String program = source]) =>
    '$runner -m pytest -q && $runner -c "$program"';
ToolResultInfo run(
  String id,
  String command,
  int exit, {
  String directory = '/project',
  String? stdout,
  String? stderr,
  String name = 'local_execute_command',
  int failed = 0,
}) => ToolResultInfo(
  id: id,
  name: name,
  arguments: {'command': command},
  result: jsonEncode({
    'command': command,
    'working_directory': directory,
    'exit_code': exit,
    'stdout': stdout ?? (exit == 0 ? '61 passed in 0.1s\nchecked\n' : ''),
    'stderr':
        stderr ??
        (exit == 0
            ? ''
            : '/opt/python/bin/python3.14: No module named pytest\n'),
    if (name != 'local_execute_command') ...{'job_id': id, 'status': 'exited'},
  }),
  outcome: ToolOutcome(
    exitCode: exit,
    testFailedCount: failed,
    processState: name == 'local_execute_command'
        ? null
        : ToolProcessState.exited,
  ),
);
void main() {
  final failed = run('failed', chain('python3'), 1);
  final passed = run('passed', chain('.venv/bin/python'), 0);
  const failure = UnresolvedVerificationFailure();
  test('version discovery never becomes required task verification', () {
    final edit = ToolResultInfo(
      id: 'edit',
      name: 'edit_file',
      arguments: const {'path': 'source.py'},
      result: '{"changed":true,"path":"source.py"}',
      outcome: const ToolOutcome(
        fileMutations: [
          ToolFileMutation(path: '/project/source.py', changed: true),
        ],
      ),
    );
    final results = [edit, passed, run('metadata', probe, 1)];
    expect(failure.latest(results), isNull);
    expect(CommandVerificationReconciliation.scopeOf(results.last), isNull);
    expect(
      const CodingContinuationRecoveryPromptBuilder().partialProgressNotice(
        results,
      ),
      isNull,
    );
    final status = const ProjectTaskStepCompletionPolicy().status(
      response: 'Checked.\nPROJECT_TASK_SUBTASK_DONE',
      results: results,
      goal: ConversationGoal(
        id: 'g',
        objective: 'Implement',
        projectTaskAutoReview: true,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    );
    expect(status.completionAccepted, isTrue);
    expect(
      LiteralEnvironmentInspectionPolicy.applies(
        probe,
        allowPackageImports: false,
      ),
      isFalse,
    );
  });
  for (final command in [
    'python3 -m pytest --version',
    'pip3 --version | tail -n 2',
    probe,
  ]) {
    test('metadata query cannot supply success: $command', () {
      expect(
        CommandVerificationReconciliation.isVerification(
          run('metadata', command, 0),
        ),
        isFalse,
      );
    });
  }
  for (final command in [
    'python3 -m pytest --version && python3 -m pytest -q',
    'python3 -m pip install pytest',
    'python3 -m pytest --version > evidence.txt',
    'python3 -m pytest --version | tee evidence.txt',
    r'python3 -m pytest --version $(touch evidence)',
    'python3 -c "import pytest; assert pytest.__version__"',
  ]) {
    test('unknown or mixed syntax retains normal handling: $command', () {
      expect(VerificationMetadataQueryPolicy.applies(command), isFalse);
    });
  }
  // Session 1afd70a6: version queries mixed with plain reads. The probe
  // failed only because a host interpreter was broken, and the harness made
  // the turn repair that host instead of accepting a verified subtask.
  const mixedProbe =
      'cat requirements.txt; ls -a | grep -i venv; '
      '/usr/local/bin/python3 -m pytest --version 2>&1 | head -2; '
      '/usr/bin/python3 -m pytest --version 2>&1 | head -2';
  test('a discovery probe mixing reads with version queries is no check', () {
    final results = [
      run('missing', 'python3 -m pytest test_watcher.py -q 2>&1 | tail -5', 1),
      run('probe', mixedProbe, 120),
      run(
        'venv',
        '.venv/bin/python -m pytest test_watcher.py -q 2>&1 | tail -5',
        0,
        stdout: '14 passed in 3.07s\n',
      ),
    ];
    expect(VerificationMetadataQueryPolicy.applies(mixedProbe), isTrue);
    expect(
      CommandVerificationReconciliation.isVerification(results[1]),
      isFalse,
    );
    expect(failure.latest(results), isNull);
    final status = const ProjectTaskStepCompletionPolicy().status(
      response: 'Verified.\nPROJECT_TASK_SUBTASK_DONE',
      results: results,
      goal: ConversationGoal(
        id: 'g',
        objective: 'Implement',
        projectTaskAutoReview: true,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    );
    expect(status.completionAccepted, isTrue);
  });
  // Session 1df8a06d: the bare import probe failed on a host without
  // pytest and stayed the check the subtask had to make pass, although the
  // project venv then ran the tests (86 passed).
  const importProbe =
      'cd /repo && ls -a | head -20 && which pytest; '
      'python3 -c "import pytest" 2>&1';
  test('a bare pytest import probe is no check', () {
    final results = [
      run('probe', importProbe, 1),
      run(
        'venv',
        '.venv/bin/python -m pytest test_state.py -q 2>&1 | tail -5',
        0,
        stdout: '86 passed in 9.18s\n',
      ),
    ];
    expect(VerificationMetadataQueryPolicy.applies(importProbe), isTrue);
    expect(failure.latest(results), isNull);
    final status = const ProjectTaskStepCompletionPolicy().status(
      response: 'Verified.\nPROJECT_TASK_SUBTASK_DONE',
      results: results,
      goal: ConversationGoal(
        id: 'g',
        objective: 'Implement',
        projectTaskAutoReview: true,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    );
    expect(status.completionAccepted, isTrue);
  });
  for (final command in [
    'python3 -c "import watcher"',
    'python3 -c "import pytest, watcher"',
    'python3 -c "import pytest; pytest.main()"',
  ]) {
    test(
      'importing project code or running pytest stays a check: $command',
      () {
        expect(VerificationMetadataQueryPolicy.applies(command), isFalse);
      },
    );
  }
  for (final command in [
    'cat requirements.txt; grep -n webhook watcher.py',
    'cat requirements.txt; python3 -m pytest -q',
    'ls; python3 -m pytest --version && python3 -m pytest -q',
    'python3 -m pytest --version; python3 run_checks.py',
    'cat a.txt; python3 -m pytest --version > evidence.txt',
  ]) {
    test(
      'reads without a query, or with a real run, stay normal: $command',
      () {
        expect(VerificationMetadataQueryPolicy.applies(command), isFalse);
      },
    );
  }
  test('masked availability errors stay observations, not failed feedback', () {
    final result = run(
      'metadata',
      probe,
      0,
      stdout: 'python3.12: No module named pytest\n',
      stderr: '',
    );
    expect(const CodingCommandOutputIssueDetector().detect(result), isNull);
    expect(failure.latest([passed, result]), isNull);
    expect(
      const CodingContinuationRecoveryPromptBuilder().partialProgressNotice([
        passed,
        result,
      ]),
      isNull,
    );
  });
  test('typed test failures override metadata spelling', () {
    expect(
      CommandVerificationReconciliation.isVerification(
        run('bad', 'python3 --version', 1, failed: 1),
      ),
      isTrue,
    );
    expect(
      failure.latest([run('bad', 'python3 --version', 1, failed: 1)]),
      isNotNull,
    );
  });
  test(
    'an identical complete chain settles a missing-pytest launch failure',
    () {
      expect(failure.latest([failed, passed]), isNull);
      expect(
        CommandVerificationReconciliation.currentResults([
          failed,
          passed,
        ]).map((r) => r.id),
        ['passed'],
      );
    },
  );
  for (final variant in [
    chain('.venv/bin/python', source.replaceFirst('os, json, tempfile', 'os')),
    chain(
      '.venv/bin/python',
      source.replaceFirst('assert os.name', 'assert True'),
    ),
    chain('.venv/bin/python', source.replaceFirst('assert os.name', 'pass')),
    chain(
      '.venv/bin/python',
    ).replaceFirst('pytest -q', 'pytest test_other.py -q'),
    '.venv/bin/python -m pytest -q',
  ]) {
    test('changed verification never settles the full chain: $variant', () {
      expect(
        failure.latest([failed, run('different', variant, 0)])?.id,
        'failed',
      );
    });
  }
  test('a different directory cannot settle the failure', () {
    expect(
      failure.latest([
        failed,
        run('other', chain('.venv/bin/python'), 0, directory: '/other'),
      ])?.id,
      'failed',
    );
  });
  test('runtime replacement cannot clear a failure after tests started', () {
    final actualFailure = run(
      'assertion',
      chain('python3'),
      1,
      stdout: '61 passed in 0.1s\n',
      stderr: 'Traceback\nAssertionError',
    );
    expect(failure.latest([actualFailure, passed])?.id, 'assertion');
    expect(failure.latest([passed, failed])?.id, 'failed');
    expect(
      failure.latest([
        failed,
        run('empty', chain('.venv/bin/python'), 0, stdout: 'checked'),
      ])?.id,
      'failed',
    );
  });
  test('a background completion uses the same rules', () {
    expect(
      failure.latest([
        failed,
        run('job', chain('.venv/bin/python'), 0, name: 'process_wait'),
      ]),
      isNull,
    );
    expect(
      CommandVerificationReconciliation.isVerification(
        run('metadata', probe, 1, name: 'process_wait'),
      ),
      isFalse,
    );
  });
  test('runtime repair keeps a leading cd in the effective directory', () {
    final failed = run('nested', 'cd nested && ${chain('python3')}', 1);
    final successful = run(
      'nested-pass',
      '.venv/bin/python -m pytest -q',
      0,
      directory: '/project/nested',
      stdout: '61 passed in 0.1s\n',
    );
    expect(
      CompoundPythonRuntimeRepair.suggest(failed, [failed, successful]),
      'cd /project/nested && ${chain('.venv/bin/python')}',
    );
  });
  test('a stale background verifier cannot settle a launch failure', () {
    final start = ToolResultInfo(
      id: 'start',
      name: 'process_start',
      arguments: {'command': chain('.venv/bin/python')},
      result: jsonEncode({
        'job_id': 'job',
        'command': chain('.venv/bin/python'),
        'working_directory': '/project',
        'status': 'running',
      }),
      outcome: const ToolOutcome(processState: ToolProcessState.running),
    );
    final change = ToolResultInfo(
      id: 'edit',
      name: 'edit_file',
      arguments: const {'path': 'source.py'},
      result: '{"changed":true,"path":"source.py"}',
      outcome: const ToolOutcome(
        fileMutations: [
          ToolFileMutation(path: '/project/source.py', changed: true),
        ],
      ),
    );
    final poll = run('job', chain('.venv/bin/python'), 0, name: 'process_wait');
    expect(failure.latest([failed, start, change, poll])?.id, 'failed');
  });
  test(
    'runtime repair preserves the original source and requires fresh execution',
    () {
      final changed = run(
        'changed',
        chain(
          '.venv/bin/python',
          source.replaceFirst('os, json, tempfile', 'os'),
        ),
        0,
      );
      final results = [failed, changed];
      final suggestion = CompoundPythonRuntimeRepair.suggest(failed, results);
      expect(suggestion, chain('.venv/bin/python'));
      expect(failure.latest(results)?.id, 'failed');
      expect(
        const StructuredTaskStatusEvidence().summarize(
          results,
        )!['unresolvedVerification']['runtimeRepairCommand'],
        suggestion,
      );
      expect(failure.describe(results), contains('runtimeRepairCommand'));
      expect(
        failure.latest([...results, run('repair', suggestion!, 0)]),
        isNull,
      );
    },
  );
}
