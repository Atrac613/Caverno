import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/presentation/providers/tool_approval_cache.dart';

void main() {
  final ownerA = ChatTurnOwner(
    conversationId: 'thread-a',
    interactionGeneration: 7,
  );
  final ownerB = ChatTurnOwner(
    conversationId: 'thread-b',
    interactionGeneration: 7,
  );
  final ownerA2 = ChatTurnOwner(
    conversationId: 'thread-a',
    interactionGeneration: 8,
  );

  group('ToolApprovalCache', () {
    test('reuses denial results when only reason changes', () {
      final cache = ToolApprovalCache();
      const result = McpToolResult(
        toolName: 'write_file',
        result: 'ok',
        isSuccess: false,
        errorMessage: 'User denied file write',
      );

      cache.rememberDenial(ownerA, 'write_file', {
        'path': 'lib/main.dart',
        'content': 'hello',
        'reason': 'Initial approval text',
      }, result);

      final cached = cache.lookup(ownerA, 'write_file', {
        'reason': 'Different approval text',
        'content': 'hello',
        'path': 'lib/main.dart',
      });

      expect(cached?.isApproved, isFalse);
      expect(cached?.denialResult, result);
    });

    test('normalizes nested map key order', () {
      final cache = ToolApprovalCache();
      cache.rememberApproval(ownerA, 'local_execute_command', {
        'working_directory': '/tmp/project',
        'command': 'dart test',
        'environment': {'B': '2', 'A': '1'},
      });

      final cached = cache.lookup(ownerA, 'local_execute_command', {
        'environment': {'A': '1', 'B': '2'},
        'command': 'dart test',
        'working_directory': '/tmp/project',
      });

      expect(cached?.isApproved, isTrue);
      expect(cached?.denialResult, isNull);
    });

    test('returns null for different execution arguments', () {
      final cache = ToolApprovalCache();
      cache.rememberApproval(ownerA, 'git_execute_command', {
        'command': 'git status',
        'working_directory': '/tmp/project',
      });

      final cached = cache.lookup(ownerA, 'git_execute_command', {
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
        ownerA,
        'edit_file',
        arguments,
        stateFingerprint: 'before-edit',
      );

      expect(
        cache
            .lookup(
              ownerA,
              'edit_file',
              arguments,
              stateFingerprint: 'before-edit',
            )
            ?.isApproved,
        isTrue,
      );
      expect(
        cache.lookup(
          ownerA,
          'edit_file',
          arguments,
          stateFingerprint: 'after-edit',
        ),
        isNull,
      );
    });

    test('isolates replacement by composite owner', () {
      final cache = ToolApprovalCache();
      const arguments = {'command': 'dart test'};
      const denied = McpToolResult(
        toolName: 'local_execute_command',
        result: 'denied-b',
        isSuccess: false,
      );
      const deniedA = McpToolResult(
        toolName: 'local_execute_command',
        result: 'denied-a',
        isSuccess: false,
      );

      cache.rememberApproval(ownerA, 'local_execute_command', arguments);
      expect(
        cache.rememberDenial(
          ownerB,
          'local_execute_command',
          arguments,
          denied,
        ),
        same(denied),
      );

      expect(
        cache.lookup(ownerA, 'local_execute_command', arguments)?.isApproved,
        isTrue,
      );
      expect(
        cache.lookup(ownerB, 'local_execute_command', arguments)?.denialResult,
        same(denied),
      );
      expect(cache.lookup(ownerA2, 'local_execute_command', arguments), isNull);

      cache.rememberApproval(ownerB, 'local_execute_command', arguments);
      cache.rememberDenial(ownerA, 'local_execute_command', arguments, deniedA);

      expect(
        cache.lookup(ownerA, 'local_execute_command', arguments)?.denialResult,
        same(deniedA),
      );
      expect(
        cache.lookup(ownerB, 'local_execute_command', arguments)?.isApproved,
        isTrue,
      );
    });

    test('normalizes every supported value shape within an owner', () {
      final cache = ToolApprovalCache();
      final stored = {
        'values': [
          null,
          3,
          true,
          'text',
          {
            'reason': 'ignored nested narration',
            'b': _StableValue('opaque'),
            'a': 1,
          },
        ],
      };
      final equivalent = {
        'values': [
          null,
          3,
          true,
          'text',
          {'a': 1, 'b': _StableValue('opaque'), 'reason': 'different'},
        ],
      };

      cache.rememberApproval(ownerA, 'custom_tool', stored);

      expect(
        cache.lookup(ownerA, 'custom_tool', equivalent)?.isApproved,
        isTrue,
      );
      expect(cache.lookup(ownerA, 'other_tool', equivalent), isNull);
      expect(
        cache.lookup(ownerA, 'custom_tool', {
          'values': [
            null,
            4,
            true,
            'text',
            {'a': 1, 'b': _StableValue('opaque')},
          ],
        }),
        isNull,
      );
    });

    test('binds state fingerprints to the exact owner', () {
      final cache = ToolApprovalCache();
      const arguments = {'path': 'pubspec.yaml'};

      cache.rememberApproval(
        ownerA,
        'edit_file',
        arguments,
        stateFingerprint: 'before-edit',
      );

      expect(
        cache.lookup(
          ownerA,
          'edit_file',
          arguments,
          stateFingerprint: 'before-edit',
        ),
        isNotNull,
      );
      expect(cache.lookup(ownerA, 'edit_file', arguments), isNull);
      expect(
        cache.lookup(
          ownerB,
          'edit_file',
          arguments,
          stateFingerprint: 'before-edit',
        ),
        isNull,
      );
      expect(
        cache.lookup(
          ownerA2,
          'edit_file',
          arguments,
          stateFingerprint: 'before-edit',
        ),
        isNull,
      );
    });

    test('clears one owner without affecting equal-generation peers', () {
      final cache = ToolApprovalCache();
      cache
        ..rememberApproval(ownerA, 'write_file', const {'path': 'a.txt'})
        ..rememberApproval(ownerA, 'edit_file', const {'path': 'a.txt'})
        ..rememberApproval(ownerB, 'write_file', const {'path': 'b.txt'})
        ..rememberApproval(ownerA2, 'write_file', const {'path': 'a2.txt'});

      expect(cache.clear(ownerA), isTrue);
      expect(cache.clear(ownerA), isFalse);
      expect(
        cache.lookup(ownerA, 'write_file', const {'path': 'a.txt'}),
        isNull,
      );
      expect(
        cache.lookup(ownerA, 'edit_file', const {'path': 'a.txt'}),
        isNull,
      );
      expect(
        cache.lookup(ownerB, 'write_file', const {'path': 'b.txt'}),
        isNotNull,
      );
      expect(
        cache.lookup(ownerA2, 'write_file', const {'path': 'a2.txt'}),
        isNotNull,
      );
    });

    test('clears every owner globally', () {
      final cache = ToolApprovalCache();
      cache
        ..rememberApproval(ownerA, 'write_file', const {'path': 'a.txt'})
        ..rememberApproval(ownerB, 'write_file', const {'path': 'b.txt'});

      cache
        ..clearAll()
        ..clearAll();

      expect(
        cache.lookup(ownerA, 'write_file', const {'path': 'a.txt'}),
        isNull,
      );
      expect(
        cache.lookup(ownerB, 'write_file', const {'path': 'b.txt'}),
        isNull,
      );
    });

    test('owner-bound capability preserves result and denial behavior', () {
      final cache = ToolApprovalCache();
      final approvals = cache.forOwner(ownerA);
      const arguments = {'command': 'dart test'};
      const success = McpToolResult(
        toolName: 'local_execute_command',
        result: 'passed',
        isSuccess: true,
      );
      const denial = McpToolResult(
        toolName: 'local_execute_command',
        result: 'denied',
        isSuccess: false,
      );

      expect(approvals.owner, ownerA);
      expect(
        approvals.rememberResult('local_execute_command', arguments, success),
        same(success),
      );
      expect(
        approvals.lookup('local_execute_command', arguments)?.isApproved,
        isTrue,
      );
      expect(
        approvals.rememberDenial('local_execute_command', arguments, denial),
        same(denial),
      );
      expect(
        approvals.lookupDenial('local_execute_command', arguments),
        same(denial),
      );
      expect(
        approvals.lookupDenial(
          'local_execute_command',
          arguments,
          stateFingerprint: 'different',
        ),
        isNull,
      );
    });

    test('owner-local clear revokes the issued capability', () {
      final cache = ToolApprovalCache();
      final approvals = cache.forOwner(ownerA);
      const arguments = {'command': 'dart test'};
      const success = McpToolResult(
        toolName: 'local_execute_command',
        result: 'passed',
        isSuccess: true,
      );
      const denial = McpToolResult(
        toolName: 'local_execute_command',
        result: 'denied',
        isSuccess: false,
      );

      approvals.rememberResult('local_execute_command', arguments, success);

      expect(cache.clear(ownerA), isTrue);
      expect(
        approvals.rememberResult('local_execute_command', arguments, success),
        same(success),
      );
      expect(
        approvals.rememberDenial('local_execute_command', arguments, denial),
        same(denial),
      );
      expect(approvals.lookup('local_execute_command', arguments), isNull);
      expect(
        approvals.lookupDenial('local_execute_command', arguments),
        isNull,
      );
      expect(cache.lookup(ownerA, 'local_execute_command', arguments), isNull);

      final replacement = cache.forOwner(ownerA);
      expect(replacement, isNot(same(approvals)));
      replacement.rememberResult('local_execute_command', arguments, success);
      expect(
        replacement.lookup('local_execute_command', arguments)?.isApproved,
        isTrue,
      );
    });

    test('global clear revokes every issued capability', () {
      final cache = ToolApprovalCache();
      final approvalsA = cache.forOwner(ownerA);
      final approvalsB = cache.forOwner(ownerB);
      const arguments = {'path': 'lib/main.dart'};
      const result = McpToolResult(
        toolName: 'write_file',
        result: 'ok',
        isSuccess: true,
      );

      approvalsA.rememberResult('write_file', arguments, result);
      approvalsB.rememberResult('write_file', arguments, result);
      cache
        ..clearAll()
        ..clearAll();

      approvalsA.rememberResult('write_file', arguments, result);
      approvalsB.rememberResult('write_file', arguments, result);
      expect(approvalsA.lookup('write_file', arguments), isNull);
      expect(approvalsB.lookup('write_file', arguments), isNull);
    });
  });
}

final class _StableValue {
  const _StableValue(this.value);

  final String value;

  @override
  String toString() => value;
}
