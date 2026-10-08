import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/structured_task_status_evidence.dart';
import 'package:caverno/features/chat/domain/services/tool_results/tool_result_prompt_builder.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

ToolResultInfo _write(String path) => ToolResultInfo(
  id: 'write-$path',
  name: 'write_file',
  arguments: {'path': path},
  result: '{"path":"$path","created":true,"changed":true}',
  outcome: ToolOutcome(
    fileMutations: [ToolFileMutation(path: path, changed: true)],
  ),
);

ToolResultInfo _command(String command, int exitCode, String stdout) =>
    ToolResultInfo(
      id: 'cmd-$command',
      name: 'local_execute_command',
      arguments: {'command': command},
      result: jsonEncode({
        'exit_code': exitCode,
        'stdout': stdout,
        'stderr': '',
      }),
      outcome: ToolOutcome(exitCode: exitCode),
    );

ToolResultInfo _read(String path) => ToolResultInfo(
  id: 'read-$path',
  name: 'read_file',
  arguments: {'path': path},
  result: '{"path":"$path","content":"x"}',
);

void main() {
  const evidence = StructuredTaskStatusEvidence();

  test(
    'retains launch authority without inferring it from model arguments',
    () {
      for (final boundary in [
        {'kind': 'macos_workspace_sandbox', 'network': 'denied'},
        {'kind': 'host', 'network': 'not_restricted_by_workspace_sandbox'},
        null,
      ]) {
        final summary = evidence.summarize([
          ToolResultInfo(
            id: 'network-failure',
            name: 'local_execute_command',
            arguments: const {
              'command': 'python3 watcher.py --dry-run',
              'execution_scope': 'host',
            },
            result: jsonEncode({
              'exit_code': 1,
              'stdout': 'socket.gaierror: DNS resolution failed',
              'execution_boundary': ?boundary,
            }),
            outcome: const ToolOutcome(exitCode: 1),
          ),
        ])!;
        for (final key in ['latestExecution', 'unresolvedVerification']) {
          final execution = summary[key] as Map;
          expect(execution['succeeded'], isFalse);
          if (boundary == null) {
            expect(execution, isNot(contains('executionBoundary')));
          } else {
            expect(execution['executionBoundary'], boundary);
          }
        }
      }
    },
  );

  test('states the writes and the verification that followed them', () {
    // Session 1d76c878: the status request carried four reads and neither
    // the written test files nor the passing pytest run.
    final summary = evidence.summarize([
      _read('/p/state.py'),
      _write('/p/test_state.py'),
      _write('/p/test_notifier.py'),
      _command('pytest -q', 0, '53 passed in 3.11s'),
      _read('/p/ROADMAP.md'),
    ]);

    expect(summary!['fileChanges'], [
      '/p/test_state.py',
      '/p/test_notifier.py',
    ]);
    expect(summary['latestExecution'], {
      'tool': 'local_execute_command',
      'command': 'pytest -q',
      'succeeded': true,
      'exitCode': 0,
      'outputTail': '53 passed in 3.11s',
    });
    expect(summary['latestExecutionFollowsLatestChange'], isTrue);
  });

  test('reports a verification that predates the latest change', () {
    final summary = evidence.summarize([
      _command('pytest -q', 1, '1 failed'),
      _write('/p/a.py'),
    ]);

    expect(summary!['latestExecutionFollowsLatestChange'], isFalse);
    expect((summary['latestExecution'] as Map)['succeeded'], isFalse);
  });

  test('a successful echo cannot report its failed command as succeeded', () {
    final summary = evidence.summarize([
      _command(
        r'python3 app.py --dry-run 2>&1 | head -40; echo "PIPELINE_EXIT=${PIPESTATUS[0]:-n/a}"',
        0,
        'usage error\nPIPELINE_EXIT=2\n',
      ),
    ])!;
    final execution = summary['latestExecution'] as Map;
    expect(execution['succeeded'], isFalse);
    expect(execution['exitCode'], 0);
    expect(execution['reportedExitCode'], 2);
    expect(execution['failureReason'], contains('failing command exit status'));
    expect(
      summary['unresolvedVerificationFailure'],
      contains('reported exit 2'),
    );
  });

  test('a passing unrelated check retains the earlier failed verification', () {
    final summary = evidence.summarize([
      _command('python3 app.py --dry-run', 2, 'usage error'),
      _command('python3 -m pytest -q', 0, '53 passed in 0.1s'),
    ])!;
    expect((summary['latestExecution'] as Map)['succeeded'], isTrue);
    expect(
      summary['unresolvedVerificationFailure'],
      contains('app.py --dry-run'),
    );
    final failed = summary['unresolvedVerification'] as Map;
    expect(failed['command'], 'python3 app.py --dry-run');
    expect(failed['exitCode'], 2);
    expect(failed['succeeded'], isFalse);
    expect(failed['outputTail'], 'usage error');
  });

  test(
    'carries a failed inline verifier verbatim beside the later success',
    () {
      final command =
          '''python3 -c "from worker import emit
records = emit()
${'# fixture details\n' * 40}assert '[INFO]' in records, 'INFO missing'
assert 'worker' in records, 'module missing'
" 2>&1''';
      final result = ToolResultInfo(
        id: 'inline-failure',
        name: 'local_execute_command',
        arguments: {'command': command, 'working_directory': '/workspace'},
        result: jsonEncode({
          'command': command,
          'working_directory': '/workspace',
          'exit_code': 1,
          'stdout':
              '${'traceback detail\n' * 50}AssertionError: module missing',
        }),
        outcome: ToolOutcome(exitCode: 1),
      );
      final summary = evidence.summarize([
        result,
        _command('python3 -m pytest -q', 0, '53 passed'),
      ])!;
      final failed = summary['unresolvedVerification'] as Map;
      expect(failed['toolCallId'], 'inline-failure');
      expect(failed['command'], command);
      expect(failed['commandTruncated'], isFalse);
      expect(failed['workingDirectory'], '/workspace');
      expect(failed['repairableInlineFixture'], isTrue);
      expect(failed['outputTail'], endsWith('AssertionError: module missing'));
      expect((summary['latestExecution'] as Map)['succeeded'], isTrue);
    },
  );

  test('bounds failed command source and explicitly reports truncation', () {
    final summary = evidence.summarize([
      _command("python3 -c \"${'x' * 16000}\"", 1, 'failed'),
    ])!;
    final failed = summary['unresolvedVerification'] as Map;
    expect(failed['commandTruncated'], isTrue);
    expect(
      (failed['command'] as String).length,
      StructuredTaskStatusEvidence.maxFailedCommandChars,
    );
  });

  test('compact recovery budgeting retains a repairable failed command', () {
    final command =
        '''python3 -c "from worker import missing
${'# fixture details\n' * 110}records = missing()
assert '[INFO]' in records, 'INFO missing'
assert 'worker' in records, 'module missing'
" 2>&1''';
    final failed = ToolResultInfo(
      id: 'inline-failure',
      name: 'local_execute_command',
      arguments: {'command': command, 'working_directory': '/workspace'},
      result: jsonEncode({'exit_code': 1, 'stdout': 'ImportError: missing'}),
      outcome: ToolOutcome(exitCode: 1),
    );
    final feedback = evidence.attachTo(
      ToolResultInfo(
        id: 'status',
        name: 'coding_continuation_recovery',
        arguments: const {},
        result: '{"ok":false,"code":"structured_coding_task_status"}',
      ),
      [failed, _command('python3 -m pytest -q', 0, '53 passed')],
    );
    final budgeted = ToolResultPromptBuilder.budgetToolResults(
      [feedback],
      mode: ToolResultPromptBudgetMode.compact,
      summaryFirst: true,
    );
    final payload = jsonDecode(budgeted.single.result) as Map;
    final captured = payload['capturedEvidence'] as Map;
    final unresolved = captured['unresolvedVerification'] as Map;
    expect(unresolved['command'], command);
    expect(unresolved['outputTail'], 'ImportError: missing');
    expect(unresolved['repairableInlineFixture'], isTrue);
  });

  test('masked runtime errors also remain failed in captured evidence', () {
    final summary = evidence.summarize([
      _command(
        'python3 app.py 2>&1 | head -40',
        0,
        'Traceback (most recent call last)\nConnectionError: offline',
      ),
    ])!;
    expect((summary['latestExecution'] as Map)['succeeded'], isFalse);
    expect(
      summary['unresolvedVerificationFailure'],
      contains('runtime failure'),
    );
  });

  test('an unmasked successful logging verifier may print a traceback', () {
    final summary = evidence.summarize([
      _command(
        'python3 verify_logging.py',
        0,
        'Traceback (most recent call last)\nExpected exception\nAll checks passed',
      ),
    ])!;
    expect((summary['latestExecution'] as Map)['succeeded'], isTrue);
    expect(summary, isNot(contains('unresolvedVerificationFailure')));
  });

  test('ignores git inspection and returns null without evidence', () {
    final status = ToolResultInfo(
      id: 'git',
      name: 'git_execute_command',
      arguments: {'command': 'status'},
      result: '{"exit_code":0,"stdout":""}',
      outcome: ToolOutcome(exitCode: 0),
    );

    expect(evidence.summarize([_read('/p/a.py'), status]), isNull);
  });

  test('attaches the summary to the status feedback payload', () {
    final feedback = ToolResultInfo(
      id: 'f',
      name: 'coding_continuation_recovery',
      arguments: const {},
      result: '{"ok":false,"code":"structured_coding_task_status"}',
    );

    final attached = evidence.attachTo(feedback, [
      _write('/p/a.py'),
      _command('pytest -q', 0, '1 passed'),
    ]);
    final payload = jsonDecode(attached.result) as Map<String, dynamic>;

    expect(payload['code'], 'structured_coding_task_status');
    expect((payload['capturedEvidence'] as Map)['fileChanges'], ['/p/a.py']);
    expect(evidence.attachTo(feedback, const []), same(feedback));
  });
}
