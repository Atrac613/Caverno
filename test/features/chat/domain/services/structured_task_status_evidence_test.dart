import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/structured_task_status_evidence.dart';
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
