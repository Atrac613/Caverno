import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/data/datasources/local_shell_tools.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/command_verification_reconciliation.dart';
import 'package:caverno/features/chat/domain/services/goal_update_tool_handler.dart';
import 'package:caverno/features/chat/domain/services/local_command/literal_shell_words.dart';
import 'package:caverno/features/chat/domain/services/python/inline_python_verification_contract.dart';
import 'package:caverno/features/chat/domain/services/tool_result_prompt_builder.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

const _checks = '''assert '[INFO]' in records, 'INFO missing'
assert 'worker' in records, 'module missing'
print('All checks passed')
''';

String _inline({
  String fixture = 'from worker import emit\nrecords = emit()',
  String checks = _checks,
  String interpreter = 'python3',
}) => '$interpreter -c "$fixture\n$checks" 2>&1';

ToolResultInfo _run(String id, String command, int exitCode) => ToolResultInfo(
  id: id,
  name: 'local_execute_command',
  arguments: {'command': command, 'working_directory': '/workspace'},
  result: jsonEncode({
    'command': command,
    'working_directory': '/workspace',
    'exit_code': exitCode,
    'stdout': exitCode == 0 ? 'All checks passed' : 'AssertionError',
  }),
  outcome: ToolOutcome(exitCode: exitCode),
);

void main() {
  test('repairs fixture names while retaining the exact check block', () {
    final failed = _run(
      'failed',
      _inline(fixture: 'from worker import missing\nrecords = missing()'),
      1,
    );
    final passed = _run('passed', _inline(), 0);
    final original = [failed, passed];
    expect(
      CommandVerificationReconciliation.currentResults(
        original,
      ).map((result) => result.id),
      ['passed'],
    );
    expect(original, hasLength(2), reason: 'the audit evidence is preserved');
    final evidence = ToolResultPromptBuilder.completionEvidence(original);
    expect(evidence.hasFailedExecutionVerification, isFalse);
    expect(evidence.hasSuccessfulExecutionVerification, isTrue);
  });

  test(
    'additional imports cover earlier fixtures without dropping modules',
    () {
      final failed = _run(
        'failed',
        _inline(fixture: "import os\nfrom worker import emit\nrecords = ''"),
        1,
      );
      final passed = _run(
        'passed',
        _inline(
          fixture:
              'import os, logging\nfrom worker import emit\nrecords = emit()',
        ),
        0,
      );
      expect(
        CommandVerificationReconciliation.currentResults([
          failed,
          passed,
        ]).map((result) => result.id),
        ['passed'],
      );
      expect(
        CommandVerificationReconciliation.currentResults([
          failed,
          _run('dropped', _inline(), 0),
        ]).map((result) => result.id),
        ['failed', 'dropped'],
      );
    },
  );

  test(
    'a later failed repair still blocks completion after a passing repair',
    () {
      final results = [
        _run(
          'failed',
          _inline(fixture: "from worker import emit\nrecords = ''"),
          1,
        ),
        _run('passed', _inline(), 0),
        _run(
          'later-failed',
          _inline(fixture: "from worker import emit\nrecords = ''"),
          1,
        ),
      ];
      expect(
        ToolResultPromptBuilder.completionEvidence(
          results,
        ).hasFailedExecutionVerification,
        isTrue,
      );
      expect(
        CommandVerificationReconciliation.currentResults(
          results,
        ).map((result) => result.id),
        ['passed', 'later-failed'],
      );
    },
  );

  for (final variant in [
    'drop check',
    'weaken check',
    'literal whitespace',
    'other module',
    'other interpreter',
    'disabled asserts',
    'early exit',
    'dynamic fixture',
    'shell chain',
    'unquoted newline',
    'different check mechanism',
  ]) {
    test('keeps the old failure for $variant', () {
      final candidate = switch (variant) {
        'drop check' => _inline(checks: _checks.split('\n').skip(1).join('\n')),
        'weaken check' => _inline(checks: _checks.replaceFirst('[INFO]', '')),
        'literal whitespace' => _inline(
          checks: _checks.replaceFirst('INFO missing', 'INFO  missing'),
        ),
        'other module' => _inline(
          fixture: 'from other import emit\nrecords = emit()',
        ),
        'other interpreter' => _inline(interpreter: '.venv/bin/python'),
        'disabled asserts' => _inline(interpreter: 'python3 -O'),
        'early exit' => _inline(
          fixture: 'from worker import emit\nexit(0)\nrecords = emit()',
        ),
        'dynamic fixture' => _inline(
          fixture: 'from worker import emit\nexec(code)\nrecords = emit()',
        ),
        'shell chain' => '${_inline()} && echo done',
        'unquoted newline' => '${_inline()}\necho done',
        _ => _inline(checks: "print('All checks passed')\n"),
      };
      final evidence = ToolResultPromptBuilder.completionEvidence([
        _run('failed', _inline(), 1),
        _run('candidate', candidate, 0),
      ]);
      expect(evidence.hasFailedExecutionVerification, isTrue);
      expect(evidence.hasSuccessfulExecutionVerification, isFalse);
    });
  }

  test('resolves a literal cd and keeps directories distinct', () {
    final command = _inline();
    expect(
      InlinePythonVerificationContract.parse(
        'cd /workspace && $command',
        '/parent',
      )?.key,
      InlinePythonVerificationContract.parse(command, '/workspace')?.key,
    );
    expect(
      InlinePythonVerificationContract.parse(command, '/other')?.key,
      isNot(InlinePythonVerificationContract.parse(command, '/workspace')?.key),
    );
    expect(InlinePythonVerificationContract.parse(command, ''), isNull);
  });

  test('quoted newlines are opt-in and expansions never become literals', () {
    expect(LiteralShellWords.parse('python3 -c "x\ny"'), isNull);
    expect(
      LiteralShellWords.parse('python3 -c "x\ny"', allowQuotedNewlines: true),
      ['python3', '-c', 'x\ny'],
    );
    for (final source in [
      'python3 -c "x\ny"\necho done',
      r'python3 -c "print($VALUE)"',
      'python3 -c "print(`command`)"',
    ]) {
      expect(
        LiteralShellWords.parse(source, allowQuotedNewlines: true),
        isNull,
      );
    }
  });

  test('multiline strings and nested checks retain the exact-command scope', () {
    for (final fixture in [
      "from worker import emit\ntext = '''\nassert false\n'''\nrecords = emit()",
      'from worker import emit\nif True:\n    assert emit()\nrecords = emit()',
    ]) {
      expect(
        InlinePythonVerificationContract.parse(
          _inline(fixture: fixture),
          '/workspace',
        ),
        isNull,
      );
    }
  });

  test('actual fixture repair permits inherited task completion', () async {
    if (Platform.isWindows) return;
    final root = await Directory.systemTemp.createTemp('inline_verifier_');
    addTearDown(() => root.delete(recursive: true));
    await File(
      '${root.path}/worker.py',
    ).writeAsString("def emit():\n    return '[INFO] worker: started'\n");
    final results = <ToolResultInfo>[];
    for (final fixture in [
      'from worker import missing\nrecords = missing()',
      "from worker import emit\nrecords = ''",
      'import logging\nfrom worker import emit\nrecords = emit()',
    ]) {
      final command = _inline(fixture: fixture);
      final executed = await LocalShellTools.executeResult(
        command: command,
        workingDirectory: root.path,
      );
      results.add(
        ToolResultInfo(
          id: 'run-${results.length}',
          name: 'local_execute_command',
          arguments: {'command': command, 'working_directory': root.path},
          result: executed.result,
          outcome: executed.outcome,
        ),
      );
    }
    expect(results.map((result) => result.outcome?.exitCode), [1, 1, 0]);
    expect(results.first.result, contains('ImportError'));
    expect(results[1].result, contains('AssertionError'));
    final owner = ChatTurnOwner(
      conversationId: 'fixture',
      interactionGeneration: 1,
    );
    final outcome = const GoalUpdateToolHandler().handleCall(
      owner: owner,
      toolCall: ToolCallInfo(
        id: 'complete',
        name: 'update_goal',
        arguments: const {'completed': true},
      ),
      goal: ConversationGoal(
        id: 'goal',
        objective: 'Verify module logging',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        projectTaskAutoReview: true,
        projectTaskInheritedPaths: ['${root.path}/worker.py'],
      ),
      toolResults: results,
      completionEvidence: ToolResultPromptBuilder.completionEvidence(
        results.take(2).toList(),
      ),
    );
    expect(outcome.ackOutcome, GoalUpdateAckOutcome.completionRecorded);
  });
}
