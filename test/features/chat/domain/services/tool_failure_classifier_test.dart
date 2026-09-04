import 'dart:convert';

import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/model_usage_role.dart';
import 'package:caverno/features/chat/domain/services/anabasis_parent_authority_guard.dart';
import 'package:caverno/features/chat/domain/services/material_contract_assumption_guard.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/tool_failure_classifier.dart';
import 'package:caverno/features/chat/domain/services/tool_outcome_shadow_comparison.dart';

void main() {
  const classifier = ToolFailureClassifier();

  test('classifies structured non-zero command diagnostics as actionable', () {
    final result = _failure({
      'exit_code': 1,
      'stdout': '',
      'stderr': 'Acceptance criteria failed.',
      'diagnostics': [
        {'code': 'todo_cli_entrypoint'},
      ],
    });

    expect(
      classifier.classify(_commandCall(), result),
      ToolResultDisposition.actionableCommandFailure,
    );
    expect(
      classifier.lifecycleResultStatus(_commandCall(), result),
      'command_failure',
    );
  });

  test('classifies command output without diagnostics as actionable', () {
    final result = _failure({
      'exit_code': 2,
      'stdout': 'Expected value was missing.',
      'stderr': '',
    });

    expect(
      classifier.classify(_commandCall(), result),
      ToolResultDisposition.actionableCommandFailure,
    );
  });

  test('keeps approval denial on the operational failure path', () {
    final result = _failure({
      'exit_code': 1,
      'stdout': '',
      'stderr': '',
    }, errorMessage: 'Auto-review denied this command.');

    expect(
      classifier.classify(_commandCall(), result),
      ToolResultDisposition.approvalDenied,
    );
    expect(classifier.isApprovalDenial(result), isTrue);
  });

  test('keeps timeout and explicit execution errors operational', () {
    final timeout = _failure({
      'exit_code': 124,
      'stdout': '',
      'stderr': '',
      'timed_out': true,
    });
    final startError = _failure({
      'exit_code': 1,
      'stdout': '',
      'stderr': '',
      'error': 'Process failed to start.',
    });
    final structuredError = _failure({
      'exit_code': 1,
      'stdout': '',
      'stderr': '',
      'error': {'code': 'spawn_failed'},
    });

    expect(
      classifier.classify(_commandCall(), timeout),
      ToolResultDisposition.executionFailure,
    );
    expect(
      classifier.classify(_commandCall(), startError),
      ToolResultDisposition.executionFailure,
    );
    expect(
      classifier.classify(_commandCall(), structuredError),
      ToolResultDisposition.executionFailure,
    );
  });

  test('keeps malformed and non-command failures operational', () {
    const malformed = McpToolResult(
      toolName: 'local_execute_command',
      result: 'exit code 1',
      isSuccess: false,
      errorMessage: 'Command failed.',
    );
    final nonCommand = _failure({
      'exit_code': 1,
      'stdout': '',
      'stderr': 'Read failed.',
    }, toolName: 'read_file');

    expect(
      classifier.classify(_commandCall(), malformed),
      ToolResultDisposition.executionFailure,
    );
    expect(
      classifier.classify(
        ToolCallInfo(
          id: 'read-1',
          name: 'read_file',
          arguments: {'path': 'README.md'},
        ),
        nonCommand,
      ),
      ToolResultDisposition.executionFailure,
    );
  });

  test('classifies successful results before inspecting payloads', () {
    const result = McpToolResult(
      toolName: 'local_execute_command',
      result: '{"exit_code":1,"stderr":"ignored"}',
      isSuccess: true,
    );

    expect(
      classifier.classify(_commandCall(), result),
      ToolResultDisposition.success,
    );
  });

  group('structured outcome (LL34)', () {
    test('classifies from the reported exit code without parsing output', () {
      // The payload is deliberately unparseable: a tool that reports its own
      // exit status must not need its prose read back to be classified.
      const result = McpToolResult(
        toolName: 'local_execute_command',
        result: 'Build failed after 3 steps.',
        isSuccess: false,
        errorMessage: 'Command exited non-zero.',
        outcome: ToolOutcome(exitCode: 1),
      );

      expect(
        classifier.classify(_commandCall(), result),
        ToolResultDisposition.actionableCommandFailure,
      );
      expect(
        classifier.inspect(_commandCall(), result).exitCodeSource,
        ToolOutcomeVerdictSource.typed,
      );
    });

    test('keeps a zero exit code off the actionable path', () {
      // isSuccess: false with exit 0 is contradictory; the reported status is
      // the fact, so the failure stays operational rather than becoming a
      // command failure the model is told to fix.
      const result = McpToolResult(
        toolName: 'local_execute_command',
        result: 'Command completed.',
        isSuccess: false,
        errorMessage: 'Result could not be delivered.',
        outcome: ToolOutcome(exitCode: 0),
      );

      expect(
        classifier.classify(_commandCall(), result),
        ToolResultDisposition.executionFailure,
      );
    });

    test('outcome overrides a payload that disagrees with it', () {
      final result = McpToolResult(
        toolName: 'local_execute_command',
        result: jsonEncode({'exit_code': 0, 'stdout': 'ok'}),
        isSuccess: false,
        errorMessage: 'Command exited non-zero.',
        outcome: const ToolOutcome(exitCode: 3),
      );

      expect(
        classifier.classify(_commandCall(), result),
        ToolResultDisposition.actionableCommandFailure,
      );
    });

    test('falls back to payload parsing when no outcome is reported', () {
      // Third-party MCP results and unmigrated first-party tools keep the
      // lexical path; it must stay byte-for-byte equivalent to today.
      final result = _failure({
        'exit_code': 1,
        'stdout': '',
        'stderr': 'Acceptance criteria failed.',
      });

      expect(result.outcome, isNull);
      expect(
        classifier.classify(_commandCall(), result),
        ToolResultDisposition.actionableCommandFailure,
      );
      expect(
        classifier.inspect(_commandCall(), result).exitCodeSource,
        ToolOutcomeVerdictSource.lexicalFallback,
      );
    });

    test('an empty outcome is treated as no outcome', () {
      final result = _failure({
        'exit_code': 1,
        'stdout': '',
        'stderr': 'Acceptance criteria failed.',
      }).copyWith(outcome: const ToolOutcome());

      expect(
        classifier.classify(_commandCall(), result),
        ToolResultDisposition.actionableCommandFailure,
      );
    });

    test('approval denial still wins over a reported exit code', () {
      const result = McpToolResult(
        toolName: 'local_execute_command',
        result: 'blocked',
        isSuccess: false,
        errorMessage: 'Auto-review denied this command.',
        outcome: ToolOutcome(exitCode: 1),
      );

      expect(
        classifier.classify(_commandCall(), result),
        ToolResultDisposition.approvalDenied,
      );
    });

    test('a non-command tool is unaffected by a reported exit code', () {
      const result = McpToolResult(
        toolName: 'read_file',
        result: 'Read failed.',
        isSuccess: false,
        errorMessage: 'Read failed.',
        outcome: ToolOutcome(exitCode: 1),
      );

      expect(
        classifier.classify(
          ToolCallInfo(
            id: 'read-1',
            name: 'read_file',
            arguments: {'path': 'README.md'},
          ),
          result,
        ),
        ToolResultDisposition.executionFailure,
      );
    });
  });

  group('a policy refusal is not a broken tool', () {
    final mutation = ToolCallInfo(
      id: 'call-write',
      name: 'write_file',
      arguments: const {'path': 'lib/a.dart', 'content': '// x'},
    );

    test('the parent authority guard is read by its code, not its prose', () {
      final result = const AnabasisParentAuthorityGuard().evaluate(
        mutation,
        executingRole: ModelUsageRole.anabasisParent,
      )!;

      expect(
        '${result.errorMessage}\n${result.result}'.toLowerCase(),
        isNot(contains('denied')),
        reason:
            'The fixture is only meaningful while the prose does not happen '
            'to contain the word the substring test looks for.',
      );
      expect(
        classifier.classify(mutation, result),
        ToolResultDisposition.approvalDenied,
        reason:
            'Classified as an execution failure, this told the user to check '
            'their server configuration for a policy working as designed, and '
            'recorded tool_failure for a decision.',
      );
    });

    test('the material assumption guard is read the same way', () {
      final result = const MaterialContractAssumptionGuard().evaluate(
        mutation,
        workspaceMode: WorkspaceMode.coding,
        blockingAssumptions: const [
          ConversationContractItemProvenance(
            itemId: 'constraint:stable-ids',
            kind: ConversationContractItemKind.constraint,
            assumption: true,
            material: true,
          ),
        ],
      )!;

      expect(
        '${result.errorMessage}\n${result.result}'.toLowerCase(),
        isNot(contains('denied')),
      );
      expect(
        classifier.classify(mutation, result),
        ToolResultDisposition.approvalDenied,
      );
    });

    test('an unrecognised code is still an execution failure', () {
      expect(
        classifier.classify(
          mutation,
          McpToolResult(
            toolName: 'write_file',
            result: jsonEncode({'code': 'disk_full', 'error': 'no space'}),
            isSuccess: false,
            errorMessage: 'no space left on device',
          ),
        ),
        ToolResultDisposition.executionFailure,
        reason:
            'Treating every structured failure as a policy decision would '
            'stop the loop retrying things a retry can actually fix.',
      );
    });

    test('a non-JSON refusal still reaches the prose branch', () {
      expect(
        classifier.classify(
          mutation,
          McpToolResult(
            toolName: 'write_file',
            result: 'User denied the write.',
            isSuccess: false,
            errorMessage: 'denied',
          ),
        ),
        ToolResultDisposition.approvalDenied,
        reason:
            'The codes are additive; refusals without one still rely on it.',
      );
    });
  });
}

ToolCallInfo _commandCall() {
  return ToolCallInfo(
    id: 'command-1',
    name: 'local_execute_command',
    arguments: {'command': 'dart test'},
  );
}

McpToolResult _failure(
  Map<String, dynamic> payload, {
  String toolName = 'local_execute_command',
  String errorMessage = 'Command exited non-zero.',
}) {
  return McpToolResult(
    toolName: toolName,
    result: jsonEncode(payload),
    isSuccess: false,
    errorMessage: errorMessage,
  );
}
