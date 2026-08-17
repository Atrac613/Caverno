import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/uninspected_commit_guard.dart';

void main() {
  const guard = UninspectedCommitGuard();

  ToolCallInfo gitCall(String command) => ToolCallInfo(
    id: 'call-$command',
    name: 'git_execute_command',
    arguments: {'command': command},
  );

  ToolResultInfo gitResult(String command) => ToolResultInfo(
    id: 'result-$command',
    name: 'git_execute_command',
    arguments: {'command': command},
    result: '{"exit_code":0}',
  );

  ToolResultInfo mutation(String name) => ToolResultInfo(
    id: 'result-$name',
    name: name,
    arguments: const {'path': 'lib/app.dart'},
    result: '{"changed":true}',
  );

  Map<String, dynamic>? evaluate({
    required String command,
    required List<ToolResultInfo> results,
  }) {
    final blocked = guard.evaluate(
      UninspectedCommitInput(
        toolCall: gitCall(command),
        executedToolResults: results,
      ),
    );
    return blocked == null
        ? null
        : jsonDecode(blocked.result) as Map<String, dynamic>;
  }

  test('blocks a commit whose turn only saw file names', () {
    // Session 96797b74: status --short and diff --stat, then commit.
    final blocked = evaluate(
      command: 'commit -m "chore(flutter): bump"',
      results: [gitResult('status --short'), gitResult('diff --stat')],
    );

    expect(blocked, isNotNull);
    expect(blocked!['code'], UninspectedCommitGuard.blockedCode);
    expect(blocked['required_action'], contains('diff --cached'));
    expect(blocked['required_action'], contains('unrelated changes'));
  });

  test('allows a commit after a content diff', () {
    expect(
      evaluate(
        command: 'commit -m "fix: x"',
        results: [gitResult('status --short'), gitResult('diff --cached')],
      ),
      isNull,
    );
    expect(
      evaluate(command: 'commit -m "fix: x"', results: [gitResult('diff')]),
      isNull,
    );
    expect(
      evaluate(
        command: 'commit -m "fix: x"',
        results: [gitResult('show HEAD')],
      ),
      isNull,
    );
  });

  test('treats every summary-only diff form as not having looked', () {
    for (final summary in [
      'diff --stat',
      'diff --cached --stat',
      'diff --name-only',
      'diff --numstat',
      'diff --name-status',
      'diff --shortstat',
      'diff --dirstat=files',
    ]) {
      expect(
        evaluate(command: 'commit -m "x"', results: [gitResult(summary)]),
        isNotNull,
        reason: summary,
      );
    }
  });

  test('stays silent when the turn wrote the files itself', () {
    // The common edit-then-commit flow must not pay an extra round trip: a
    // model that just wrote the file knows what it is committing.
    for (final tool in ['write_file', 'edit_file']) {
      expect(
        evaluate(
          command: 'commit -m "feat: add"',
          results: [mutation(tool), gitResult('status --short')],
        ),
        isNull,
        reason: tool,
      );
    }
  });

  test('ignores git commands that are not a commit', () {
    for (final command in ['status --short', 'add .', 'push origin HEAD']) {
      expect(evaluate(command: command, results: const []), isNull);
    }
  });

  test('reads the commit subcommand through a leading git prefix', () {
    expect(
      evaluate(command: 'git commit -m "x"', results: const []),
      isNotNull,
    );
  });
}
