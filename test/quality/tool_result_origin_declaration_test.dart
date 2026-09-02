import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/data/datasources/chat_turn_owner_required_tool_result.dart';
import 'package:caverno/features/chat/data/datasources/local_shell_tools.dart';
import 'package:caverno/features/chat/data/datasources/project_mutation_path_fence.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/duplicate_tool_result_reuse_payload.dart';
import 'package:caverno/features/chat/domain/services/goal_validation_probe_guard.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/services/production_release_blocked_result.dart';
import 'package:caverno/features/chat/domain/services/saved_task_target_scope_guard.dart';
import 'package:caverno/features/chat/domain/services/tool_loop_recovery_policy.dart';
import 'package:caverno/features/chat/domain/services/unexecuted_file_mutation_block_payload.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

/// HEU3 instrument: a result that never reached its tool must say who wrote it.
///
/// A harness-authored nudge and a policy refusal render identically —
/// `{"ok": false, "code": ..., "error": ...}`, no `stdout` — so any rate
/// computed over "the turn tried and was stopped" counts both. That is how a
/// substitute for `BlockedMutationNotice` measured 22 of 715 turns and then
/// collapsed to 3 once the instrument was audited. The remedy is a declaration
/// by the producer, checked here two ways: the real producers are run and their
/// payloads parsed, and every known producer file is required to keep its
/// declaration.
///
/// Deliberately **not** a check that every tool result is marked. Results a
/// tool actually produced are unmarked on purpose; absence means "not
/// declared", the same tri-state `ToolOutcome` uses.
///
/// The registry below is also the answer to a drift this test surfaced.
/// `ConversationPlanExecutionGuardrails.hasOnlySyntheticNonExecutionResults`,
/// `ToolResultPromptBuilder.completionEvidence` and
/// `MemoryExtractionDraftService` each keep their own hand-written list of
/// "synthetic" codes, and the three already disagree with each other and with
/// the four codes HEU3 measured. Those lists are left alone here — this
/// milestone is the instrument, not the mechanism — but a producer that
/// declares its own provenance is what lets them be reconciled later against
/// something other than a reader's memory.
const _producers = <String, ToolResultOrigin>{
  // Harness-authored: no tool ran and no rule forbade one. The loop is
  // steering itself.
  'lib/features/chat/domain/services/final_answer_claim_detector.dart':
      ToolResultOrigin.harness,
  'lib/features/chat/domain/services/unexecuted_file_mutation_block_payload.dart':
      ToolResultOrigin.harness,
  'lib/features/chat/domain/services/unexecuted_final_answer_tool_request_policy.dart':
      ToolResultOrigin.harness,
  'lib/features/chat/domain/services/tool_loop_recovery_policy.dart':
      ToolResultOrigin.harness,
  'lib/features/chat/domain/services/unexecuted_command_action_retry_policy.dart':
      ToolResultOrigin.harness,
  'lib/features/chat/domain/services/command_diagnostic_verifier_replay_guard.dart':
      ToolResultOrigin.harness,
  'lib/features/chat/domain/services/goal_validation_probe_guard.dart':
      ToolResultOrigin.harness,
  'lib/features/chat/domain/services/duplicate_tool_result_reuse_payload.dart':
      ToolResultOrigin.harness,
  // Refusals: a permission, scope or safety rule stopped a call that was
  // otherwise ready to run. This is the population a "was stopped" rate means.
  'lib/features/chat/domain/services/production_release_blocked_result.dart':
      ToolResultOrigin.refusal,
  'lib/features/chat/data/datasources/local_shell_tools.dart':
      ToolResultOrigin.refusal,
  'lib/features/chat/data/datasources/project_mutation_path_fence.dart':
      ToolResultOrigin.refusal,
  'lib/features/chat/domain/services/saved_validation_command_guard.dart':
      ToolResultOrigin.refusal,
  'lib/features/chat/data/datasources/chat_turn_owner_required_tool_result.dart':
      ToolResultOrigin.refusal,
  'lib/features/chat/data/datasources/built_in_local_command_tool_handler.dart':
      ToolResultOrigin.refusal,
  // Found by the instrument rather than by reading the code: these three never
  // appeared in any of the three hand-maintained "synthetic" lists, and
  // `saved_task_target_scope_violation` is the single most frequent
  // never-reached-a-tool code in the measured corpus (13 of 29).
  'lib/features/chat/domain/services/saved_task_target_scope_guard.dart':
      ToolResultOrigin.refusal,
  'lib/features/chat/data/datasources/project_read_tool_authorizer.dart':
      ToolResultOrigin.refusal,
  'lib/core/services/browser_session_service.dart': ToolResultOrigin.refusal,
};

ToolResultOrigin? _originOf(String payload) =>
    ToolResultOrigin.fromPayload(jsonDecode(payload) as Map<String, Object?>);

String? _codeOf(String payload) =>
    (jsonDecode(payload) as Map<String, Object?>)['code'] as String?;

void main() {
  group('declared origin, read off the real producers', () {
    test(
      'a validation-only continuation blocks a call as harness feedback',
      () {
        final result = const GoalValidationProbeGuard().evaluate(
          ToolCallInfo(id: 'call-1', name: 'write_file', arguments: const {}),
          verifierOnlyContinuation: true,
        );

        expect(result, isNotNull);
        expect(_codeOf(result!.result), GoalValidationProbeGuard.blockedCode);
        expect(_originOf(result.result), ToolResultOrigin.harness);
      },
    );

    test('a reused duplicate result is harness feedback', () {
      final payload = const DuplicateToolResultReusePayload().build(
        ToolResultInfo(
          id: 'call-1',
          name: 'read_file',
          arguments: const {},
          result: jsonEncode({'ok': true, 'content': 'hello'}),
        ),
        currentToolCallId: 'call-2',
      );

      expect(_codeOf(payload), 'duplicate_tool_call_result_reused');
      expect(_originOf(payload), ToolResultOrigin.harness);
    });

    test('a call left pending by loop exhaustion is harness feedback', () {
      final pending = const ToolLoopRecoveryPolicy()
          .buildUnexecutedPendingToolResults(
            toolCalls: [
              ToolCallInfo(
                id: 'call-1',
                name: 'local_execute_command',
                arguments: const {},
              ),
            ],
            executedToolCallKeys: const <String>{},
            commandRetryGeneration: 0,
            toolCallKey: (toolCall, generation) =>
                '${toolCall.name}#$generation',
          );

      expect(pending, hasLength(1));
      expect(_codeOf(pending.single.result), 'tool_call_not_executed');
      expect(_originOf(pending.single.result), ToolResultOrigin.harness);
    });

    test('a blocked unexecuted file mutation is harness feedback', () {
      final payload = const UnexecutedFileMutationBlockPayload().encode(
        blockedTool: 'local_execute_command',
        claimedResponse: 'I updated the config file.',
      );

      expect(_codeOf(payload), 'unexecuted_file_save');
      expect(_originOf(payload), ToolResultOrigin.harness);
    });

    test('an unapproved production release is a refusal', () {
      final result = buildProductionReleaseBlockedResult(
        toolName: 'local_execute_command',
        command: 'fastlane release',
        assistantIntent: 'Ship the build',
        approvalToken: 'token-123',
      );

      expect(
        _codeOf(result.result),
        'production_release_explicit_approval_required',
      );
      expect(_originOf(result.result), ToolResultOrigin.refusal);
    });

    test('a git write through the local shell is a refusal', () {
      final payload = LocalShellTools.gitWriteCommandBlockedResult(
        command: 'git commit -m "wip"',
        workingDirectory: '/tmp/project',
      );

      expect(payload, isNotNull);
      expect(_codeOf(payload!), 'local_shell_git_write_blocked');
      expect(_originOf(payload), ToolResultOrigin.refusal);
    });

    test('a mutation outside the project root is a refusal', () {
      final denied = ProjectMutationPathAuthorization.denied(
        ProjectMutationPathDenial.outsideProject,
        toolName: 'write_file',
        canonicalRoot: '/tmp/project',
        rawPath: '/etc/hosts',
      );

      expect(denied.deniedResult, isNotNull);
      expect(
        _codeOf(denied.deniedResult!.result),
        'project_mutation_outside_root',
      );
      expect(_originOf(denied.deniedResult!.result), ToolResultOrigin.refusal);
    });

    test('ownerless dispatch is a refusal', () {
      final result = OwnerRequiredToolResult.create('local_execute_command');

      expect(_codeOf(result.result), 'chat_turn_owner_required');
      expect(_originOf(result.result), ToolResultOrigin.refusal);
    });

    test('a mutation outside the saved task target files is a refusal', () {
      final result = const SavedTaskTargetScopeGuard().evaluate(
        SavedTaskTargetScopeInput(
          owner: ChatTurnOwner(
            conversationId: 'conversation-a',
            interactionGeneration: 1,
          ),
          toolCall: ToolCallInfo(
            id: 'call-1',
            name: 'write_file',
            arguments: const {'path': 'js/player.js', 'content': 'x\n'},
          ),
          ownerTask: ConversationWorkflowTask(
            id: 'task-1',
            title: 'Build the page',
            targetFiles: const ['index.html'],
          ),
          ownerProjectRoot: '/workspace/project',
        ),
      );

      expect(result, isNotNull);
      expect(_codeOf(result!.result), SavedTaskTargetScopeGuard.blockedCode);
      expect(_originOf(result.result), ToolResultOrigin.refusal);
    });
  });

  group('declaration retention', () {
    test('every registered producer still declares its origin', () {
      // The producers above are covered by running them. The rest need
      // runtime state this test has no business assembling, so they are held
      // to the weaker but still structural claim: the declaration is present
      // in the source. Deleting a marker during an unrelated edit fails here
      // rather than silently emptying a measurement months later.
      final missing = <String>[];
      for (final entry in _producers.entries) {
        final file = File(entry.key);
        expect(file.existsSync(), isTrue, reason: '${entry.key} is missing');
        final source = file.readAsStringSync();
        if (!source.contains('ToolResultOrigin.${entry.value.name}.marker')) {
          missing.add('${entry.key} -> ${entry.value.name}');
        }
      }
      expect(missing, isEmpty, reason: 'producers without a declaration');
    });

    test('no producer declares both origins', () {
      // A file emitting both would make the marker ambiguous per site rather
      // than per payload, which is the drift the shared registry is meant to
      // prevent. Split the file instead of widening this test.
      for (final entry in _producers.entries) {
        final source = File(entry.key).readAsStringSync();
        final other = entry.value == ToolResultOrigin.harness
            ? ToolResultOrigin.refusal
            : ToolResultOrigin.harness;
        expect(
          source.contains('ToolResultOrigin.${other.name}.marker'),
          isFalse,
          reason: '${entry.key} declares both origins',
        );
      }
    });
  });
}
