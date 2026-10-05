import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/project_task_verification_context.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ToolResultInfo verify({
    int exit = 0,
    bool reused = false,
    bool carried = false,
    bool changed = false,
    String command = '.venv/bin/python -m pytest test_watcher.py -v',
  }) => ToolResultInfo(
    id: 'check',
    name: 'local_execute_command',
    arguments: {'command': command, 'working_directory': '/repo'},
    result: jsonEncode({
      'exit_code': exit,
      'stdout': '13 passed',
      'execution_reused': reused,
    }),
    outcome: ToolOutcome(exitCode: exit),
    fromEarlierLoop: carried,
    changesSinceCapture: changed ? ['edit_file /repo/watcher.py'] : [],
  );
  final edit = ToolResultInfo(
    id: 'edit',
    name: 'edit_file',
    arguments: {'path': '/repo/watcher.py'},
    result: '{"changed":true}',
  );

  test('retains the successful project interpreter and exact directory', () {
    final context = ProjectTaskVerificationContext.fromResults([
      edit,
      verify(),
    ]);
    expect(
      context.runs.single.command,
      '.venv/bin/python -m pytest test_watcher.py -v',
    );
    expect(context.runs.single.directory, '/repo');
    expect(context.prompt, contains('historical evidence'));
    expect(
      context.prompt,
      contains('before proposing dependency installation'),
    );
  });
  for (final result in [
    verify(exit: 1),
    verify(reused: true),
    verify(carried: true),
    verify(changed: true),
    verify(command: 'python3 --version'),
  ]) {
    test(
      'excludes unavailable or stale verification: ${result.result} ${result.arguments}',
      () {
        expect(
          ProjectTaskVerificationContext.fromResults([result]).runs,
          isEmpty,
        );
      },
    );
  }
  test('a subsequent edit invalidates the earlier successful runner', () {
    expect(
      ProjectTaskVerificationContext.fromResults([verify(), edit]).runs,
      isEmpty,
    );
  });
}
