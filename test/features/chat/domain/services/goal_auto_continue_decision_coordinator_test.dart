import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/services/conversation_goal_auto_continue_policy.dart';
import 'package:caverno/features/chat/domain/services/goal_auto_continue_decision_coordinator.dart';
import 'package:caverno/features/chat/domain/services/goal_auto_continue_tracker_registry.dart';
import 'package:caverno/features/chat/domain/services/short_prompt_contract_builder.dart';
import 'package:caverno/features/chat/domain/services/tool_result_prompt_builder.dart';
import 'package:caverno/features/chat/domain/services/verification_cadence_policy.dart';
import 'package:test/test.dart';

const _coordinator = GoalAutoContinueDecisionCoordinator();

ChatTurnOwner _owner(String conversationId, {int generation = 1}) {
  return ChatTurnOwner(
    conversationId: conversationId,
    interactionGeneration: generation,
  );
}

ConversationGoal _goal({
  bool enabled = true,
  bool autoContinue = true,
  ConversationGoalStatus status = ConversationGoalStatus.active,
  int tokenBudget = 0,
  int tokenUsage = 0,
  int turnBudget = 0,
  int turnsUsed = 1,
}) {
  return ConversationGoal(
    id: 'goal-1',
    objective: 'Finish the owner task',
    enabled: enabled,
    autoContinue: autoContinue,
    status: status,
    tokenBudget: tokenBudget,
    tokenUsage: tokenUsage,
    turnBudget: turnBudget,
    turnsUsed: turnsUsed,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}

Conversation _conversation({
  String id = 'owner-conversation',
  WorkspaceMode workspaceMode = WorkspaceMode.coding,
  ConversationGoal? goal,
  bool includeGoal = true,
  ConversationWorkflowSpec? workflowSpec,
  int mutationGeneration = 1,
  int verificationGeneration = 1,
}) {
  return Conversation(
    id: id,
    title: id,
    messages: const [],
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    workspaceMode: workspaceMode,
    workflowSpec: workflowSpec,
    mutationGeneration: mutationGeneration,
    verificationGeneration: verificationGeneration,
    goal: includeGoal ? (goal ?? _goal()) : null,
  );
}

GoalVerifierReplayCandidateSnapshot _verifierCandidate() {
  return (
    id: 'verifier-1',
    name: 'run_tests',
    arguments: const <String, dynamic>{'path': 'test/'},
    taskId: null,
    priority: 2,
  );
}

GoalAutoContinueTrackerSnapshot _tracker({
  int consecutiveAutoContinuations = 0,
  int diagnosticRepairContinuations = 0,
  bool diagnosticRepairExtensionUsed = false,
  int noProgressStreak = 0,
  int consecutiveValidationMisses = 0,
  bool failedVerificationObserved = false,
  ToolResultCompletionEvidence? previousEvidence,
  String previousDiagnosticSignature = '',
  int identicalDiagnosticSignatureStreak = 0,
  bool pendingPostRepairReplayOutcome = false,
  bool pendingRepairContractOutcome = false,
  bool repairNoMutationRetryUsed = false,
  int? completionElicitationMutationGeneration,
  GoalVerifierReplayCandidateSnapshot? verifierReplayCandidate,
  bool budgetNoticePresented = false,
}) {
  return (
    consecutiveAutoContinuations: consecutiveAutoContinuations,
    diagnosticRepairContinuations: diagnosticRepairContinuations,
    diagnosticRepairExtensionUsed: diagnosticRepairExtensionUsed,
    noProgressStreak: noProgressStreak,
    consecutiveValidationMisses: consecutiveValidationMisses,
    failedVerificationObserved: failedVerificationObserved,
    previousEvidence: previousEvidence,
    previousDiagnosticSignature: previousDiagnosticSignature,
    identicalDiagnosticSignatureStreak: identicalDiagnosticSignatureStreak,
    pendingPostRepairReplayOutcome: pendingPostRepairReplayOutcome,
    pendingRepairContractOutcome: pendingRepairContractOutcome,
    repairNoMutationRetryUsed: repairNoMutationRetryUsed,
    completionElicitationMutationGeneration:
        completionElicitationMutationGeneration,
    activeCommandDiagnosticRepairFocus: null,
    verifierReplayCandidate: verifierReplayCandidate,
    replayedMutationGenerations: const <int>{},
    replayedInteractionGenerations: const <int>{},
    budgetNoticePresented: budgetNoticePresented,
  );
}

GoalAutoContinueSafeBoundary _safeBoundary({
  bool isLoading = false,
  bool hasQueuedUserInput = false,
  bool hasPendingSshConnect = false,
  bool hasPendingSshCommand = false,
  bool hasPendingGitCommand = false,
  bool hasPendingLocalCommand = false,
  bool hasPendingComputerUseAction = false,
  bool hasPendingBrowserAction = false,
  bool hasPendingFileOperation = false,
  bool hasPendingBleConnect = false,
  bool hasPendingSerialOpen = false,
  bool hasPendingParticipantToolApproval = false,
  bool hasPendingAskUserQuestion = false,
  bool hasPendingWorkflowDecision = false,
  bool hasParticipantTurnRuntime = false,
  bool hasError = false,
}) {
  return GoalAutoContinueSafeBoundary(
    isLoading: isLoading,
    hasQueuedUserInput: hasQueuedUserInput,
    hasPendingSshConnect: hasPendingSshConnect,
    hasPendingSshCommand: hasPendingSshCommand,
    hasPendingGitCommand: hasPendingGitCommand,
    hasPendingLocalCommand: hasPendingLocalCommand,
    hasPendingComputerUseAction: hasPendingComputerUseAction,
    hasPendingBrowserAction: hasPendingBrowserAction,
    hasPendingFileOperation: hasPendingFileOperation,
    hasPendingBleConnect: hasPendingBleConnect,
    hasPendingSerialOpen: hasPendingSerialOpen,
    hasPendingParticipantToolApproval: hasPendingParticipantToolApproval,
    hasPendingAskUserQuestion: hasPendingAskUserQuestion,
    hasPendingWorkflowDecision: hasPendingWorkflowDecision,
    hasParticipantTurnRuntime: hasParticipantTurnRuntime,
    hasError: hasError,
  );
}

const _incompleteEvidence = ToolResultCompletionEvidence(
  boundedToolLoopExhausted: true,
  unexecutedToolNames: ['read_file'],
);

ToolResultCompletionEvidence _diagnosticEvidence({
  required int count,
  String signature = '',
}) {
  return ToolResultCompletionEvidence(
    unresolvedErrorCount: count,
    unresolvedErrorPaths: const ['lib/main.dart'],
    unresolvedErrorDiagnostics: const [
      UnresolvedErrorDiagnostic(
        path: 'lib/main.dart',
        code: 'compile_error',
        message: 'Compilation failed.',
      ),
    ],
    diagnosticSignature: signature,
  );
}

GoalAutoContinueDecisionInput _input({
  ChatTurnOwner? owner,
  Conversation? conversation,
  GoalAutoContinueTrackerSnapshot? tracker,
  ToolResultCompletionEvidence evidence = _incompleteEvidence,
  String finalizedAssistantResponse = 'Work remains.',
  GoalAutoContinueSafeBoundary? safeBoundary,
  bool isVoiceMode = false,
}) {
  final resolvedConversation = conversation ?? _conversation();
  return GoalAutoContinueDecisionInput(
    owner: owner ?? _owner(resolvedConversation.id),
    ownerConversation: resolvedConversation,
    tracker: tracker ?? _tracker(),
    completionEvidence: evidence,
    finalizedAssistantResponse: finalizedAssistantResponse,
    safeBoundary: safeBoundary ?? _safeBoundary(),
    isVoiceMode: isVoiceMode,
  );
}

void main() {
  group('owner and mode vetoes', () {
    test('rejects a conversation that does not match the exact owner', () {
      final plan = _coordinator.coordinate(
        _input(
          owner: _owner('owner-a'),
          conversation: _conversation(id: 'visible-peer'),
        ),
      );

      expect(
        plan.reason.code,
        GoalAutoContinueCoordinationReasonCode.ownerConversationMismatch,
      );
      expect(plan.policyInput, isNull);
      expect(plan.effectiveTurnBudget, isNull);
      expect(plan.trackerDelta.pendingPostRepairReplayOutcome, isNull);
    });

    test('applies owner, workspace, voice, and workflow vetoes in order', () {
      const pendingWorkflow = ConversationWorkflowSpec(
        tasks: [
          ConversationWorkflowTask(
            id: 'saved-task',
            title: 'Finish saved task',
          ),
        ],
      );
      final cases = [
        (
          input: _input(
            owner: _owner('owner-a'),
            conversation: _conversation(
              id: 'visible-peer',
              workspaceMode: WorkspaceMode.chat,
              workflowSpec: pendingWorkflow,
            ),
            isVoiceMode: true,
          ),
          code:
              GoalAutoContinueCoordinationReasonCode.ownerConversationMismatch,
        ),
        (
          input: _input(
            conversation: _conversation(
              workspaceMode: WorkspaceMode.chat,
              workflowSpec: pendingWorkflow,
            ),
            isVoiceMode: true,
          ),
          code: GoalAutoContinueCoordinationReasonCode.nonCodingWorkspace,
        ),
        (
          input: _input(
            conversation: _conversation(workflowSpec: pendingWorkflow),
            isVoiceMode: true,
          ),
          code: GoalAutoContinueCoordinationReasonCode.voiceModeActive,
        ),
        (
          input: _input(
            conversation: _conversation(workflowSpec: pendingWorkflow),
            safeBoundary: _safeBoundary(isLoading: true),
          ),
          code: GoalAutoContinueCoordinationReasonCode
              .savedWorkflowOwnsContinuation,
        ),
      ];

      for (final testCase in cases) {
        final plan = _coordinator.coordinate(testCase.input);

        expect(plan.reason.code, testCase.code);
        expect(plan.policyInput, isNull);
        expect(plan.effectiveTurnBudget, isNull);
      }
    });

    test('rejects non-coding and voice-mode owner turns', () {
      final cases = [
        (
          input: _input(
            conversation: _conversation(workspaceMode: WorkspaceMode.chat),
          ),
          code: GoalAutoContinueCoordinationReasonCode.nonCodingWorkspace,
          reason: 'conversation is not in coding workspace',
        ),
        (
          input: _input(isVoiceMode: true),
          code: GoalAutoContinueCoordinationReasonCode.voiceModeActive,
          reason: 'voice mode is active',
        ),
      ];

      for (final testCase in cases) {
        final plan = _coordinator.coordinate(testCase.input);
        expect(plan.policyDecision.shouldContinue, isFalse);
        expect(plan.reason.code, testCase.code);
        expect(plan.reason.detail, testCase.reason);
        expect(plan.trackerDelta, _emptyDeltaMatcher());
      }
    });

    test('defers pending non-synthetic saved workflow tasks', () {
      final plan = _coordinator.coordinate(
        _input(
          conversation: _conversation(
            workflowSpec: const ConversationWorkflowSpec(
              tasks: [
                ConversationWorkflowTask(
                  id: 'saved-task',
                  title: 'Finish saved task',
                ),
              ],
            ),
          ),
        ),
      );

      expect(
        plan.reason.code,
        GoalAutoContinueCoordinationReasonCode.savedWorkflowOwnsContinuation,
      );
      expect(plan.reason.detail, contains('saved workflow execution'));
    });

    test('allows completed and synthetic saved workflow tasks', () {
      final synthetic = const ShortPromptContractBuilder().build(
        userMessageId: 'message-1',
        userRequest: 'Fix the analyzer error',
      )!;
      final conversations = [
        _conversation(
          workflowSpec: const ConversationWorkflowSpec(
            tasks: [
              ConversationWorkflowTask(
                id: 'saved-task',
                title: 'Finished task',
                status: ConversationWorkflowTaskStatus.completed,
              ),
            ],
          ),
        ),
        _conversation(workflowSpec: synthetic),
      ];

      for (final conversation in conversations) {
        final plan = _coordinator.coordinate(
          _input(conversation: conversation),
        );
        expect(plan.policyDecision.shouldContinue, isTrue);
      }
    });
  });

  group('progress and diagnostic progression', () {
    test('resets no-progress after improved diagnostic evidence', () {
      final plan = _coordinator.coordinate(
        _input(
          tracker: _tracker(
            noProgressStreak: 1,
            previousEvidence: _diagnosticEvidence(count: 3),
          ),
          evidence: _diagnosticEvidence(count: 2),
        ),
      );

      expect(plan.policyInput!.diagnosticEvidenceImproved, isTrue);
      expect(plan.policyInput!.noProgressStreak, 0);
      expect(plan.trackerDelta.noProgressStreak, 0);
      expect(plan.policyDecision.shouldContinue, isTrue);
    });

    test('increments no-progress and blocks stalled diagnostics', () {
      final plan = _coordinator.coordinate(
        _input(
          tracker: _tracker(
            noProgressStreak: 1,
            previousEvidence: _diagnosticEvidence(count: 2),
          ),
          evidence: _diagnosticEvidence(count: 2),
        ),
      );

      expect(plan.policyInput!.noProgressStreak, 2);
      expect(plan.policyDecision.shouldBlock, isTrue);
      expect(plan.trackerDelta.noProgressStreak, 2);
      expect(plan.trackerDelta.removeTracker, isTrue);
      expect(
        plan.reason.code,
        GoalAutoContinueCoordinationReasonCode.policyStopAndBlock,
      );
    });

    test('advances a changed post-repair verifier signature once', () {
      final plan = _coordinator.coordinate(
        _input(
          tracker: _tracker(
            diagnosticRepairContinuations:
                kGoalAutoContinueDiagnosticRepairBudget,
            previousEvidence: _diagnosticEvidence(
              count: 3,
              signature: 'old-signature',
            ),
            previousDiagnosticSignature: 'old-signature',
            identicalDiagnosticSignatureStreak: 2,
            pendingPostRepairReplayOutcome: true,
          ),
          evidence: _diagnosticEvidence(count: 2, signature: 'new-signature'),
        ),
      );

      expect(plan.policyInput!.postRepairVerifierAdvanced, isTrue);
      expect(plan.policyInput!.identicalDiagnosticSignatureStreak, 0);
      expect(plan.policyDecision.usesDiagnosticRepairExtension, isTrue);
      expect(plan.trackerDelta.diagnosticRepairExtensionUsed, isTrue);
      expect(plan.trackerDelta.pendingPostRepairReplayOutcome, isFalse);
    });

    test('preserves no-progress streak when current evidence is complete', () {
      final plan = _coordinator.coordinate(
        _input(
          tracker: _tracker(noProgressStreak: 4),
          evidence: const ToolResultCompletionEvidence(),
          conversation: _conversation(
            goal: _goal(status: ConversationGoalStatus.awaitingConfirmation),
          ),
        ),
      );

      expect(plan.policyInput!.noProgressStreak, 4);
      expect(
        plan.elicitationEligibility,
        GoalCompletionElicitationEligibility.goalStatusNotActive,
      );
    });
  });

  group('question endings and verification cadence', () {
    test('recognizes ASCII and full-width question punctuation', () {
      for (final response in ['Continue?  \n', 'Continue？\t']) {
        final plan = _coordinator.coordinate(
          _input(finalizedAssistantResponse: response),
        );

        expect(plan.policyInput!.finalAnswerEndsWithQuestion, isTrue);
        expect(plan.policyDecision.reason, 'final answer asks a question');
      }
    });

    test('does not treat other terminal punctuation as a question', () {
      final plan = _coordinator.coordinate(
        _input(finalizedAssistantResponse: 'Continue.'),
      );

      expect(plan.policyInput!.finalAnswerEndsWithQuestion, isFalse);
      expect(plan.policyDecision.shouldContinue, isTrue);
    });

    test('stable diagnostics override a terminal question', () {
      final plan = _coordinator.coordinate(
        _input(
          tracker: _tracker(
            previousDiagnosticSignature: 'stable',
            identicalDiagnosticSignatureStreak: 0,
          ),
          evidence: _diagnosticEvidence(count: 1, signature: 'stable'),
          finalizedAssistantResponse: 'Continue?',
        ),
      );

      expect(plan.policyInput!.identicalDiagnosticSignatureStreak, 1);
      expect(plan.policyDecision.shouldContinue, isTrue);
    });

    test('derives required cadence directly from the owner conversation', () {
      final ownerConversation = _conversation(
        mutationGeneration: 3,
        verificationGeneration: 1,
      );
      final visiblePeer = _conversation(
        id: 'visible-peer',
        workspaceMode: WorkspaceMode.chat,
        goal: _goal(autoContinue: false),
        mutationGeneration: 0,
        verificationGeneration: 20,
      );

      final plan = _coordinator.coordinate(
        _input(
          conversation: ownerConversation,
          evidence: const ToolResultCompletionEvidence(),
        ),
      );

      expect(visiblePeer.id, 'visible-peer');
      expect(
        plan.policyInput!.verificationCadence,
        VerificationCadence.required,
      );
      expect(plan.policyDecision.shouldContinue, isTrue);
      expect(plan.policyDecision.reason, contains('not caught up'));
      expect(
        plan.capabilityProfile,
        GoalAutoContinueCapabilityProfile.unrestricted,
      );
    });
  });

  group('budgets, notices, and policy outcomes', () {
    test('returns default continuation limits and tracker increments', () {
      final plan = _coordinator.coordinate(_input());

      expect(plan.policyDecision.shouldContinue, isTrue);
      expect(plan.effectiveTurnBudget, kGoalAutoContinueDefaultTurnBudget);
      expect(plan.continuationLimits!.nextTurnNumber, 2);
      expect(
        plan.continuationLimits!.effectiveTurnBudget,
        kGoalAutoContinueDefaultTurnBudget,
      );
      expect(plan.continuationLimits!.allowedToolNames, isNull);
      expect(plan.trackerDelta.consecutiveAutoContinuationsDelta, 1);
      expect(plan.trackerDelta.previousEvidence, same(_incompleteEvidence));
      expect(plan.trackerDelta.previousDiagnosticSignature, isEmpty);
      expect(plan.trackerDelta.pendingRepairContractOutcome, isFalse);
      expect(
        plan.reason.code,
        GoalAutoContinueCoordinationReasonCode.policyContinue,
      );
    });

    test('preserves a custom turn budget', () {
      final plan = _coordinator.coordinate(
        _input(conversation: _conversation(goal: _goal(turnBudget: 6))),
      );

      expect(plan.effectiveTurnBudget, 6);
      expect(plan.continuationLimits!.effectiveTurnBudget, 6);
    });

    test('emits one budget stop notice and tracker marker', () {
      final plan = _coordinator.coordinate(
        _input(
          conversation: _conversation(goal: _goal(turnBudget: 2, turnsUsed: 2)),
        ),
      );

      expect(
        plan.policyDecision.stopCause,
        GoalAutoContinueStopCause.turnBudget,
      );
      expect(plan.stopNotice, 'chat.goal_auto_continue_budget_reached');
      expect(plan.trackerDelta.markBudgetNoticePresented, isTrue);
      expect(plan.trackerDelta.noProgressStreak, isNull);
    });

    test('uses the same notice for exhausted goal tokens', () {
      final plan = _coordinator.coordinate(
        _input(
          conversation: _conversation(
            goal: _goal(tokenBudget: 50, tokenUsage: 50),
          ),
        ),
      );

      expect(
        plan.policyDecision.stopCause,
        GoalAutoContinueStopCause.goalBudget,
      );
      expect(plan.stopNotice, 'chat.goal_auto_continue_budget_reached');
    });

    test('suppresses an already-presented stop notice', () {
      final plan = _coordinator.coordinate(
        _input(
          conversation: _conversation(goal: _goal(turnsUsed: 10)),
          tracker: _tracker(budgetNoticePresented: true),
        ),
      );

      expect(plan.stopNotice, isNull);
      expect(plan.trackerDelta.markBudgetNoticePresented, isFalse);
    });

    test('returns no effective budget when the owner has no goal', () {
      final plan = _coordinator.coordinate(
        _input(conversation: _conversation(includeGoal: false)),
      );

      expect(plan.policyDecision.reason, 'goal is not active');
      expect(plan.effectiveTurnBudget, isNull);
      expect(plan.stopNotice, isNull);
      expect(
        plan.reason.code,
        GoalAutoContinueCoordinationReasonCode.policySkip,
      );
    });

    test('preserves safe-boundary skip without advancing progress', () {
      final plan = _coordinator.coordinate(
        _input(
          tracker: _tracker(noProgressStreak: 3),
          safeBoundary: _safeBoundary(hasQueuedUserInput: true),
        ),
      );

      expect(plan.policyDecision.reason, 'queued user input is waiting');
      expect(plan.trackerDelta.noProgressStreak, isNull);
      expect(plan.trackerDelta.pendingPostRepairReplayOutcome, isFalse);
      expect(plan.trackerDelta.pendingRepairContractOutcome, isFalse);
    });

    test('preserves the safe-boundary veto order', () {
      final plan = _coordinator.coordinate(
        _input(
          safeBoundary: _safeBoundary(
            isLoading: true,
            hasQueuedUserInput: true,
            hasPendingAskUserQuestion: true,
            hasError: true,
          ),
        ),
      );

      expect(plan.policyDecision.reason, 'response still loading');
      expect(plan.reason.detail, 'response still loading');
    });

    test('returns a typed no-progress notice without blocking', () {
      final plan = _coordinator.coordinate(
        _input(
          tracker: _tracker(
            noProgressStreak: 1,
            previousEvidence: _incompleteEvidence,
          ),
        ),
      );

      expect(
        plan.policyDecision.stopCause,
        GoalAutoContinueStopCause.noProgress,
      );
      expect(plan.policyDecision.shouldBlock, isFalse);
      expect(plan.stopNotice, 'chat.goal_auto_continue_no_progress');
      expect(plan.trackerDelta.noProgressStreak, 2);
    });
  });

  group('repair and validation planning', () {
    test('builds a constrained repair contract with repair limits', () {
      final plan = _coordinator.coordinate(
        _input(
          tracker: _tracker(
            previousDiagnosticSignature: 'stable',
            verifierReplayCandidate: _verifierCandidate(),
          ),
          evidence: _diagnosticEvidence(count: 1, signature: 'stable'),
        ),
      );

      expect(plan.repairContract, contains('<repair_contract>'));
      expect(plan.capabilityProfile, GoalAutoContinueCapabilityProfile.repair);
      expect(plan.continuationLimits!.allowedToolNames, {
        'read_file',
        'write_file',
        'edit_file',
        'delete_file',
      });
      expect(
        plan.continuationLimits!.replayVerifierImmediatelyAfterMutation,
        isTrue,
      );
      expect(plan.continuationLimits!.verifierOnlyContinuation, isFalse);
      expect(plan.trackerDelta.pendingRepairContractOutcome, isTrue);
      expect(plan.trackerDelta.diagnosticRepairContinuationsDelta, 1);
    });

    test('does not build a repair contract without a replay candidate', () {
      final plan = _coordinator.coordinate(
        _input(
          tracker: _tracker(previousDiagnosticSignature: 'stable'),
          evidence: _diagnosticEvidence(count: 1, signature: 'stable'),
        ),
      );

      expect(plan.repairContract, isNull);
      expect(
        plan.capabilityProfile,
        GoalAutoContinueCapabilityProfile.unrestricted,
      );
      expect(
        plan.continuationLimits!.replayVerifierImmediatelyAfterMutation,
        isFalse,
      );
    });

    test('grants and records one no-mutation repair retry', () {
      final plan = _coordinator.coordinate(
        _input(tracker: _tracker(pendingRepairContractOutcome: true)),
      );

      expect(plan.policyDecision.usesRepairNoMutationRetry, isTrue);
      expect(plan.trackerDelta.repairNoMutationRetryUsed, isTrue);
      expect(plan.trackerDelta.pendingRepairContractOutcome, isFalse);
    });

    test('blocks a second no-mutation repair outcome', () {
      final plan = _coordinator.coordinate(
        _input(
          tracker: _tracker(
            pendingRepairContractOutcome: true,
            repairNoMutationRetryUsed: true,
          ),
        ),
      );

      expect(plan.policyDecision.shouldBlock, isTrue);
      expect(plan.policyDecision.reason, contains('no mutation twice'));
      expect(plan.trackerDelta.removeTracker, isTrue);
    });

    test('returns validation-only limits and increments the miss count', () {
      const evidence = ToolResultCompletionEvidence(
        mutatedWithoutExecutionVerification: true,
        unverifiedChangePaths: ['lib/main.dart'],
      );
      final plan = _coordinator.coordinate(_input(evidence: evidence));

      expect(
        plan.capabilityProfile,
        GoalAutoContinueCapabilityProfile.validation,
      );
      expect(plan.continuationLimits!.allowedToolNames, {
        'local_execute_command',
        'run_tests',
      });
      expect(plan.continuationLimits!.verifierOnlyContinuation, isTrue);
      expect(plan.trackerDelta.consecutiveValidationMisses, 1);
    });

    test('blocks an ignored validation continuation', () {
      const evidence = ToolResultCompletionEvidence(
        mutatedWithoutExecutionVerification: true,
        unverifiedChangePaths: ['lib/main.dart'],
      );
      final plan = _coordinator.coordinate(
        _input(
          tracker: _tracker(consecutiveValidationMisses: 1),
          evidence: evidence,
        ),
      );

      expect(plan.policyDecision.shouldBlock, isTrue);
      expect(plan.policyDecision.reason, 'validation continuation was ignored');
      expect(plan.trackerDelta.consecutiveValidationMisses, isNull);
    });

    test('resets validation state from current verification evidence', () {
      const evidence = ToolResultCompletionEvidence(
        boundedToolLoopExhausted: true,
        hasExecutionVerification: true,
        hasSuccessfulExecutionVerification: true,
      );
      final plan = _coordinator.coordinate(
        _input(
          tracker: _tracker(
            consecutiveValidationMisses: 4,
            failedVerificationObserved: true,
          ),
          evidence: evidence,
        ),
      );

      expect(plan.policyInput!.consecutiveValidationMisses, 0);
      expect(plan.policyInput!.failedVerificationObserved, isFalse);
      expect(plan.trackerDelta.consecutiveValidationMisses, 0);
      expect(plan.trackerDelta.failedVerificationObserved, isFalse);
    });

    test('records a failed verification before a validation retry', () {
      const evidence = ToolResultCompletionEvidence(
        mutatedWithoutExecutionVerification: true,
        hasExecutionVerification: true,
        hasSuccessfulExecutionVerification: false,
      );
      final plan = _coordinator.coordinate(
        _input(
          tracker: _tracker(consecutiveValidationMisses: 5),
          evidence: evidence,
        ),
      );

      expect(plan.policyInput!.consecutiveValidationMisses, 0);
      expect(plan.policyInput!.failedVerificationObserved, isTrue);
      expect(plan.trackerDelta.consecutiveValidationMisses, 1);
      expect(plan.trackerDelta.failedVerificationObserved, isTrue);
    });
  });

  group('completion elicitation', () {
    test('spends one elicitation at the current mutation generation', () {
      final plan = _coordinator.coordinate(
        _input(evidence: const ToolResultCompletionEvidence()),
      );

      expect(plan.policyDecision.noRemainingWork, isTrue);
      expect(
        plan.elicitationEligibility,
        GoalCompletionElicitationEligibility.eligible,
      );
      expect(plan.trackerDelta.completionElicitationMutationGeneration, 1);
      expect(plan.shouldMarkAwaitingConfirmation, isFalse);
    });

    test('marks awaiting confirmation when no work was produced', () {
      final plan = _coordinator.coordinate(
        _input(
          conversation: _conversation(
            mutationGeneration: 0,
            verificationGeneration: 0,
          ),
          evidence: const ToolResultCompletionEvidence(),
        ),
      );

      expect(
        plan.elicitationEligibility,
        GoalCompletionElicitationEligibility.noProducedWork,
      );
      expect(plan.shouldMarkAwaitingConfirmation, isTrue);
      expect(plan.trackerDelta.completionElicitationMutationGeneration, isNull);
    });

    test('does not repeat elicitation for the same mutation generation', () {
      final plan = _coordinator.coordinate(
        _input(
          tracker: _tracker(completionElicitationMutationGeneration: 2),
          conversation: _conversation(
            mutationGeneration: 2,
            verificationGeneration: 2,
          ),
          evidence: const ToolResultCompletionEvidence(),
        ),
      );

      expect(
        plan.elicitationEligibility,
        GoalCompletionElicitationEligibility.alreadySpentForMutation,
      );
      expect(plan.shouldMarkAwaitingConfirmation, isTrue);
    });

    test('does not re-elicitate an awaiting-confirmation goal', () {
      final plan = _coordinator.coordinate(
        _input(
          conversation: _conversation(
            goal: _goal(status: ConversationGoalStatus.awaitingConfirmation),
          ),
          evidence: const ToolResultCompletionEvidence(),
        ),
      );

      expect(
        plan.elicitationEligibility,
        GoalCompletionElicitationEligibility.goalStatusNotActive,
      );
      expect(plan.shouldMarkAwaitingConfirmation, isFalse);
    });

    test('keeps elicitation inapplicable for ordinary continuation', () {
      final plan = _coordinator.coordinate(_input());

      expect(
        plan.elicitationEligibility,
        GoalCompletionElicitationEligibility.notApplicable,
      );
    });
  });

  test('two owner snapshots cannot poison each other', () {
    final ownerConversation = _conversation(
      id: 'detached-owner',
      goal: _goal(turnBudget: 6),
      mutationGeneration: 4,
      verificationGeneration: 4,
    );
    final visibleConversation = _conversation(
      id: 'visible-peer',
      workspaceMode: WorkspaceMode.chat,
      goal: _goal(enabled: false, autoContinue: false),
      mutationGeneration: 99,
      verificationGeneration: -1,
    );
    final visibleBoundary = _safeBoundary(
      isLoading: true,
      hasQueuedUserInput: true,
      hasPendingAskUserQuestion: true,
    );
    final visibleEvidence = _diagnosticEvidence(
      count: 99,
      signature: 'peer-diagnostic',
    );

    final ownerPlan = _coordinator.coordinate(
      _input(
        owner: _owner('detached-owner', generation: 8),
        conversation: ownerConversation,
        tracker: _tracker(),
        evidence: _incompleteEvidence,
        safeBoundary: _safeBoundary(),
      ),
    );
    final visiblePlan = _coordinator.coordinate(
      _input(
        owner: _owner('visible-peer', generation: 99),
        conversation: visibleConversation,
        tracker: _tracker(noProgressStreak: 9, consecutiveValidationMisses: 9),
        evidence: visibleEvidence,
        safeBoundary: visibleBoundary,
        isVoiceMode: true,
      ),
    );
    final mismatchedPlan = _coordinator.coordinate(
      _input(
        owner: _owner('detached-owner', generation: 8),
        conversation: visibleConversation,
        evidence: visibleEvidence,
        safeBoundary: visibleBoundary,
      ),
    );

    expect(ownerPlan.policyDecision.shouldContinue, isTrue);
    expect(ownerPlan.effectiveTurnBudget, 6);
    expect(ownerPlan.continuationLimits!.effectiveTurnBudget, 6);
    expect(ownerPlan.policyInput!.safeBoundary.isSafe, isTrue);
    expect(ownerPlan.policyInput!.evidence.unresolvedErrorCount, 0);
    expect(
      ownerPlan.policyInput!.verificationCadence,
      VerificationCadence.notDue,
    );
    expect(
      visiblePlan.reason.code,
      GoalAutoContinueCoordinationReasonCode.nonCodingWorkspace,
    );
    expect(
      mismatchedPlan.reason.code,
      GoalAutoContinueCoordinationReasonCode.ownerConversationMismatch,
    );
    expect(mismatchedPlan.policyInput, isNull);
    expect(mismatchedPlan.effectiveTurnBudget, isNull);
  });

  test('returns deltas without mutating captured tracker and evidence', () {
    final unexecutedToolNames = <String>['run_tests'];
    final evidence = ToolResultCompletionEvidence(
      boundedToolLoopExhausted: true,
      unexecutedToolNames: unexecutedToolNames,
    );
    final tracker = _tracker(
      pendingPostRepairReplayOutcome: true,
      pendingRepairContractOutcome: true,
    );

    final plan = _coordinator.coordinate(
      _input(tracker: tracker, evidence: evidence),
    );

    expect(tracker.pendingPostRepairReplayOutcome, isTrue);
    expect(tracker.pendingRepairContractOutcome, isTrue);
    expect(evidence.unexecutedToolNames, ['run_tests']);
    expect(plan.trackerDelta.pendingPostRepairReplayOutcome, isFalse);
    expect(plan.trackerDelta.pendingRepairContractOutcome, isFalse);
  });
}

Matcher _emptyDeltaMatcher() {
  return isA<GoalAutoContinueTrackerDelta>()
      .having(
        (delta) => delta.consecutiveAutoContinuationsDelta,
        'consecutiveAutoContinuationsDelta',
        0,
      )
      .having(
        (delta) => delta.diagnosticRepairContinuationsDelta,
        'diagnosticRepairContinuationsDelta',
        0,
      )
      .having(
        (delta) => delta.pendingPostRepairReplayOutcome,
        'pendingPostRepairReplayOutcome',
        isNull,
      )
      .having(
        (delta) => delta.pendingRepairContractOutcome,
        'pendingRepairContractOutcome',
        isNull,
      )
      .having(
        (delta) => delta.markBudgetNoticePresented,
        'markBudgetNoticePresented',
        isFalse,
      )
      .having((delta) => delta.removeTracker, 'removeTracker', isFalse);
}
