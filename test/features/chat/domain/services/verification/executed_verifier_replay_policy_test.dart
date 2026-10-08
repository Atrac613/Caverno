import 'dart:convert';

import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/goal/goal_auto_continue_tracker_registry.dart';
import 'package:caverno/features/chat/domain/services/tool_results/tool_result_prompt_builder.dart';
import 'package:caverno/features/chat/domain/services/verification/executed_verifier_replay_policy.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final call = ToolCallInfo(
    id: 'verified',
    name: 'local_execute_command',
    arguments: {
      'command':
          'cd /project && .venv/bin/python -m pytest test.py -v 2>&1 | tail -30',
    },
  );
  McpToolResult result({
    int exit = 0,
    String output = '====== 6 passed in 3.05s ======',
  }) => McpToolResult(
    toolName: call.name,
    isSuccess: true,
    result: jsonEncode({'working_directory': '/parent', 'stdout': output}),
    outcome: ToolOutcome(exitCode: exit),
  );

  test('replays the successful runner without cd, tail or redirection', () {
    final replay = ExecutedVerifierReplayPolicy.prepare(call, result())!;
    expect(replay.arguments['working_directory'], '/project');
    expect(
      replay.arguments['command'],
      '.venv/bin/python -m pytest test.py -v',
    );
    expect(
      GoalAutoContinueTrackerRegistry(
        replayIdFactory: (generation) => '$generation',
      ).isReplayEligibleVerifierToolCall(replay),
      isTrue,
    );
  });
  for (final output in [
    'python3: No module named pytest',
    '====== 2 failed, 4 passed in 3.05s ======',
    'done',
  ]) {
    test('does not replace a replay candidate with $output', () {
      expect(
        ExecutedVerifierReplayPolicy.prepare(call, result(output: output)),
        isNull,
      );
    });
  }
  test('requires a successful typed exit', () {
    expect(ExecutedVerifierReplayPolicy.prepare(call, result(exit: 1)), isNull);
  });
  test(
    'post-mutation replay retains the working runner after a failed retry',
    () {
      final registry = GoalAutoContinueTrackerRegistry(
        replayIdFactory: (_) => 'replay',
      );
      final context = (
        owner: ChatTurnOwner(conversationId: 'task', interactionGeneration: 1),
        workspaceMode: WorkspaceMode.coding,
        activeTaskId: 'task-id',
        mutationGeneration: 1,
        verificationGeneration: 0,
      );
      for (final response in [
        result(),
        result(exit: 1, output: 'No module named pytest'),
      ]) {
        final candidate = ExecutedVerifierReplayPolicy.prepare(call, response);
        if (candidate != null) {
          registry.recordExecutedVerifierReplayCandidate(
            context: context,
            toolCall: candidate,
          );
        }
      }
      final selected = registry.takePostMutationVerifierReplay(
        context: context,
        evidence: const ToolResultCompletionEvidence(
          mutatedWithoutExecutionVerification: true,
        ),
      );
      expect(selected?.toolCall.arguments['working_directory'], '/project');
      expect(
        selected?.toolCall.arguments['command'],
        contains('.venv/bin/python'),
      );
    },
  );
}
