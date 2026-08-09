import 'dart:async';
import 'dart:convert';

import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/core/types/goal_completion_policy.dart';
import 'package:caverno/features/chat/application/runtime/turn_runtime_conversation_goal_store.dart';
import 'package:caverno/features/chat/data/datasources/llm_session_log_store.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/goal_update_tool_contract.dart';
import 'package:caverno/features/chat/domain/services/tool_result_prompt_builder.dart';
import 'package:caverno/features/chat/presentation/providers/turn_finalization_state_registry.dart';
import 'package:caverno/features/chat/presentation/providers/turn_goal_completion_evidence_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final owner = ChatTurnOwner(
    conversationId: 'thread-a',
    interactionGeneration: 7,
  );

  test('requires an active owner for replacement and updates', () {
    final registry = TurnGoalCompletionEvidenceRegistry();
    const replacement = ToolResultCompletionEvidence(
      hasFailedExecutionVerification: true,
    );
    var transformed = false;

    expect(registry.isEmpty, isTrue);
    expect(registry.length, 0);
    expect(registry.contains(owner), isFalse);
    expect(registry.evidenceFor(owner), isNull);
    expect(registry.replace(owner, replacement), isFalse);
    expect(
      registry.update(owner, (evidence) {
        transformed = true;
        return evidence;
      }),
      isNull,
    );
    expect(transformed, isFalse);

    expect(registry.begin(owner), isTrue);
    expect(registry.begin(owner), isFalse);
    expect(registry.contains(owner), isTrue);
    expect(registry.isEmpty, isFalse);
    expect(registry.length, 1);
    expect(registry.evidenceFor(owner)?.hasIncompleteEvidence, isFalse);

    expect(registry.replace(owner, replacement), isTrue);
    expect(identical(registry.evidenceFor(owner), replacement), isTrue);
    const updated = ToolResultCompletionEvidence(
      unresolvedErrorCount: 2,
      unresolvedErrorPaths: <String>['lib/a.dart'],
    );
    expect(identical(registry.update(owner, (_) => updated), updated), isTrue);
    expect(identical(registry.evidenceFor(owner), updated), isTrue);
  });

  test('keeps call-time result combination read-only', () {
    const initial = ToolResultCompletionEvidence(
      hasFailedExecutionVerification: true,
    );
    final registry = TurnGoalCompletionEvidenceRegistry();
    final failedCommand = ToolResultInfo(
      id: 'verify',
      name: 'local_execute_command',
      arguments: const <String, dynamic>{},
      result: jsonEncode(<String, dynamic>{'exit_code': 1}),
    );

    expect(registry.begin(owner, initialEvidence: initial), isTrue);
    final combined = registry.combinedToolResultsFor(owner, [failedCommand]);

    expect(combined.hasFailedExecutionVerification, isTrue);
    expect(identical(registry.evidenceFor(owner), initial), isTrue);
  });

  test('producer combination replaces only registered owner evidence', () {
    final registry = TurnGoalCompletionEvidenceRegistry();
    final unexecutedAction = ToolResultInfo(
      id: 'unexecuted',
      name: 'local_execute_command',
      arguments: const <String, dynamic>{},
      result: jsonEncode(<String, dynamic>{
        'ok': false,
        'code': 'unexecuted_command_action',
      }),
    );

    final inactive = registry.replaceWithToolResults(owner, [unexecutedAction]);
    expect(inactive.hasUnexecutedActionClaim, isTrue);
    expect(registry.evidenceFor(owner), isNull);

    expect(registry.begin(owner), isTrue);
    final active = registry.replaceWithToolResults(owner, [unexecutedAction]);
    expect(active.hasUnexecutedActionClaim, isTrue);
    expect(identical(registry.evidenceFor(owner), active), isTrue);

    const failed = ToolResultCompletionEvidence(
      hasFailedExecutionVerification: true,
    );
    final combined = registry.replaceWithCombinedEvidence(owner, failed);
    expect(identical(registry.evidenceFor(owner), combined), isTrue);
    expect(combined.hasFailedExecutionVerification, isTrue);
    expect(combined.hasUnexecutedActionClaim, isTrue);
  });

  test(
    'final reconciliation uses content evidence and execution generations',
    () {
      final registry = TurnGoalCompletionEvidenceRegistry();
      final diagnostic = ToolResultInfo(
        id: 'diagnostic',
        name: 'dart_analyze_feedback',
        arguments: const <String, dynamic>{},
        result: jsonEncode(<String, dynamic>{
          'diagnostics': <Map<String, dynamic>>[
            <String, dynamic>{
              'severity': 'Error',
              'path': '/tmp/app/lib/main.dart',
              'relative_path': 'lib/main.dart',
              'code': 'undefined_identifier',
              'message': 'Undefined name.',
            },
          ],
        }),
      );

      expect(registry.begin(owner), isTrue);
      final contentEvidence = registry.reconcileForFinalization(
        owner,
        completedToolResults: const <ToolResultInfo>[],
        contentToolResults: [diagnostic],
      );
      expect(contentEvidence.unresolvedErrorCount, 1);
      expect(identical(registry.evidenceFor(owner), contentEvidence), isTrue);

      const pendingVerification = ToolResultCompletionEvidence(
        mutatedWithoutExecutionVerification: true,
        unverifiedChangePaths: <String>['lib/main.dart'],
      );
      expect(registry.replace(owner, pendingVerification), isTrue);
      final settled = registry.reconcileForFinalization(
        owner,
        completedToolResults: const <ToolResultInfo>[],
        contentToolResults: const <ToolResultInfo>[],
        mutationGeneration: 3,
        verificationGeneration: 3,
      );
      expect(settled.hasSuccessfulExecutionVerification, isTrue);
      expect(settled.hasIncompleteEvidence, isFalse);
    },
  );

  test('saved validation settlement requires successful validation', () {
    final timestamp = DateTime.utc(2026, 7, 29);
    final conversation = Conversation(
      id: 'thread-a',
      title: 'Thread A',
      messages: const [],
      createdAt: timestamp,
      updatedAt: timestamp,
      mutationGeneration: 4,
      verificationGeneration: 3,
    );
    const pending = ToolResultCompletionEvidence(
      mutatedWithoutExecutionVerification: true,
      unverifiedChangePaths: <String>['lib/main.dart'],
    );
    final registry = TurnGoalCompletionEvidenceRegistry();

    expect(
      identical(
        registry.settleSuccessfulSavedValidation(
          pending,
          conversation: conversation,
          succeeded: false,
        ),
        pending,
      ),
      isTrue,
    );
    final settled = registry.settleSuccessfulSavedValidation(
      pending,
      conversation: conversation,
      succeeded: true,
    );
    expect(settled.hasSuccessfulExecutionVerification, isTrue);
    expect(settled.hasIncompleteEvidence, isFalse);
  });

  test('keeps equal generations isolated by conversation', () {
    final peer = ChatTurnOwner(
      conversationId: 'thread-b',
      interactionGeneration: 7,
    );
    const ownerEvidence = ToolResultCompletionEvidence(
      hasFailedExecutionVerification: true,
    );
    const peerEvidence = ToolResultCompletionEvidence(
      hasSuccessfulExecutionVerification: true,
    );
    final registry = TurnGoalCompletionEvidenceRegistry();

    expect(registry.begin(owner, initialEvidence: ownerEvidence), isTrue);
    expect(registry.begin(peer, initialEvidence: peerEvidence), isTrue);
    expect(identical(registry.evidenceFor(owner), ownerEvidence), isTrue);
    expect(identical(registry.evidenceFor(peer), peerEvidence), isTrue);

    const ownerReplacement = ToolResultCompletionEvidence(
      boundedToolLoopExhausted: true,
    );
    expect(registry.replace(owner, ownerReplacement), isTrue);
    expect(identical(registry.evidenceFor(owner), ownerReplacement), isTrue);
    expect(identical(registry.evidenceFor(peer), peerEvidence), isTrue);
  });

  test('seeds successors only from their explicit evidence', () {
    final successor = ChatTurnOwner(
      conversationId: 'thread-a',
      interactionGeneration: 8,
    );
    final unseededSuccessor = ChatTurnOwner(
      conversationId: 'thread-a',
      interactionGeneration: 9,
    );
    const carriedEvidence = ToolResultCompletionEvidence(
      unresolvedErrorCount: 1,
      unresolvedErrorPaths: <String>['lib/pending.dart'],
    );
    final registry = TurnGoalCompletionEvidenceRegistry();

    expect(registry.begin(owner), isTrue);
    expect(registry.dispose(owner), isTrue);
    expect(registry.begin(successor, initialEvidence: carriedEvidence), isTrue);
    expect(identical(registry.evidenceFor(successor), carriedEvidence), isTrue);
    expect(registry.dispose(successor), isTrue);

    expect(registry.begin(unseededSuccessor), isTrue);
    final unseededEvidence = registry.evidenceFor(unseededSuccessor);
    expect(unseededEvidence, isNotNull);
    expect(unseededEvidence?.hasIncompleteEvidence, isFalse);
    expect(identical(unseededEvidence, carriedEvidence), isFalse);
  });

  test('disposal is owner-local and rejects late writes', () {
    final peer = ChatTurnOwner(
      conversationId: 'thread-b',
      interactionGeneration: 7,
    );
    final olderOwner = ChatTurnOwner(
      conversationId: 'thread-a',
      interactionGeneration: 6,
    );
    final newerOwner = ChatTurnOwner(
      conversationId: 'thread-a',
      interactionGeneration: 8,
    );
    final newerPeer = ChatTurnOwner(
      conversationId: 'thread-b',
      interactionGeneration: 8,
    );
    const peerEvidence = ToolResultCompletionEvidence(
      hasSuccessfulExecutionVerification: true,
    );
    const lateEvidence = ToolResultCompletionEvidence(
      hasFailedExecutionVerification: true,
    );
    final registry = TurnGoalCompletionEvidenceRegistry();

    expect(registry.begin(owner), isTrue);
    expect(registry.begin(peer, initialEvidence: peerEvidence), isTrue);
    expect(registry.dispose(owner), isTrue);
    expect(registry.dispose(owner), isFalse);
    expect(registry.contains(owner), isFalse);
    expect(registry.begin(owner), isFalse);
    expect(registry.begin(olderOwner), isFalse);
    expect(registry.replace(owner, lateEvidence), isFalse);
    expect(registry.update(owner, (_) => lateEvidence), isNull);
    expect(identical(registry.evidenceFor(peer), peerEvidence), isTrue);

    expect(registry.begin(newerOwner), isTrue);
    registry.clear();
    expect(registry.isEmpty, isTrue);
    expect(registry.begin(peer), isFalse);
    expect(registry.begin(newerOwner), isFalse);
    expect(registry.begin(newerPeer), isTrue);
    registry.clear();
    registry.clear();
    expect(registry.isEmpty, isTrue);
  });

  test(
    'finalizer captures claim and shadow outcome before persistence',
    () async {
      final evidenceRegistry = TurnGoalCompletionEvidenceRegistry();
      final finalizationState = TurnFinalizationStateRegistry();
      final goalWrite = Completer<bool>();
      final timestamp = DateTime.utc(2026, 7, 29);
      final conversation = Conversation(
        id: 'thread-a',
        title: 'Thread A',
        messages: const [],
        createdAt: timestamp,
        updatedAt: timestamp,
        goal: ConversationGoal(
          id: 'goal-a',
          objective: 'Complete owner A work',
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
        mutationGeneration: 2,
        verificationGeneration: 2,
      );
      const context = LlmSessionLogContext(
        workspaceMode: WorkspaceMode.coding,
        sessionId: 'thread-a',
        conversationId: 'thread-a',
      );
      late String recordedConversationId;
      late bool recordedClaim;
      late ToolResultCompletionEvidence recordedEvidence;
      ChatTurnOwner? shadowOwner;
      GoalUpdateAckOutcome? shadowOutcome;
      bool? shadowLexicalCompleted;

      expect(evidenceRegistry.begin(owner), isTrue);
      expect(finalizationState.begin(owner), isTrue);
      expect(finalizationState.markGoalClaimed(owner), isTrue);
      expect(
        finalizationState.setGoalOutcome(
          owner,
          GoalUpdateAckOutcome.completionRecorded,
        ),
        isTrue,
      );
      final future =
          TurnGoalCompletionFinalizer(
            goalStore: _GoalStore(),
            recordGoalTurn:
                ({
                  required assistantResponse,
                  required tokenUsageDelta,
                  required completionEvidence,
                  required toolCompletionClaimed,
                  required conversationId,
                }) {
                  expect(assistantResponse, 'Done through the tool.');
                  expect(tokenUsageDelta, 41);
                  recordedConversationId = conversationId;
                  recordedClaim = toolCompletionClaimed;
                  recordedEvidence = completionEvidence;
                  return goalWrite.future;
                },
            recordGoalCompletionShadow:
                ({
                  required lexicalCompleted,
                  required owner,
                  required context,
                  required toolCompletionOutcome,
                }) async {
                  expect(context.conversationId, 'thread-a');
                  shadowOwner = owner;
                  shadowOutcome = toolCompletionOutcome;
                  shadowLexicalCompleted = lexicalCompleted;
                },
          ).finalize(
            owner: owner,
            evidenceRegistry: evidenceRegistry,
            finalizationState: finalizationState,
            completedToolResults: const <ToolResultInfo>[],
            contentToolResults: const <ToolResultInfo>[],
            conversation: conversation,
            assistantResponse: 'Done through the tool.',
            tokenUsageDelta: 41,
            context: context,
          );

      await Future<void>.delayed(Duration.zero);
      expect(recordedConversationId, 'thread-a');
      expect(recordedClaim, isTrue);
      expect(finalizationState.takeGoalClaim(owner), isFalse);
      expect(finalizationState.takeGoalOutcome(owner), isNull);
      expect(finalizationState.dispose(owner), isTrue);
      goalWrite.complete(false);

      final evidence = await future;
      expect(evidence, isNotNull);
      expect(identical(evidence, recordedEvidence), isTrue);
      expect(evidence?.hasSuccessfulExecutionVerification, isTrue);
      expect(shadowOwner, owner);
      expect(shadowOutcome, GoalUpdateAckOutcome.completionRecorded);
      expect(shadowLexicalCompleted, isFalse);
    },
  );

  test(
    'finalizer downgrades a call-time completion from final evidence',
    () async {
      final evidenceRegistry = TurnGoalCompletionEvidenceRegistry();
      final finalizationState = TurnFinalizationStateRegistry();
      final timestamp = DateTime.utc(2026, 8, 9);
      final conversation = Conversation(
        id: 'thread-a',
        title: 'Thread A',
        messages: const [],
        createdAt: timestamp,
        updatedAt: timestamp,
        goal: ConversationGoal(
          id: 'goal-a',
          objective: 'Verify the final result',
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      );
      final request = GoalUpdateToolRequest(
        owner: owner,
        toolCallId: 'completion-before-late-failure',
        toolName: canonicalGoalUpdateToolName,
        arguments: const {'completed': true},
      );
      final acknowledgement = GoalUpdateCompletionAcknowledgement(
        identity: request.identity,
        outcome: GoalUpdateAckOutcome.completionRecorded,
        input: const GoalUpdateInput(completed: true),
        completionPolicy: GoalCompletionPolicy.toolOrAsk,
      );
      bool? finalClaim;
      GoalUpdateAckOutcome? finalShadowOutcome;

      expect(evidenceRegistry.begin(owner), isTrue);
      expect(
        evidenceRegistry.replace(
          owner,
          const ToolResultCompletionEvidence(
            hasFailedExecutionVerification: true,
          ),
        ),
        isTrue,
      );
      expect(finalizationState.begin(owner), isTrue);
      expect(
        finalizationState.recordGoalAcknowledgement(owner, acknowledgement),
        isTrue,
      );

      await TurnGoalCompletionFinalizer(
        goalStore: _GoalStore(),
        recordGoalTurn:
            ({
              required assistantResponse,
              required tokenUsageDelta,
              required completionEvidence,
              required toolCompletionClaimed,
              required conversationId,
            }) async {
              finalClaim = toolCompletionClaimed;
              return true;
            },
        recordGoalCompletionShadow:
            ({
              required lexicalCompleted,
              required owner,
              required context,
              required toolCompletionOutcome,
            }) async {
              finalShadowOutcome = toolCompletionOutcome;
            },
      ).finalize(
        owner: owner,
        evidenceRegistry: evidenceRegistry,
        finalizationState: finalizationState,
        completedToolResults: const [],
        contentToolResults: const [],
        conversation: conversation,
        assistantResponse: 'All tests passed.',
        tokenUsageDelta: 10,
        context: const LlmSessionLogContext(
          workspaceMode: WorkspaceMode.coding,
          sessionId: 'thread-a',
          conversationId: 'thread-a',
        ),
      );

      expect(finalClaim, isFalse);
      expect(finalShadowOutcome, GoalUpdateAckOutcome.completionRejected);
    },
  );

  test(
    'finalizer excludes turns without an active goal from shadow data',
    () async {
      final evidenceRegistry = TurnGoalCompletionEvidenceRegistry();
      final finalizationState = TurnFinalizationStateRegistry();
      final timestamp = DateTime.utc(2026, 8, 9);
      final conversation = Conversation(
        id: 'thread-a',
        title: 'Thread A',
        messages: const [],
        createdAt: timestamp,
        updatedAt: timestamp,
      );
      const context = LlmSessionLogContext(
        workspaceMode: WorkspaceMode.coding,
        sessionId: 'thread-a',
        conversationId: 'thread-a',
      );
      var goalWrites = 0;
      var shadowWrites = 0;

      expect(evidenceRegistry.begin(owner), isTrue);
      expect(finalizationState.begin(owner), isTrue);
      final evidence =
          await TurnGoalCompletionFinalizer(
            goalStore: _GoalStore(),
            recordGoalTurn:
                ({
                  required assistantResponse,
                  required tokenUsageDelta,
                  required completionEvidence,
                  required toolCompletionClaimed,
                  required conversationId,
                }) async {
                  goalWrites += 1;
                  return false;
                },
            recordGoalCompletionShadow:
                ({
                  required lexicalCompleted,
                  required owner,
                  required context,
                  required toolCompletionOutcome,
                }) async {
                  shadowWrites += 1;
                },
          ).finalize(
            owner: owner,
            evidenceRegistry: evidenceRegistry,
            finalizationState: finalizationState,
            completedToolResults: const <ToolResultInfo>[],
            contentToolResults: const <ToolResultInfo>[],
            conversation: conversation,
            assistantResponse: 'No goal is active.',
            tokenUsageDelta: 0,
            context: context,
          );

      expect(evidence, isNotNull);
      expect(goalWrites, 1);
      expect(shadowWrites, 0);
    },
  );

  test('finalizer asks the user for an admissible ask-policy claim', () async {
    final evidenceRegistry = TurnGoalCompletionEvidenceRegistry();
    final finalizationState = TurnFinalizationStateRegistry();
    final goalStore = _GoalStore();
    final timestamp = DateTime.utc(2026, 8, 9);
    final conversation = Conversation(
      id: owner.conversationId,
      title: 'Thread A',
      messages: const [],
      createdAt: timestamp,
      updatedAt: timestamp,
      goal: ConversationGoal(
        id: 'goal-a',
        objective: 'Finish the implementation',
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
    );
    final request = GoalUpdateToolRequest(
      owner: owner,
      toolCallId: 'ask-policy-completion',
      toolName: canonicalGoalUpdateToolName,
      arguments: const {'completed': true},
    );
    final acknowledgement = GoalUpdateCompletionAcknowledgement.fromRequest(
      request: request,
      outcome: GoalUpdateAckOutcome.confirmationRequired,
      completionPolicy: GoalCompletionPolicy.ask,
    );
    GoalUpdateAckOutcome? shadowOutcome;

    expect(evidenceRegistry.begin(owner), isTrue);
    expect(finalizationState.begin(owner), isTrue);
    expect(
      finalizationState.recordGoalAcknowledgement(owner, acknowledgement),
      isTrue,
    );

    await TurnGoalCompletionFinalizer(
      goalStore: goalStore,
      recordGoalTurn:
          ({
            required assistantResponse,
            required tokenUsageDelta,
            required completionEvidence,
            required toolCompletionClaimed,
            required conversationId,
          }) async {
            expect(toolCompletionClaimed, isFalse);
            return false;
          },
      recordGoalCompletionShadow:
          ({
            required lexicalCompleted,
            required owner,
            required context,
            required toolCompletionOutcome,
          }) async {
            shadowOutcome = toolCompletionOutcome;
          },
    ).finalize(
      owner: owner,
      evidenceRegistry: evidenceRegistry,
      finalizationState: finalizationState,
      completedToolResults: const [],
      contentToolResults: const [],
      conversation: conversation,
      assistantResponse: 'The implementation is complete.',
      tokenUsageDelta: 0,
      context: const LlmSessionLogContext(
        workspaceMode: WorkspaceMode.coding,
        sessionId: 'thread-a',
        conversationId: 'thread-a',
      ),
    );

    expect(goalStore.status, ConversationGoalStatus.awaitingConfirmation);
    expect(goalStore.completionSummary, contains('Confirm completion'));
    expect(shadowOutcome, GoalUpdateAckOutcome.confirmationRequired);
  });

  test('finalizer records no shadow when goal persistence fails', () async {
    final evidenceRegistry = TurnGoalCompletionEvidenceRegistry();
    final finalizationState = TurnFinalizationStateRegistry();
    const context = LlmSessionLogContext(
      workspaceMode: WorkspaceMode.coding,
      sessionId: 'thread-a',
      conversationId: 'thread-a',
    );
    var shadowWrites = 0;

    expect(evidenceRegistry.begin(owner), isTrue);
    expect(finalizationState.begin(owner), isTrue);
    expect(finalizationState.markGoalClaimed(owner), isTrue);
    expect(
      finalizationState.setGoalOutcome(
        owner,
        GoalUpdateAckOutcome.completionRecorded,
      ),
      isTrue,
    );

    final future =
        TurnGoalCompletionFinalizer(
          goalStore: _GoalStore(),
          recordGoalTurn:
              ({
                required assistantResponse,
                required tokenUsageDelta,
                required completionEvidence,
                required toolCompletionClaimed,
                required conversationId,
              }) async {
                throw StateError('Goal persistence failed.');
              },
          recordGoalCompletionShadow:
              ({
                required lexicalCompleted,
                required owner,
                required context,
                required toolCompletionOutcome,
              }) async {
                shadowWrites += 1;
              },
        ).finalize(
          owner: owner,
          evidenceRegistry: evidenceRegistry,
          finalizationState: finalizationState,
          completedToolResults: const <ToolResultInfo>[],
          contentToolResults: const <ToolResultInfo>[],
          conversation: null,
          assistantResponse: 'Done.',
          tokenUsageDelta: 0,
          context: context,
        );

    await expectLater(future, throwsStateError);
    expect(shadowWrites, 0);
    expect(finalizationState.takeGoalClaim(owner), isFalse);
    expect(finalizationState.takeGoalOutcome(owner), isNull);
  });

  test('finalizer rejects owners missing either lifecycle registry', () async {
    const context = LlmSessionLogContext(
      workspaceMode: WorkspaceMode.coding,
      sessionId: 'thread-a',
    );
    var goalWrites = 0;
    var shadowWrites = 0;

    for (final missingEvidence in <bool>[true, false]) {
      final evidenceRegistry = TurnGoalCompletionEvidenceRegistry();
      final finalizationState = TurnFinalizationStateRegistry();
      if (!missingEvidence) {
        expect(evidenceRegistry.begin(owner), isTrue);
      } else {
        expect(finalizationState.begin(owner), isTrue);
      }
      final result =
          await TurnGoalCompletionFinalizer(
            goalStore: _GoalStore(),
            recordGoalTurn:
                ({
                  required assistantResponse,
                  required tokenUsageDelta,
                  required completionEvidence,
                  required toolCompletionClaimed,
                  required conversationId,
                }) async {
                  goalWrites += 1;
                  return false;
                },
            recordGoalCompletionShadow:
                ({
                  required lexicalCompleted,
                  required owner,
                  required context,
                  required toolCompletionOutcome,
                }) async {
                  shadowWrites += 1;
                },
          ).finalize(
            owner: owner,
            evidenceRegistry: evidenceRegistry,
            finalizationState: finalizationState,
            completedToolResults: const <ToolResultInfo>[],
            contentToolResults: const <ToolResultInfo>[],
            conversation: null,
            assistantResponse: 'Done.',
            tokenUsageDelta: 0,
            context: context,
          );
      expect(result, isNull);
    }

    expect(goalWrites, 0);
    expect(shadowWrites, 0);
  });
}

final class _GoalStore implements TurnRuntimeConversationGoalStore {
  ConversationGoalStatus? status;
  String? completionSummary;

  @override
  Conversation? conversationForId(String conversationId) => null;

  @override
  Future<void> markGoalStatus({
    required String conversationId,
    required ConversationGoalStatus status,
    String? blockedReason,
    String? completionSummary,
  }) async {
    this.status = status;
    this.completionSummary = completionSummary;
  }
}
