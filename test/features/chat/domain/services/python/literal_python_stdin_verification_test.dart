import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/final_answer_claim_detector.dart';
import 'package:caverno/features/chat/domain/services/python/literal_python_stdin_verification.dart';
import 'package:caverno/features/chat/domain/services/tool_result_prompt_builder.dart';
import 'package:caverno/features/chat/domain/services/verification/command_verification_reconciliation.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const script = 'import sys\nif 1 != 1:\n    sys.exit(1)\nprint("Verified.")';
  const invocation = "cd /workspace && python3 - <<'PY'\n$script\nPY";

  for (final header in [
    "python3 - <<'PY'",
    'python3.14 - <<"PY"',
    "/workspace/.venv/bin/python - <<'PY' 2>&1",
    "cd '/workspace/project name' && python - <<'PY'",
    // Session 64bbc516: tests first, then the stdin check.
    "python3 -m pytest test_state.py -q && python3 - <<'PY'",
    'cd /workspace && .venv/bin/python -m pytest -q && '
        ".venv/bin/python - <<'PY'",
  ]) {
    test('recognizes a literal stdin invocation: $header', () {
      final command = '$header\n$script\nPY\n';
      expect(LiteralPythonStdinVerification.applies(command), isTrue);
      final result = _result('passed', command);
      expect(CommandVerificationReconciliation.isVerification(result), isTrue);
      expect(CommandVerificationReconciliation.scopeOf(result)!.passed, isTrue);
      expect(
        ToolResultPromptBuilder.completionEvidence([
          result,
        ]).hasSuccessfulExecutionVerification,
        isTrue,
      );
      expect(
        const ToolCapabilityClassifier()
            .classify(result.name, arguments: result.arguments)
            .commandEffect,
        ToolCommandEffect.workspaceMutation,
        reason: 'completion evidence must not relax command approval',
      );
    });
  }

  test('a failing check chained after pytest blocks completion', () {
    final failed = _result(
      'chained',
      "python3 -m pytest -q && python3 - <<'PY'\n$script\nPY",
      exitCode: 1,
      stdout: '37 passed in 3.1s',
    );
    expect(CommandVerificationReconciliation.isVerification(failed), isTrue);
    expect(
      ToolResultPromptBuilder.completionEvidence([
        failed,
      ]).hasFailedExecutionVerification,
      isTrue,
    );
  });

  test('Python strings remain literal even when they contain shell syntax', () {
    expect(
      LiteralPythonStdinVerification.applies(
        "python3 - <<'PY'\nprint('`whoami` \$HOME && echo x; PY')\nPY",
      ),
      isTrue,
    );
  });

  for (final command in [
    'python3 - <<PY\n$script\nPY',
    "python3 - <<-'PY'\n$script\nPY",
    "python3 - <<'PY'\n$script",
    "python3 - <<'PY'\n$script\nPY \n",
    "python3 - <<'PY'\n$script\nPY\necho done",
    "python3 - <<'PY'\n$script\nPY\necho done\nPY",
    "python3 - <<'PY' | cat\n$script\nPY",
    "python3 - <<'PY' > report.txt\n$script\nPY",
    "python3 - > report.txt <<'PY'\n$script\nPY",
    "env python3 - <<'PY'\n$script\nPY",
    "python3 -u - <<'PY'\n$script\nPY",
    "sh - <<'PY'\n$script\nPY",
    "cd /workspace; python3 - <<'PY'\n$script\nPY",
    "cd \$HOME && python3 - <<'PY'\n$script\nPY",
    "cd /workspace && echo ready && python3 - <<'PY'\n$script\nPY",
    "rm -rf data && python3 - <<'PY'\n$script\nPY",
    "python3 -m pytest -q || python3 - <<'PY'\n$script\nPY",
    "python3 - <<'PY'\n\nPY",
    "python3 - <<'PY'\r\n$script\r\nPY",
  ]) {
    test('rejects unsupported shell structure: ${jsonEncode(command)}', () {
      expect(LiteralPythonStdinVerification.applies(command), isFalse);
    });
  }

  for (final metadata in [
    'import pytest; print(pytest.__file__)',
    'import pytest\nprint(pytest.__version__)',
  ]) {
    test('excludes package metadata lookup: $metadata', () {
      final command = "python3 - <<'PY'\n$metadata\nPY";
      expect(LiteralPythonStdinVerification.applies(command), isFalse);
      expect(
        ToolResultPromptBuilder.completionEvidence([
          _result('metadata', command),
        ]).hasExecutionVerification,
        isFalse,
      );
    });
  }

  test('a fresh passing stdin verifier settles an evidence-absence notice', () {
    final claim = const FinalAnswerClaimDetector()
        .buildUnexecutedCommandActionToolResult(
          candidateResponse: 'The local command completed.',
          toolResults: const [],
        )!;
    final results = [claim, _result('passed', invocation)];
    final evidence = ToolResultPromptBuilder.completionEvidence(results);
    expect(evidence.hasSuccessfulExecutionVerification, isTrue);
    expect(evidence.hasUnexecutedActionClaim, isFalse);
    expect(results, hasLength(2), reason: 'retain the raw audit evidence');
    expect(
      ToolResultPromptBuilder.completionEvidence(
        results.reversed.toList(),
      ).hasUnexecutedActionClaim,
      isTrue,
      reason: 'earlier verification cannot execute a later missing action',
    );
  });

  test('settles only a rerun of the identical stdin script and directory', () {
    final failed = _result('failed', invocation, exitCode: 1);
    for (final passed in [
      _result('same', invocation),
      _result('changed-script', invocation.replaceFirst('1 != 1', '2 != 2')),
      _result('changed-directory', invocation, directory: '/other'),
      _result('another-check', 'python3 verify.py'),
    ]) {
      final results = [failed, passed];
      final same = passed.id == 'same';
      expect(
        CommandVerificationReconciliation.currentResults(
          results,
        ).contains(failed),
        !same,
      );
      final evidence = ToolResultPromptBuilder.completionEvidence(results);
      expect(evidence.hasFailedExecutionVerification, !same);
      expect(evidence.hasSuccessfulExecutionVerification, same);
    }
  });

  for (final invalid in [
    _result('failed', invocation, exitCode: 1),
    _result('unknown', invocation, exitCode: null),
    _result('timeout', invocation, payload: const {'timed_out': true}),
    _result('reused', invocation, payload: const {'execution_reused': true}),
    _result(
      'running',
      invocation,
      outcome: const ToolOutcome(
        exitCode: 0,
        processState: ToolProcessState.running,
      ),
    ),
    _result(
      'diagnostic',
      invocation,
      outcome: const ToolOutcome(exitCode: 0, diagnosticErrorCount: 1),
    ),
    _result(
      'traceback',
      invocation,
      stdout:
          'Traceback (most recent call last):\nAssertionError: fixture mismatch',
    ),
  ]) {
    test('cannot settle missing execution with ${invalid.id}', () {
      final claim = const FinalAnswerClaimDetector()
          .buildUnexecutedCommandActionToolResult(
            candidateResponse: 'The local command completed.',
            toolResults: const [],
          )!;
      expect(
        ToolResultPromptBuilder.completionEvidence([
          claim,
          invalid,
        ]).hasUnexecutedActionClaim,
        isTrue,
      );
    });
  }
}

ToolResultInfo _result(
  String id,
  String command, {
  String directory = '/workspace',
  int? exitCode = 0,
  String stdout = 'Verified.',
  Map<String, Object?> payload = const {},
  ToolOutcome? outcome,
}) => ToolResultInfo(
  id: id,
  name: 'local_execute_command',
  arguments: {'command': command, 'working_directory': directory},
  result: jsonEncode({'exit_code': exitCode, 'stdout': stdout, ...payload}),
  outcome:
      outcome ?? (exitCode == null ? null : ToolOutcome(exitCode: exitCode)),
);
