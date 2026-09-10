import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/subagent_task.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/subagent_command_observation.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'mutation tracking distinguishes refused writes and confirmed effects',
    () {
      final write = ToolCallInfo(
        id: 'write',
        name: 'write_file',
        arguments: const {'path': 'count_field.py', 'content': 'updated'},
      );
      expect(
        SubagentCommandObservation.changesWorkspace(
          write,
          McpToolResult(
            toolName: write.name,
            result: 'refused',
            isSuccess: false,
          ),
        ),
        isFalse,
      );
      expect(
        SubagentCommandObservation.changesWorkspace(
          write,
          McpToolResult(
            toolName: write.name,
            result: 'written',
            isSuccess: true,
          ),
        ),
        isTrue,
      );
      expect(
        SubagentCommandObservation.changesWorkspace(
          write,
          McpToolResult(
            toolName: write.name,
            result: 'failed after write',
            isSuccess: false,
            outcome: const ToolOutcome(
              fileMutations: [
                ToolFileMutation(path: 'count_field.py', changed: true),
              ],
            ),
          ),
        ),
        isTrue,
      );
      final read = ToolCallInfo(
        id: 'read',
        name: 'read_file',
        arguments: const {'path': 'count_field.py'},
      );
      expect(
        SubagentCommandObservation.changesWorkspace(
          read,
          McpToolResult(
            toolName: read.name,
            result: 'contents',
            isSuccess: true,
          ),
        ),
        isFalse,
      );
    },
  );

  final task = SubagentTask(id: 'child', description: 'Verify');
  McpToolResult result(int code) => McpToolResult(
    toolName: 'local_execute_command',
    result: '',
    isSuccess: code == 0,
    outcome: ToolOutcome(exitCode: code),
  );
  ToolCallInfo call(String command) => ToolCallInfo(
    id: 'cmd',
    name: 'local_execute_command',
    arguments: {'command': command},
  );
  test('trailing echo cannot promote masked command failures', () {
    final observation = SubagentCommandObservation();
    observation.observe(
      call('python3 count_field.py level sample.jsonl; echo "exit=\$?"'),
      result(0),
    );
    expect(observation.completed('spawn_subagent', task).outcome, isNull);
  });
  test('later failure supersedes earlier command success', () {
    final observation = SubagentCommandObservation();
    observation.observe(call('python3 -m unittest'), result(0));
    expect(observation.completed('spawn_subagent', task).outcome?.exitCode, 0);
    observation.observe(
      call('python3 count_field.py level sample.jsonl'),
      result(1),
    );
    expect(observation.completed('spawn_subagent', task).outcome, isNull);
  });
  test('file mutation invalidates an earlier observation', () {
    final observation = SubagentCommandObservation();
    observation.observe(call('python3 -m unittest'), result(0));
    observation.observe(
      ToolCallInfo(
        id: 'write',
        name: 'write_file',
        arguments: {'path': 'count_field.py', 'content': 'broken'},
      ),
      result(0),
    );
    expect(observation.completed('spawn_subagent', task).outcome, isNull);
  });
}
