import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/goal/goal_update_ack.dart';
import 'package:caverno/features/chat/domain/services/project_task/project_task_step_completion_policy.dart';
import 'package:caverno/features/chat/domain/services/project_task/project_task_terminal_status.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const policy = ProjectTaskStepCompletionPolicy();
  final goal = ConversationGoal(
    id: 'goal',
    objective: 'Task',
    projectTaskAutoReview: true,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  const done = 'Verified.\nPROJECT_TASK_SUBTASK_DONE';
  ToolResultInfo changed(String id) => ToolResultInfo(
    id: id,
    name: 'edit_file',
    arguments: const {},
    result: '{}',
    outcome: ToolOutcome(
      fileMutations: [
        ToolFileMutation(
          path: '/project/policy.md',
          changed: true,
          contentHash: id,
        ),
      ],
    ),
  );
  // An inline Python verifier with no working_directory argument reproduces
  // the failed check in the investigated session without its sensitive data.
  ToolResultInfo verify(
    String id,
    int exit, {
    String? command,
    String? stdout,
    String? directory,
  }) => ToolResultInfo(
    id: id,
    name: 'local_execute_command',
    arguments: {
      'command': command ?? 'cd /project && python3 -c "assert 1 == 1"',
    },
    result: jsonEncode({
      'exit_code': exit,
      'working_directory': ?directory,
      'stdout': stdout ?? (exit == 0 ? 'Verified.' : 'INCONSISTENCIES FOUND'),
    }),
    outcome: ToolOutcome(exitCode: exit),
  );
  ProjectTaskTerminalStatus status(
    List<ToolResultInfo> results, {
    String response = done,
  }) => policy.status(
    response: response,
    results: results,
    goal: goal,
    taskId: 'policy',
  );

  test('a declared false positive cannot settle an executed failure', () {
    final verdict = status([
      changed('edit'),
      verify('bad', 1),
    ], response: 'The check was a false positive.\nPROJECT_TASK_SUBTASK_DONE');
    expect(verdict.completionAccepted, isFalse);
    expect(verdict.gaps.join(' '), contains('exit 1'));
    expect(
      verdict.correctResponse(done),
      isNot(contains('PROJECT_TASK_SUBTASK_DONE')),
    );
    expect(
      policy.shouldRecover(
        status: verdict,
        goal: goal,
        boundarySafe: true,
        acknowledgement: null,
      ),
      isTrue,
    );
  });
  test('a passing rerun settles the failed inline verifier', () {
    final verdict = status([
      changed('edit'),
      verify('bad', 1),
      verify('good', 0),
    ]);
    expect(verdict.completionAccepted, isTrue);
    expect(verdict.gaps, isEmpty);
    expect(verdict.correctResponse(done), done);
    final recorded = ProjectTaskTerminalStatus.fromToolResults([
      verdict.toToolResult('status'),
    ])!;
    expect(recorded.isSubtask, isTrue);
    expect(recorded.subtaskId, 'policy');
    expect(recorded.completionAccepted, isTrue);
  });
  test('unrelated passing verification does not clear the failed check', () {
    expect(
      status([
        changed('edit'),
        verify('bad', 1),
        verify('other', 0, command: 'python3 verify_other.py'),
      ]).completionAccepted,
      isFalse,
    );
  });
  test('optional runtime lookup does not stall a verified subtask', () {
    final results = [
      changed('edit'),
      verify(
        'pytest-missing',
        1,
        command: 'cd /project && python3 -m pytest -q',
        directory: '/project',
      ),
      verify(
        'lookup',
        1,
        command:
            'cd /project && ls -a && which -a python3 python3.12 python3.13',
      ),
    ];
    expect(status(results).completionAccepted, isFalse);
    final verdict = status([
      ...results,
      verify(
        'pytest-passed',
        0,
        command: 'cd /project && .venv/bin/python -m pytest -q',
        directory: '/project',
        stdout: '53 passed in 0.1s',
      ),
    ]);
    expect(verdict.completionAccepted, isTrue, reason: verdict.gaps.join('\n'));
    expect(verdict.gaps, isEmpty);
    expect(goal.status, ConversationGoalStatus.active);
    expect(verdict.correctResponse(done), done);
  });
  test('execution must follow the latest mutation', () {
    expect(
      status([verify('before', 0), changed('edit')]).completionAccepted,
      isFalse,
    );
    expect(
      status([changed('edit'), verify('after', 0)]).completionAccepted,
      isTrue,
    );
  });
  test(
    'legacy mutations and timed out or running verification remain unfinished',
    () {
      final legacyEdit = ToolResultInfo(
        id: 'legacy',
        name: 'edit_file',
        arguments: const {'path': '/project/policy.md'},
        result: '{"path":"/project/policy.md","changed":true}',
      );
      expect(status([legacyEdit]).completionAccepted, isFalse);
      expect(
        status([legacyEdit, verify('after', 0)]).completionAccepted,
        isTrue,
      );
      expect(
        status([
          ToolResultInfo(
            id: 'timeout',
            name: 'local_execute_command',
            arguments: const {'command': 'python3 verify.py'},
            result: '{"timed_out":true,"exit_code":0}',
            outcome: const ToolOutcome(exitCode: 0),
          ),
        ]).completionAccepted,
        isFalse,
      );
      expect(
        status([
          ToolResultInfo(
            id: 'running',
            name: 'process_start',
            arguments: const {'command': 'python3 verify.py'},
            result:
                '{"status":"running","job_id":"job","command":"python3 verify.py","working_directory":"/project"}',
            outcome: const ToolOutcome(processState: ToolProcessState.running),
          ),
        ]).completionAccepted,
        isFalse,
      );
      expect(
        status([
          verify('old-failure', 1),
          changed('new-edit'),
          verify('other', 0, command: 'python3 verify_other.py'),
        ]).completionAccepted,
        isFalse,
      );
    },
  );
  test(
    'read-only investigation and existing-work steps need no artificial edit',
    () {
      expect(
        status([
          ToolResultInfo(
            id: 'read',
            name: 'read_file',
            arguments: const {},
            result: '{"content":"policy"}',
          ),
        ]).completionAccepted,
        isTrue,
      );
      expect(status([verify('existing', 0)]).completionAccepted, isTrue);
      expect(
        status(
          [],
          response: '<think>inspection</think>\n  PROJECT_TASK_SUBTASK_DONE  ',
        ).completionAccepted,
        isTrue,
      );
      expect(
        status(
          [],
          response: 'All done. PROJECT_TASK_SUBTASK_DONE',
        ).completionAccepted,
        isFalse,
      );
    },
  );
  test(
    'a future action without a final marker needs recovery in every language',
    () {
      for (final response in [
        'I will rerun the check.',
        '\u518d\u691c\u8a3c\u3057\u307e\u3059\u3002',
        'Voy a verificarlo.',
      ]) {
        expect(
          status([
            changed('edit'),
            verify('good', 0),
          ], response: response).completionAccepted,
          isFalse,
        );
      }
    },
  );
  test('unexecuted calls and unresolved diagnostics prevent acceptance', () {
    expect(
      status([
        ToolResultInfo(
          id: 'missing',
          name: 'local_execute_command',
          arguments: const {},
          result:
              '{"code":"tool_call_not_executed","reason":"bounded_tool_loop_exhausted"}',
        ),
      ]).completionAccepted,
      isFalse,
    );
    expect(
      status([
        ToolResultInfo(
          id: 'diagnostics',
          name: 'coding_output_feedback',
          arguments: const {},
          result: '{"diagnostics":[{"severity":"error","message":"Failed"}]}',
        ),
      ]).completionAccepted,
      isFalse,
    );
  });
  test('discarded redundant reads do not reopen a finished investigation', () {
    expect(
      status([
        ToolResultInfo(
          id: 'discarded',
          name: 'read_file',
          arguments: const {},
          result:
              '{"code":"tool_call_not_executed","reason":"bounded_tool_loop_exhausted","tool_name":"read_file"}',
        ),
      ]).completionAccepted,
      isTrue,
    );
  });
  test('unsafe, blocked and capped boundaries cannot recover', () {
    final verdict = status([], response: 'Remaining work.');
    expect(
      policy.shouldRecover(
        status: verdict,
        goal: goal,
        boundarySafe: false,
        acknowledgement: null,
      ),
      isFalse,
    );
    expect(
      policy.shouldRecover(
        status: verdict,
        goal: goal,
        boundarySafe: true,
        acknowledgement: GoalUpdateAckOutcome.blockerLogged,
      ),
      isFalse,
    );
    expect(
      policy.shouldRecover(
        status: verdict,
        goal: goal.copyWith(status: ConversationGoalStatus.completed),
        boundarySafe: true,
        acknowledgement: null,
      ),
      isFalse,
    );
  });
}
