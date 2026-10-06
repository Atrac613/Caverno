import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/tool_loop_recovery_policy.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const policy = ToolLoopRecoveryPolicy();
  const file = '/repo/source.py';
  ToolResultInfo read({
    String id = 'read',
    String path = file,
    String content = 'interval = 2\n',
    List<String> changes = const [],
    String? error,
  }) => ToolResultInfo(
    id: id,
    name: 'read_file',
    arguments: {'path': path, 'offset': 1, 'limit': 20},
    result: jsonEncode({
      'path': file,
      if (error == null) 'content': content else 'error': error,
      'content_hash': content,
    }),
    changesSinceCapture: changes,
  );
  ToolResultInfo edit({bool changed = true, bool failed = false}) =>
      ToolResultInfo(
        id: 'edit',
        name: 'edit_file',
        arguments: const {'path': 'source.py'},
        result: jsonEncode({
          if (failed) 'error': 'permission_denied' else 'changed': changed,
        }),
        outcome: failed
            ? null
            : ToolOutcome(
                fileMutations: [
                  ToolFileMutation(
                    path: file,
                    contentHash: 'updated',
                    changed: changed,
                  ),
                ],
              ),
      );
  final mismatch = ToolResultInfo(
    id: 'mismatch',
    name: 'edit_file',
    arguments: const {'path': 'source.py'},
    result: '{"error":"old_text was not found in the target file"}',
  );
  List<ToolResultInfo> recover(
    List<ToolResultInfo> ledger, {
    String pendingPath = './source.py',
  }) => policy.buildRecoveryToolResults(
    currentToolResults: [mismatch],
    executedToolResults: ledger,
    pendingToolCalls: [
      ToolCallInfo(
        id: 'pending',
        name: 'read_file',
        arguments: {'path': pendingPath},
      ),
    ],
    pathFromArguments: (value) =>
        value is Map ? value['path'] as String? : null,
    toolResultKey: (value) => value.id,
    projectRoot: '/repo',
  );
  String prompt(List<ToolResultInfo> results) =>
      policy.buildExhaustionRecoveryPrompt(
        const [],
        previousToolResults: results,
        projectRoot: '/repo',
      );

  test(
    'a successful edit invalidates the earlier read across path aliases',
    () {
      final results = recover([read(), edit(), mismatch]);
      expect(results.map((value) => value.id), ['mismatch']);
      expect(prompt(results), contains('No current read has been established'));
      expect(prompt(results), isNot(contains('A current read_file result')));
    },
  );

  test('the read after the edit is retained as historical current context', () {
    final results = recover([
      read(id: 'old'),
      edit(),
      read(id: 'fresh', path: './source.py', content: 'interval = 0\n'),
      mismatch,
    ]);
    expect(results.map((value) => value.id), ['fresh', 'mismatch']);
    expect(results.first.fromEarlierLoop, isTrue);
    expect(results.first.result, contains('interval = 0'));
    expect(prompt(results), contains('A current read_file result'));
    expect(prompt(results), contains('read that missing range'));
    expect(prompt(results), isNot(contains('Do not call read_file again')));
  });

  test(
    'the observed path invalidates a read requested through another alias',
    () {
      expect(
        recover([
          read(path: '/alias/source.py'),
          edit(),
        ], pendingPath: '/alias/source.py').map((value) => value.id),
        ['mismatch'],
      );
    },
  );

  for (final mutation in [edit(changed: false), edit(failed: true)]) {
    test(
      'an unchanged or denied edit leaves the prior read usable ${mutation.result}',
      () {
        expect(recover([read(), mutation]).first.id, 'read');
      },
    );
  }

  for (final command in ['python mutate.py', 'git checkout other']) {
    test(
      'an executed command with unknown writes invalidates prior reads: $command',
      () {
        final execution = ToolResultInfo(
          id: 'command',
          name: command.startsWith('git ')
              ? 'git_execute_command'
              : 'local_execute_command',
          arguments: {
            'command': command.startsWith('git ')
                ? command.substring(4)
                : command,
          },
          result: '{"exit_code":1}',
          outcome: ToolOutcome(exitCode: 1),
        );
        expect(recover([read(), execution]).map((value) => value.id), [
          'mismatch',
        ]);
      },
    );
  }

  test(
    'a read-only command and a refused command do not invalidate a read',
    () {
      for (final command in [
        ToolResultInfo(
          id: 'status',
          name: 'git_execute_command',
          arguments: const {'command': 'status --short'},
          result: '{"exit_code":0}',
        ),
        ToolResultInfo(
          id: 'refused',
          name: 'local_execute_command',
          arguments: const {'command': 'python mutate.py'},
          result: '{"result_origin":"harness","code":"tool_call_not_executed"}',
        ),
      ]) {
        expect(recover([read(), command]).first.id, 'read');
      }
    },
  );

  test(
    'labelled stale and failed newest reads cannot revive an older read',
    () {
      for (final latest in [
        read(id: 'stale', changes: ['edit_file $file']),
        read(id: 'denied', error: 'permission_denied'),
      ]) {
        expect(recover([read(id: 'old'), latest]).map((value) => value.id), [
          'mismatch',
        ]);
      }
    },
  );

  test('an unrelated read cannot establish context for a failed edit', () {
    expect(
      prompt([read(path: '/repo/other.py'), mismatch]),
      contains('No current read has been established'),
    );
  });
}
