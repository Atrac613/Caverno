import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/presentation/providers/tool_approval_cache.dart';

void main() {
  group('ToolApprovalCache', () {
    test('reuses the same result when only reason changes', () {
      final cache = ToolApprovalCache();
      const result = McpToolResult(
        toolName: 'write_file',
        result: 'ok',
        isSuccess: true,
      );

      cache.remember('write_file', {
        'path': 'lib/main.dart',
        'content': 'hello',
        'reason': 'Initial approval text',
      }, result);

      final cached = cache.lookup('write_file', {
        'reason': 'Different approval text',
        'content': 'hello',
        'path': 'lib/main.dart',
      });

      expect(cached, result);
    });

    test('normalizes nested map key order', () {
      final cache = ToolApprovalCache();
      const result = McpToolResult(
        toolName: 'local_execute_command',
        result: 'done',
        isSuccess: true,
      );

      cache.remember('local_execute_command', {
        'working_directory': '/tmp/project',
        'command': 'dart test',
        'environment': {'B': '2', 'A': '1'},
      }, result);

      final cached = cache.lookup('local_execute_command', {
        'environment': {'A': '1', 'B': '2'},
        'command': 'dart test',
        'working_directory': '/tmp/project',
      });

      expect(cached, result);
    });

    test('returns null for different execution arguments', () {
      final cache = ToolApprovalCache();
      const result = McpToolResult(
        toolName: 'git_execute_command',
        result: 'ok',
        isSuccess: true,
      );

      cache.remember('git_execute_command', {
        'command': 'git status',
        'working_directory': '/tmp/project',
      }, result);

      final cached = cache.lookup('git_execute_command', {
        'command': 'git add .',
        'working_directory': '/tmp/project',
      });

      expect(cached, isNull);
    });
  });
}
