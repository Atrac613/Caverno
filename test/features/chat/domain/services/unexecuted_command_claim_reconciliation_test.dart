import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/session_memory.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/final_answer_claim_detector.dart';
import 'package:caverno/features/chat/domain/services/memory_extraction_draft_service.dart';
import 'package:caverno/features/chat/domain/services/tool_result_prompt_builder.dart';
import 'package:caverno/features/chat/domain/services/unexecuted_command_claim_reconciliation.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const detector = FinalAnswerClaimDetector();
  final claim = detector.buildUnexecutedCommandActionToolResult(
    candidateResponse: 'The local command completed.',
    toolResults: const [],
  )!;
  ToolResultInfo verification({
    String command = 'python3 verify.py',
    int? exitCode = 0,
    String stdout = 'All checks passed.',
    Map<String, Object?> payload = const {},
    ToolOutcome? outcome,
  }) => ToolResultInfo(
    id: 'verify',
    name: 'local_execute_command',
    arguments: {'command': command, 'working_directory': '/project'},
    result: jsonEncode({'exit_code': exitCode, 'stdout': stdout, ...payload}),
    outcome:
        outcome ?? (exitCode == null ? null : ToolOutcome(exitCode: exitCode)),
  );

  test('settles an evidence-absence notice across all consumer views', () {
    final results = [claim, verification()];
    expect(UnexecutedCommandClaimReconciliation.currentResults(results), [
      results.last,
    ]);
    expect(
      ToolResultPromptBuilder.completionEvidence(
        results,
      ).hasUnexecutedActionClaim,
      isFalse,
    );
    expect(
      ToolResultPromptBuilder.formatToolResults(results),
      isNot(contains('unexecuted_command_action')),
    );
    expect(detector.hasUnexecutedCommandActionResult(results), isFalse);
    final input = MemoryExtractionDraftService.buildInput(
      <Message>[],
      UserMemoryProfile.empty(),
      toolResults: results,
    );
    expect(input, isNot(contains('code":"unexecuted_command_action')));
    expect(results, hasLength(2), reason: 'the audit ledger is unchanged');
  });

  for (final candidate in [
    verification(exitCode: 1),
    verification(exitCode: null),
    verification(
      command: 'python3 -m pytest test_fixture.py 2>&1 | tail -5',
      stdout: 'ModuleNotFoundError: No module named pytest',
    ),
    verification(payload: {'timed_out': true}),
    verification(payload: {'execution_reused': true}),
    verification(
      outcome: const ToolOutcome(
        exitCode: 0,
        processState: ToolProcessState.running,
      ),
    ),
    verification(
      outcome: const ToolOutcome(exitCode: 0, diagnosticErrorCount: 1),
    ),
    verification(command: 'python3 --version'),
    verification(
      command: 'python3 -c "import pytest; print(pytest.__version__)"',
    ),
    verification(
      command: 'python3 -m pytest test_fixture.py',
      stdout: 'no tests ran',
    ),
    verification(
      outcome: const ToolOutcome(
        exitCode: 0,
        testOutcome: ToolTestOutcome(
          passedCount: 1,
          failedCount: 1,
          skippedCount: 0,
          command: 'python3 verify.py',
        ),
      ),
    ),
  ]) {
    test(
      'keeps the notice without a fresh passing verifier: ${candidate.arguments} ${candidate.result} ${candidate.outcome}',
      () {
        final results = [claim, candidate];
        expect(
          UnexecutedCommandClaimReconciliation.currentResults(results),
          results,
        );
        expect(
          ToolResultPromptBuilder.completionEvidence(
            results,
          ).hasUnexecutedActionClaim,
          isTrue,
        );
      },
    );
  }

  test('settles a terminal subtask report mentioning later verification', () {
    const response =
        'Subtask implementation complete. Verification has not run. '
        'I will run the local command to test in the next subtask.\nPROJECT_TASK_SUBTASK_DONE';
    final pending = detector.buildUnexecutedCommandActionToolResult(
      candidateResponse: response,
      toolResults: const [],
      isProjectSubtask: true,
    )!;
    expect(
      jsonDecode(pending.result)['evidence_requirement'],
      UnexecutedCommandClaimReconciliation.evidenceRequirement,
    );
    expect(detector.hasUnexecutedCommandActionResult([pending]), isTrue);
    expect(
      detector.hasUnexecutedCommandActionResult([pending, verification()]),
      isFalse,
    );
    expect(
      detector.hasUnexecutedCommandActionResult([verification(), pending]),
      isTrue,
    );
    expect(
      detector.buildUnexecutedCommandActionToolResult(
        candidateResponse: response,
        toolResults: [verification()],
        isProjectSubtask: true,
      ),
      isNull,
    );
    final edit = ToolResultInfo(
      id: 'edit',
      name: 'edit_file',
      arguments: const {},
      result: '{"changed":true}',
      outcome: const ToolOutcome(
        fileMutations: [
          ToolFileMutation(path: '/project/verify.py', changed: true),
        ],
      ),
    );
    expect(
      detector.buildUnexecutedCommandActionToolResult(
        candidateResponse: response,
        toolResults: [verification(), edit],
        isProjectSubtask: true,
      ),
      isNotNull,
    );
    expect(
      detector.buildUnexecutedCommandActionToolResult(
        candidateResponse: response,
        toolResults: [
          verification(payload: {'execution_reused': true}),
        ],
        isProjectSubtask: true,
      ),
      isNotNull,
    );
    final ordinary = detector.buildUnexecutedCommandActionToolResult(
      candidateResponse: response,
      toolResults: const [],
    )!;
    // A lexical promise names no call, so a later passing verifier settles
    // it outside subtask context too (user decision 2026-10-07).
    expect(
      detector.hasUnexecutedCommandActionResult([ordinary, verification()]),
      isFalse,
    );
    expect(
      MemoryExtractionDraftService.buildInput(
        <Message>[],
        UserMemoryProfile.empty(),
        toolResults: [pending, verification()],
      ),
      isNot(contains('code":"unexecuted_command_action')),
    );
  });

  for (final response in [
    'Implementation complete. I will run the local command.\n'
        '{"command":"python3 missing.py"}\nPROJECT_TASK_SUBTASK_DONE',
    'Implementation complete. I will run the local command.\n'
        '```text\n\$ python3 missing.py\nchecks passed\n```\nPROJECT_TASK_SUBTASK_DONE',
  ]) {
    test('subtask context preserves concrete calls: $response', () {
      final pending = detector.buildUnexecutedCommandActionToolResult(
        candidateResponse: response,
        toolResults: const [],
        isProjectSubtask: true,
      )!;
      expect(
        jsonDecode(pending.result),
        isNot(contains('evidence_requirement')),
      );
      expect(
        detector.hasUnexecutedCommandActionResult([pending, verification()]),
        isTrue,
      );
    });
  }

  // Session 8ea796df: the report described a return value in braces, the
  // notice became unsettleable, and the subtask stayed rejected for
  // "unexecuted actions" after the pending pytest run passed (37 passed).
  for (final description in [
    '{"item_id", "old_price", "new_price", "change_rate"}',
    '{"item_id": "X1", "old_price": 1000}',
  ]) {
    test(
      'braces describing data do not make a call concrete: $description',
      () {
        // The answer's own wording, which is what fires the trigger.
        final response =
            'サブタスク3のコード変更が完了しました。ただし、'
            '**このターンではテストを実行していないため、変更の動作確認は未完了です。**\n'
            '- `detect_price_change` は $description を返す\n'
            '`pytest test_state.py test_watcher.py -v` の実行がまだ残っています。'
            '既存テストと競合しないかを確認するには、このコマンドの実行が必要です。\n'
            'PROJECT_TASK_SUBTASK_DONE';
        final pending = detector.buildUnexecutedCommandActionToolResult(
          candidateResponse: response,
          toolResults: const [],
          isProjectSubtask: true,
        )!;
        expect(
          jsonDecode(pending.result)['evidence_requirement'],
          UnexecutedCommandClaimReconciliation.evidenceRequirement,
        );
        expect(
          detector.hasUnexecutedCommandActionResult([
            pending,
            verification(
              command: '.venv/bin/python -m pytest test_state.py -v',
              stdout: '37 passed in 3.10s',
            ),
          ]),
          isFalse,
        );
      },
    );
  }

  // Session c4b7c183: "rerun with python3 to verify" was fulfilled two calls
  // later (58 passed), yet the notice outlived it and the subtask was
  // rejected for unexecuted actions.
  for (final promise in [
    'I will run the local command.',
    '前回の実行で `python` コマンドが見つからなかったため（exit code 127）、'
        '`python3` で再実行して検証します。',
  ]) {
    test('a later passing verifier settles a lexical promise: $promise', () {
      for (final subtask in [false, true]) {
        final pending = detector.buildUnexecutedCommandActionToolResult(
          candidateResponse: promise,
          toolResults: const [],
          isProjectSubtask: subtask,
        )!;
        expect(
          jsonDecode(pending.result)['evidence_requirement'],
          UnexecutedCommandClaimReconciliation.evidenceRequirement,
        );
        expect(
          detector.hasUnexecutedCommandActionResult([pending, verification()]),
          isFalse,
        );
        expect(
          detector.hasUnexecutedCommandActionResult([verification(), pending]),
          isTrue,
          reason: 'only a verifier after the promise can fulfil it',
        );
        expect(
          ToolResultPromptBuilder.completionEvidence([
            pending,
            verification(),
          ]).hasUnexecutedActionClaim,
          isFalse,
        );
      }
    });
  }

  test('unknown result text cannot settle a missing execution', () {
    final unknown = ToolResultInfo(
      id: 'unknown',
      name: 'local_execute_command',
      arguments: const {'command': 'python3 verify.py'},
      result: 'unstructured response',
    );
    expect(detector.hasUnexecutedCommandActionResult([claim, unknown]), isTrue);
  });

  test('earlier success cannot execute a later missing action', () {
    expect(
      detector.hasUnexecutedCommandActionResult([verification(), claim]),
      isTrue,
    );
  });
  for (final response in [
    'The local command completed.\n```json\n{"command":"python3 missing.py"}\n```',
    'The local command completed.\n```json\n{"name":"local_execute_command","arguments":{"command":"python3 missing.py"}}\n```',
    'The local command completed.\n[Tool: local_execute_command]\nArguments: {"command":"python3 missing.py"}',
    'The local command completed.\n```text\n\$ python3 missing.py\nchecks passed\n```',
    'The local command completed.\n<tool_call>{"name":"local_execute_command","arguments":{"command":"python3 missing.py"}}</tool_call>',
  ]) {
    test('keeps concrete unissued actions: $response', () {
      final pending = detector.buildUnexecutedCommandActionToolResult(
        candidateResponse: response,
        toolResults: const [],
      )!;
      expect(
        jsonDecode(pending.result),
        isNot(contains('evidence_requirement')),
      );
      expect(
        detector.hasUnexecutedCommandActionResult([pending, verification()]),
        isTrue,
      );
    });
  }
  test('does not clear legacy, foreign, scoped, or file-save notices', () {
    for (final payload in [
      {'code': 'unexecuted_command_action'},
      {
        'code': 'unexecuted_command_action',
        'evidence_requirement':
            UnexecutedCommandClaimReconciliation.evidenceRequirement,
      },
      {
        ...jsonDecode(claim.result) as Map<String, dynamic>,
        'command': 'python3 missing.py',
      },
      {
        ...jsonDecode(claim.result) as Map<String, dynamic>,
        'code': 'unexecuted_file_save',
      },
    ]) {
      final pending = ToolResultInfo(
        id: 'pending',
        name: 'local_execute_command',
        arguments: const {},
        result: jsonEncode(payload),
      );
      final results = [pending, verification()];
      expect(
        UnexecutedCommandClaimReconciliation.currentResults(results),
        results,
      );
      expect(
        ToolResultPromptBuilder.completionEvidence(
          results,
        ).hasUnexecutedActionClaim,
        isTrue,
      );
    }
  });
  test('stale background completion cannot execute a recovery after an edit', () {
    final start = ToolResultInfo(
      id: 'start',
      name: 'process_start',
      arguments: const {'command': 'python3 verify.py'},
      result:
          '{"job_id":"job","command":"python3 verify.py","working_directory":"/project"}',
      outcome: const ToolOutcome(processState: ToolProcessState.running),
    );
    final mutation = ToolResultInfo(
      id: 'edit',
      name: 'edit_file',
      arguments: const {'path': '/project/app.py'},
      result: '{"path":"/project/app.py","changed":true}',
      outcome: const ToolOutcome(fileChanged: true),
    );
    final poll = ToolResultInfo(
      id: 'poll',
      name: 'process_wait',
      arguments: const {'job_id': 'job'},
      result:
          '{"job_id":"job","command":"python3 verify.py","working_directory":"/project","status":"exited","exit_code":0}',
      outcome: const ToolOutcome(
        exitCode: 0,
        processState: ToolProcessState.exited,
      ),
    );
    expect(
      detector.hasUnexecutedCommandActionResult([claim, start, poll]),
      isFalse,
    );
    expect(
      detector.hasUnexecutedCommandActionResult([claim, start, mutation, poll]),
      isTrue,
    );
  });

  test(
    'a later verification failure remains unresolved after settling the notice',
    () {
      final results = [
        claim,
        verification(),
        ToolResultInfo(
          id: 'failed',
          name: 'local_execute_command',
          arguments: const {'command': 'python3 verify_other.py'},
          result: '{"exit_code":1}',
          outcome: const ToolOutcome(exitCode: 1),
        ),
      ];
      final evidence = ToolResultPromptBuilder.completionEvidence(results);
      expect(evidence.hasUnexecutedActionClaim, isFalse);
      expect(evidence.hasFailedExecutionVerification, isTrue);
    },
  );
}
