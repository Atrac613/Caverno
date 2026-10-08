import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/claims/uninspected_commit_guard.dart';
import 'package:caverno/features/chat/domain/services/tool_loop/tool_failure_classifier.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const guard = UninspectedCommitGuard();

  ToolCallInfo gitCall(String command) => ToolCallInfo(
    id: 'call-$command',
    name: 'git_execute_command',
    arguments: {'command': command},
  );

  ToolResultInfo gitResult(
    String command, {
    String stdout = 'diff --git a/lib/app.dart b/lib/app.dart',
  }) => ToolResultInfo(
    id: 'result-$command',
    name: 'git_execute_command',
    arguments: {'command': command},
    result: jsonEncode({'exit_code': 0, 'stdout': stdout, 'stderr': ''}),
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

  test('an empty diff is not a look at the content', () {
    // Session 23d19ede: after `git add`, a bare `git diff` printed nothing
    // because every change was staged, and it still unlocked the commit.
    expect(
      evaluate(
        command: 'commit -m "chore: release 1.3.43+57"',
        results: [
          gitResult('add pubspec.yaml'),
          gitResult('diff', stdout: ''),
        ],
      ),
      isNotNull,
    );
    expect(
      evaluate(
        command: 'commit -m "x"',
        results: [gitResult('diff --cached', stdout: '  \n')],
      ),
      isNotNull,
    );
    expect(
      evaluate(
        command: 'commit -m "x"',
        results: [
          gitResult('diff', stdout: ''),
          gitResult('diff --cached'),
        ],
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

  test('declares the block as a refusal, not as a commit that ran', () {
    // Session dd50d110: reported as a success, the block was filed as an
    // executed commit, so the same commit re-issued after `diff --cached` was
    // skipped as a duplicate and this refusal replayed in its place.
    final toolCall = gitCall('commit -m "chore: bump"');
    final blocked = guard.evaluate(
      UninspectedCommitInput(toolCall: toolCall, executedToolResults: const []),
    )!;
    final payload = jsonDecode(blocked.result) as Map<String, dynamic>;
    const classifier = ToolFailureClassifier();

    expect(blocked.isSuccess, isFalse);
    expect(payload['ok'], isFalse);
    expect(ToolResultOrigin.fromPayload(payload), ToolResultOrigin.refusal);
    expect(
      classifier.classify(toolCall, blocked),
      ToolResultDisposition.approvalDenied,
    );
    expect(
      classifier.policyRefusal(blocked)?.requiredAction,
      contains('diff --cached'),
    );
  });
}
