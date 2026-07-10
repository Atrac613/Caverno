import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/presentation/providers/tool_approval_cache.dart';

void main() {
  group('ToolApprovalCache', () {
    test('reuses denial results when only reason changes', () {
      final cache = ToolApprovalCache();
      const result = McpToolResult(
        toolName: 'write_file',
        result: 'ok',
        isSuccess: false,
        errorMessage: 'User denied file write',
      );

      cache.rememberDenial('write_file', {
        'path': 'lib/main.dart',
        'content': 'hello',
        'reason': 'Initial approval text',
      }, result);

      final cached = cache.lookup('write_file', {
        'reason': 'Different approval text',
        'content': 'hello',
        'path': 'lib/main.dart',
      });

      expect(cached?.isApproved, isFalse);
      expect(cached?.denialResult, result);
    });

    test('normalizes nested map key order', () {
      final cache = ToolApprovalCache();
      cache.rememberApproval('local_execute_command', {
        'working_directory': '/tmp/project',
        'command': 'dart test',
        'environment': {'B': '2', 'A': '1'},
      });

      final cached = cache.lookup('local_execute_command', {
        'environment': {'A': '1', 'B': '2'},
        'command': 'dart test',
        'working_directory': '/tmp/project',
      });

      expect(cached?.isApproved, isTrue);
      expect(cached?.denialResult, isNull);
    });

    test('returns null for different execution arguments', () {
      final cache = ToolApprovalCache();
      cache.rememberApproval('git_execute_command', {
        'command': 'git status',
        'working_directory': '/tmp/project',
      });

      final cached = cache.lookup('git_execute_command', {
        'command': 'git add .',
        'working_directory': '/tmp/project',
      });

      expect(cached, isNull);
    });

    test('binds file approvals to the supplied state fingerprint', () {
      final cache = ToolApprovalCache();
      const arguments = {
        'path': 'pubspec.yaml',
        'old_text': 'name: todo',
        'new_text': 'name: todo_app',
      };
      cache.rememberApproval(
        'edit_file',
        arguments,
        stateFingerprint: 'before-edit',
      );

      expect(
        cache
            .lookup('edit_file', arguments, stateFingerprint: 'before-edit')
            ?.isApproved,
        isTrue,
      );
      expect(
        cache.lookup('edit_file', arguments, stateFingerprint: 'after-edit'),
        isNull,
      );
    });
  });
}
