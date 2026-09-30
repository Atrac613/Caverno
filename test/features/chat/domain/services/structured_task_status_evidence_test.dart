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
      result: '{"exit_code":$exitCode,"stdout":"$stdout","stderr":""}',
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
