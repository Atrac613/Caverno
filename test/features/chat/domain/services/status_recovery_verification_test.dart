import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/coding/structured_coding_task_recovery_policy.dart';
import 'package:caverno/features/chat/domain/services/project_task_completion_evidence.dart';
import 'package:caverno/features/chat/domain/services/status_recovery_verification.dart';
import 'package:caverno/features/chat/domain/services/tool_result_prompt_builder.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:test/test.dart';

Map<String, dynamic> _tool(String name) => {
  'type': 'function',
  'function': {'name': name},
};

void main() {
  const verification = StatusRecoveryVerification();
  final allTools = [
    _tool('update_goal'),
    _tool('local_execute_command'),
    _tool('run_tests'),
    _tool('edit_file'),
  ];
  final edit = ToolResultInfo(
    id: 'edit',
    name: 'edit_file',
    arguments: const {'path': 'state.py'},
    result: '{"changed":true}',
    outcome: const ToolOutcome(
      fileMutations: [ToolFileMutation(path: 'state.py', changed: true)],
    ),
  );
  final pytest = ToolResultInfo(
    id: 'pytest',
    name: 'local_execute_command',
    arguments: const {'command': '.venv/bin/python -m pytest -q'},
    result: '{"exit_code":0,"stdout":"53 passed"}',
    outcome: const ToolOutcome(exitCode: 0),
  );
  ToolCallInfo call(String name, Map<String, dynamic> arguments) =>
      ToolCallInfo(id: name, name: name, arguments: arguments);

  test('the gap check reads the completion gate wording', () {
    final gaps = const ProjectTaskCompletionEvidence().gaps(
      toolResults: [edit],
      evidence: ToolResultPromptBuilder.completionEvidence([edit]),
    );
    expect(
      gaps.where((gap) => gap.contains('execution verification')),
      hasLength(1),
    );
  });

  test('offers execution tools only while the latest change is unverified', () {
    // Session 02fec5c8: the last edit had no verification after it, and the
    // status request offered only update_goal.
    final open = verification.request(
      allTools,
      [edit],
      null,
      const StructuredCodingTaskRecoveryPolicy(),
    );
    expect(open.tools.map((tool) => (tool['function'] as Map)['name']), [
      'update_goal',
      'local_execute_command',
      'run_tests',
    ]);
    expect(open.prompt, contains('run exactly one verification command'));

    final closed = verification.request(
      allTools,
      [edit, pytest],
      null,
      const StructuredCodingTaskRecoveryPolicy(),
    );
    expect(closed.tools.map((tool) => (tool['function'] as Map)['name']), [
      'update_goal',
    ]);
    expect(closed.prompt, const StructuredCodingTaskRecoveryPolicy().prompt);
  });

  test('an inherited change also opens the gap', () {
    final goal = ConversationGoal(
      id: 'g',
      objective: 'task',
      projectTaskInheritedPaths: const ['/repo/state.py'],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    expect(verification.gapOpen(const [], goal), isTrue);
  });

  test('a full rerun with the project runtime closes an inherited gap', () {
    final goal = ConversationGoal(
      id: 'g',
      objective: 'Verify inherited logging changes',
      projectTaskInheritedPaths: const ['/workspace/logging.py'],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    ToolResultInfo run(String id, String interpreter, int exitCode) {
      final command =
          'cd /workspace && $interpreter verify_logging.py && '
          '$interpreter -m pytest test_state.py test_watcher.py -v 2>&1';
      return ToolResultInfo(
        id: id,
        name: 'local_execute_command',
        arguments: {'command': command, 'working_directory': '/workspace'},
        result: jsonEncode({
          'command': command,
          'working_directory': '/workspace',
          'exit_code': exitCode,
          'stdout': exitCode == 0
              ? 'All 24 checks passed.\n53 passed in 3.09s'
              : 'python3: No module named pytest',
        }),
        outcome: ToolOutcome(exitCode: exitCode),
      );
    }

    final failed = run('failed', 'python3', 1);
    final open = verification.request(
      allTools,
      [failed],
      goal,
      const StructuredCodingTaskRecoveryPolicy(),
    );
    expect(open.prompt, contains('captured successful checks'));
    expect(open.prompt, contains('full failed verification chain'));
    expect(open.prompt, contains('capturedEvidence.unresolvedVerification'));
    expect(
      open.prompt,
      contains('entire source block from that assert onward'),
    );
    expect(open.prompt, contains('Do not drop or weaken checks'));
    expect(open.prompt, isNot(contains('latest change has no successful')));
    final closed = verification.request(
      allTools,
      [failed, run('passed', '.venv/bin/python', 0)],
      goal,
      const StructuredCodingTaskRecoveryPolicy(),
    );
    expect(closed.tools.map((tool) => (tool['function'] as Map)['name']), [
      'update_goal',
    ]);
    expect(closed.prompt, const StructuredCodingTaskRecoveryPolicy().prompt);
  });

  test('accepts one update_goal or one verification call that was offered', () {
    final offered = verification.tools(allTools, verificationGap: true);
    expect(
      verification.accepts([
        call('update_goal', {'completed': true}),
      ], offered),
      isTrue,
    );
    expect(
      verification.accepts([
        call('local_execute_command', {
          'command': '.venv/bin/python -m pytest -q',
        }),
      ], offered),
      isTrue,
    );
    expect(
      verification.accepts([
        call('local_execute_command', {'command': 'pip install pytest'}),
      ], offered),
      isFalse,
      reason: 'not a verification',
    );
    expect(
      verification.accepts([
        call('edit_file', {'path': 'state.py'}),
      ], offered),
      isFalse,
      reason: 'not offered',
    );
    expect(
      verification.accepts([
        call('local_execute_command', {'command': 'pytest -q'}),
      ], verification.tools(allTools, verificationGap: false)),
      isFalse,
      reason: 'gap closed, so not offered',
    );
    expect(
      verification.accepts([
        call('local_execute_command', {'command': 'pytest -q'}),
        call('update_goal', {'completed': true}),
      ], offered),
      isFalse,
      reason: 'one call at a time',
    );
  });

  test('accepts the verification a real status request was refused', () {
    // Session 22d603f7: the offered verification was refused twice because
    // `2>&1` and a `.venv/bin/python` script read as workspace mutation.
    final offered = verification.tools(allTools, verificationGap: true);
    expect(
      verification.accepts([
        call('local_execute_command', {
          'command':
              'cd /Users/noguwo/Documents/Workspace/Watcher && '
              '.venv/bin/python verify_logging.py && .venv/bin/python -m '
              'pytest test_state.py test_watcher.py -v 2>&1',
        }),
      ], offered),
      isTrue,
    );
    expect(
      verification.accepts([
        call('local_execute_command', {'command': 'pytest -q > out.txt'}),
      ], offered),
      isFalse,
    );
  });
}
