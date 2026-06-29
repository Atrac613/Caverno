import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/planning_tool_policy.dart';

void main() {
  const policy = PlanningToolPolicy();

  group('PlanningToolPolicy', () {
    test('does not enforce outside planning sessions', () {
      final result = policy.enforce(
        _toolCall('write_file'),
        isPlanningSession: false,
        resolveArguments: _identityResolver,
      );

      expect(result, isNull);
    });

    test('allows read-only planning tools', () {
      final result = policy.enforce(
        _toolCall('read_file'),
        isPlanningSession: true,
        resolveArguments: _identityResolver,
      );

      expect(result, isNull);
    });

    test('blocks direct file mutation tools', () {
      final result = policy.enforce(
        _toolCall('write_file'),
        isPlanningSession: true,
        resolveArguments: _identityResolver,
      );

      expect(result, isNotNull);
      expect(result!.toolName, 'write_file');
      expect(result.isSuccess, isFalse);
      expect(_payload(result), containsPair('tool', 'write_file'));
      expect(
        _payload(result),
        containsPair('reason', 'planning_mode_requires_read_only_tools'),
      );
    });

    test('allows read-only local commands after argument resolution', () {
      final result = policy.enforce(
        _toolCall('local_execute_command', {'command': 'rm -rf build'}),
        isPlanningSession: true,
        resolveArguments: (_, _) => {'command': 'pwd'},
      );

      expect(result, isNull);
    });

    test('blocks write local commands', () {
      final result = policy.enforce(
        _toolCall('local_execute_command', {'command': 'rm -rf build'}),
        isPlanningSession: true,
        resolveArguments: _identityResolver,
      );

      expect(result, isNotNull);
      expect(
        result!.errorMessage,
        'Planning mode blocked local command: rm -rf build',
      );
      expect(
        _payload(result),
        containsPair(
          'detail',
          'Planning mode blocked local command: rm -rf build',
        ),
      );
    });

    test('allows read-only git commands after argument resolution', () {
      final result = policy.enforce(
        _toolCall('git_execute_command', {'command': 'commit -m test'}),
        isPlanningSession: true,
        resolveArguments: (_, _) => {'command': 'git status --short'},
      );

      expect(result, isNull);
    });

    test('blocks write git commands', () {
      final result = policy.enforce(
        _toolCall('git_execute_command', {'command': 'commit -m test'}),
        isPlanningSession: true,
        resolveArguments: _identityResolver,
      );

      expect(result, isNotNull);
      expect(
        result!.errorMessage,
        'Planning mode blocked git command: git commit -m test',
      );
      expect(
        _payload(result),
        containsPair(
          'detail',
          'Planning mode blocked git command: git commit -m test',
        ),
      );
    });

    test('blocks worktree finish tool', () {
      final result = policy.enforce(
        _toolCall('git_finish_worktree_session', {
          'worktree_path': '/tmp/repo-worktree',
        }),
        isPlanningSession: true,
        resolveArguments: _identityResolver,
      );

      expect(result, isNotNull);
      expect(
        result!.errorMessage,
        'Planning mode cannot merge or remove git worktree sessions.',
      );
    });

    test('allows computer observation tools and blocks computer actions', () {
      final observationResult = policy.enforce(
        _toolCall('computer_screenshot'),
        isPlanningSession: true,
        resolveArguments: _identityResolver,
      );
      final actionResult = policy.enforce(
        _toolCall('computer_click'),
        isPlanningSession: true,
        resolveArguments: _identityResolver,
      );

      expect(observationResult, isNull);
      expect(actionResult, isNotNull);
      expect(
        _payload(actionResult!),
        containsPair(
          'detail',
          'Planning mode allows only macOS computer-use observation tools.',
        ),
      );
    });

    test('blocks network write and device transport tools', () {
      for (final toolName in const [
        'http_post',
        'ssh_execute_command',
        'ble_connect',
      ]) {
        final result = policy.enforce(
          _toolCall(toolName),
          isPlanningSession: true,
          resolveArguments: _identityResolver,
        );

        expect(result, isNotNull, reason: toolName);
        expect(result!.toolName, toolName);
      }
    });
  });
}

ToolCallInfo _toolCall(
  String name, [
  Map<String, dynamic> arguments = const {},
]) {
  return ToolCallInfo(id: 'tool-$name', name: name, arguments: arguments);
}

Map<String, dynamic> _identityResolver(
  String toolName,
  Map<String, dynamic> arguments,
) {
  return arguments;
}

Map<String, dynamic> _payload(McpToolResult result) {
  return jsonDecode(result.result) as Map<String, dynamic>;
}
