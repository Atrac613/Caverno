import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/tool_loop_abort_notice.dart';
import 'package:flutter_test/flutter_test.dart';

ToolResultInfo _edit(String path, {bool succeeded = true}) => ToolResultInfo(
  id: 'call-$path',
  name: 'edit_file',
  arguments: {'path': path},
  result: succeeded
      ? jsonEncode({'path': path, 'replacements': 2, 'changed': true})
      : jsonEncode({
          'error': 'old_text was not found in the target file',
          'path': path,
        }),
);

void main() {
  const notice = ToolLoopAbortNotice();

  group('ToolLoopAbortNotice', () {
    // The reported failure: `edit_file` could not find its `old_text` in a
    // local file, and the abort told the user to check their server
    // configuration — sending them to the LLM endpoint for a local edit.
    test('does not blame a server for a built-in tool refusing arguments', () {
      final message = notice.build(
        toolName: 'edit_file',
        errorMessage: 'old_text was not found in the target file',
        isApprovalDenial: false,
        isExternalMcpResult: false,
        executedToolResults: const [],
      );

      expect(message, contains('The tool (edit_file) failed twice'));
      expect(message, contains('not a server or endpoint problem'));
      expect(message, contains('old_text was not found in the target file'));
      expect(message, isNot(contains('server configuration')));
    });

    test('points at the MCP server when the failing tool came from one', () {
      final message = notice.build(
        toolName: 'remote_thing',
        errorMessage: 'connection refused',
        isApprovalDenial: false,
        isExternalMcpResult: true,
        executedToolResults: const [],
      );

      expect(message, contains('MCP server providing it is reachable'));
      expect(message, contains('connection refused'));
    });

    test('keeps the approval-denial guidance distinct from a failure', () {
      final message = notice.build(
        toolName: 'local_execute_command',
        errorMessage: 'denied by policy',
        isApprovalDenial: true,
        isExternalMcpResult: false,
        executedToolResults: const [],
      );

      expect(message, contains('blocked by approval'));
      expect(message, contains('Reason: denied by policy'));
      expect(message, isNot(contains('failed twice')));
    });

    // An abort can follow several successful edits. Reporting only the
    // failure leaves the user with mutated files they were never told about.
    test('reports the files the turn already changed', () {
      final message = notice.build(
        toolName: 'edit_file',
        errorMessage: 'old_text was not found in the target file',
        isApprovalDenial: false,
        isExternalMcpResult: false,
        executedToolResults: [
          _edit('/repo/README.md'),
          _edit('/repo/scripts/deploy_macos.py', succeeded: false),
          _edit('/repo/tests/test_agent_kb.py'),
        ],
      );

      expect(
        message,
        contains(
          'Already changed in this turn: /repo/README.md, '
          '/repo/tests/test_agent_kb.py',
        ),
      );
    });

    test('omits the changed-files line when nothing was written', () {
      final message = notice.build(
        toolName: 'edit_file',
        errorMessage: 'old_text was not found in the target file',
        isApprovalDenial: false,
        isExternalMcpResult: false,
        executedToolResults: [
          _edit('/repo/only_failed.md', succeeded: false),
        ],
      );

      expect(message, isNot(contains('Already changed')));
    });

    test('lists a repeatedly edited file once, in write order', () {
      final paths = notice.changedFilePaths([
        _edit('/repo/b.md'),
        _edit('/repo/a.md'),
        _edit('/repo/b.md'),
      ]);

      expect(paths, ['/repo/b.md', '/repo/a.md']);
    });

    test('ignores read-only tools that touched the same paths', () {
      final paths = notice.changedFilePaths([
        ToolResultInfo(
          id: 'read',
          name: 'read_file',
          arguments: const {'path': '/repo/README.md'},
          result: jsonEncode({'path': '/repo/README.md', 'content': 'x'}),
        ),
      ]);

      expect(paths, isEmpty);
    });
  });
}
