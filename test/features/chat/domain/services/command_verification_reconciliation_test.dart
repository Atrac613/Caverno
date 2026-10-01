import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/coding_command_output_guardrail_service.dart';
import 'package:caverno/features/chat/domain/services/command_verification_reconciliation.dart';
import 'package:caverno/features/chat/domain/services/pytest_verification_identity.dart';
import 'package:caverno/features/chat/domain/services/tool_result_prompt_builder.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final missing = command(
    'missing',
    'python3 -m pytest test_retry.py -v 2>&1 | tail -30',
    stdout: '/opt/python/bin/python3.14: No module named pytest',
  );
  final feedback = const CodingCommandOutputGuardrailService()
      .buildFeedbackToolResult(toolResults: [missing])!;
  final success = command(
    'success',
    '.venv/bin/python -m pytest test_retry.py -v 2>&1 | tail -40',
  );

  test('settles a cd-prefixed failure only in its effective directory', () {
    final prefixed = command(
      'prefixed',
      'cd /workspace && python3 -m pytest test_retry.py -v 2>&1 | tail -30',
      directory: '/parent',
      stdout: 'python3: No module named pytest',
    );
    final failed = const CodingCommandOutputGuardrailService()
        .buildFeedbackToolResult(toolResults: [prefixed])!;
    final passed = command(
      'passed',
      'cd /workspace && .venv/bin/python -m pytest test_retry.py -v 2>&1 | tail -40',
      directory: '/parent',
    );
    expect(
      ToolResultPromptBuilder.completionEvidence([
        prefixed,
        failed,
        passed,
      ]).unresolvedErrorCount,
      0,
    );
    expect(
      ToolResultPromptBuilder.completionEvidence([
        prefixed,
        failed,
        command(
          'other-root',
          passed.arguments['command'] as String,
          directory: '/parent',
          stdout: '2 failed, 4 passed in 0.1s',
        ),
      ]).unresolvedErrorCount,
      1,
    );
  });

  test(
    'settles a failed interpreter invocation with the matching venv verifier',
    () {
      final results = [missing, feedback, success];
      final evidence = ToolResultPromptBuilder.completionEvidence(results);
      expect(evidence.unresolvedErrorCount, 0);
      expect(evidence.hasSuccessfulExecutionVerification, isTrue);
      expect(evidence.hasFailedExecutionVerification, isFalse);
      expect(
        ToolResultPromptBuilder.completionBlockerInstructions(results),
        isEmpty,
      );
      expect(
        ToolResultPromptBuilder.formatToolResults(results),
        isNot(contains('No module named')),
      );
      expect(
        results,
        hasLength(3),
        reason: 'the raw audit results are preserved',
      );
    },
  );

  for (final variant in [
    'other target',
    'other directory',
    'other flags',
    'unknown shell',
    'unknown counts',
    'no tests',
    'failed tests',
    'timeout',
    'running',
    'missing typed exit',
    'diagnostic error',
  ]) {
    test('keeps the failure for $variant', () {
      final candidate = command(
        'candidate',
        switch (variant) {
          'other target' => '.venv/bin/python -m pytest other.py -v',
          'other flags' => '.venv/bin/python -m pytest test_retry.py -q',
          'unknown shell' =>
            '.venv/bin/python -m pytest test_retry.py -v && echo done',
          _ => '.venv/bin/python -m pytest test_retry.py -v',
        },
        directory: variant == 'other directory' ? '/other' : '/workspace',
        stdout: switch (variant) {
          'unknown counts' => 'done',
          'no tests' => '================= 0 passed in 0.1s =================',
          'failed tests' =>
            '================= 2 failed, 4 passed in 0.1s =================',
          _ => '================= 6 passed in 0.1s =================',
        },
        typed: variant != 'missing typed exit',
        timedOut: variant == 'timeout',
        processState: variant == 'running' ? ToolProcessState.running : null,
        diagnosticErrors: variant == 'diagnostic error' ? 1 : 0,
      );
      final evidence = ToolResultPromptBuilder.completionEvidence([
        missing,
        feedback,
        candidate,
      ]);
      expect(evidence.unresolvedErrorCount, 1);
      expect(evidence.hasSuccessfulExecutionVerification, isFalse);
    });
  }

  test('a later failure stays blocking after an earlier success', () {
    final failure = command(
      'later-failure',
      success.arguments['command'] as String,
      stdout: '================= 2 failed, 4 passed in 0.1s =================',
    );
    final laterFeedback = const CodingCommandOutputGuardrailService()
        .buildFeedbackToolResult(toolResults: [failure])!;
    final evidence = ToolResultPromptBuilder.completionEvidence([
      missing,
      feedback,
      success,
      failure,
      laterFeedback,
    ]);
    expect(evidence.unresolvedErrorCount, 1);
    expect(evidence.hasFailedExecutionVerification, isTrue);
  });

  test('retains unrelated diagnostics in a mixed feedback batch', () {
    final other = command(
      'other',
      'python3 -m pytest other.py -v',
      stdout: 'No data found',
    );
    final mixed = const CodingCommandOutputGuardrailService()
        .buildFeedbackToolResult(toolResults: [missing, other])!;
    final evidence = ToolResultPromptBuilder.completionEvidence([
      missing,
      other,
      mixed,
      success,
    ]);
    expect(evidence.unresolvedErrorCount, 1);
    expect(
      evidence.unresolvedErrorDiagnostics.single.message,
      contains('No data found'),
    );
  });

  test('resolves old log feedback using its nearest preceding command', () {
    ToolResultInfo legacy(ToolResultInfo source) {
      final generated = const CodingCommandOutputGuardrailService()
          .buildFeedbackToolResult(toolResults: [source])!;
      final payload = jsonDecode(generated.result) as Map<String, dynamic>;
      (payload['issues'] as List).single.remove('tool_call_id');
      return ToolResultInfo(
        id: 'legacy-${source.id}',
        name: generated.name,
        arguments: generated.arguments,
        result: jsonEncode(payload),
      );
    }

    final repeat = command(
      'repeat',
      missing.arguments['command'] as String,
      stdout: '/opt/python/bin/python3.14: No module named pytest',
    );
    final results = CommandVerificationReconciliation.currentResults([
      missing,
      legacy(missing),
      success,
      repeat,
      legacy(repeat),
    ]);
    expect(results.map((result) => result.id), [
      success.id,
      repeat.id,
      'legacy-repeat',
    ]);
  });

  test('runner counts reject prose and report failures and skips', () {
    final identity = PytestVerificationIdentity.parse(
      'pytest test.py',
      '/workspace',
    )!;
    expect(identity.counts('I confirmed 6 tests passed.'), isNull);
    final counts = identity.counts(
      '=== 2 failed, 4 passed, 1 skipped, 1 error in 0.1s ===',
    )!;
    expect(counts.failedCount, 3);
    expect(counts.skippedCount, 1);
  });

  group('non-pytest verification', () {
    // Session d0c0462c: only pytest runs were ever reconciled, so a failed
    // `watcher.py --dry-run` stayed failed for the rest of the turn even when
    // the very same command later passed.
    ToolResultInfo run(String id, String command, int exitCode) =>
        ToolResultInfo(
          id: id,
          name: 'local_execute_command',
          arguments: {'command': command, 'working_directory': '/w'},
          result: jsonEncode({
            'command': command,
            'working_directory': '/w',
            'exit_code': exitCode,
            'stdout': exitCode == 0 ? 'All 22 checks passed.' : 'failed',
          }),
          outcome: ToolOutcome(exitCode: exitCode),
        );
    const verifier = '.venv/bin/python verify_logging.py';

    test('the same command passing later settles its failure', () {
      final current = CommandVerificationReconciliation.currentResults([
        run('fail', verifier, 1),
        run('pass', verifier, 0),
      ]);
      expect(current.map((result) => result.id), ['pass']);
    });

    test('a different command passing does not', () {
      final current = CommandVerificationReconciliation.currentResults([
        run('fail', verifier, 1),
        run('other', 'python3 -m pytest -q', 0),
      ]);
      expect(current.map((result) => result.id), contains('fail'));
    });
  });
}

ToolResultInfo command(
  String id,
  String command, {
  String stdout = '================= 6 passed in 0.1s =================',
  String directory = '/workspace',
  bool typed = true,
  bool timedOut = false,
  ToolProcessState? processState,
  int diagnosticErrors = 0,
}) => ToolResultInfo(
  id: id,
  name: 'local_execute_command',
  arguments: {'command': command, 'working_directory': directory},
  result: jsonEncode({
    'command': command,
    'working_directory': directory,
    'exit_code': 0,
    'stdout': stdout,
    'timed_out': timedOut,
  }),
  outcome: typed
      ? ToolOutcome(
          exitCode: 0,
          processState: processState,
          diagnosticErrorCount: diagnosticErrors,
        )
      : null,
);
