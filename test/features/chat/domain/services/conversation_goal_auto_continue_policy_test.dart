import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:caverno/features/chat/domain/services/conversation_goal_auto_continue_policy.dart';
import 'package:caverno/features/chat/domain/services/tool_result_prompt_builder.dart';

void main() {
  const policy = ConversationGoalAutoContinuePolicy();

  test('continues active auto goals with incomplete evidence', () {
    final decision = policy.decide(_input());

    expect(decision.kind, GoalAutoContinueDecisionKind.continueTurn);
    expect(decision.nextTurnNumber, 2);
    expect(decision.effectiveTurnBudget, kGoalAutoContinueDefaultTurnBudget);
  });

  test('selects repair capabilities over pending validation', () {
    const evidence = ToolResultCompletionEvidence(
      boundedToolLoopExhausted: true,
      unexecutedToolNames: ['local_execute_command'],
      unresolvedErrorCount: 1,
      unresolvedErrorPaths: ['bin/todo_cli.dart'],
    );

    expect(
      policy.selectCapabilityProfile(
        evidence: evidence,
        hasRepairContract: true,
      ),
      GoalAutoContinueCapabilityProfile.repair,
    );
    expect(
      policy.selectCapabilityProfile(
        evidence: evidence,
        hasRepairContract: false,
      ),
      GoalAutoContinueCapabilityProfile.validation,
    );
  });

  test('skips when auto continue is disabled by default', () {
    final decision = policy.decide(_input(goal: _goal(autoContinue: false)));

    expect(decision.kind, GoalAutoContinueDecisionKind.skip);
    expect(decision.reason, 'auto-continue is disabled');
  });

  test('skips inactive completed or token-budget-exhausted goals', () {
    expect(
      policy
          .decide(_input(goal: _goal(status: ConversationGoalStatus.completed)))
          .reason,
      'goal is not active',
    );
    final decision = policy.decide(
      _input(goal: _goal(tokenBudget: 100, tokenUsage: 100)),
    );
    expect(decision.reason, 'goal budget is exhausted');
    expect(decision.stopCause, GoalAutoContinueStopCause.goalBudget);
  });

  test('skips at the effective auto continue budget', () {
    final decision = policy.decide(_input(goal: _goal(turnsUsed: 10)));

    expect(decision.kind, GoalAutoContinueDecisionKind.skip);
    expect(decision.reason, 'auto-continue turn budget reached');
    expect(decision.stopCause, GoalAutoContinueStopCause.turnBudget);
  });

  test('skips every unsafe boundary independently', () {
    final cases = <String, GoalAutoContinueSafeBoundary Function()>{
      'response still loading': () => _safeBoundary(isLoading: true),
      'queued user input is waiting': () =>
          _safeBoundary(hasQueuedUserInput: true),
      'SSH connection approval is pending': () =>
          _safeBoundary(hasPendingSshConnect: true),
      'SSH command approval is pending': () =>
          _safeBoundary(hasPendingSshCommand: true),
      'git command approval is pending': () =>
          _safeBoundary(hasPendingGitCommand: true),
      'local command approval is pending': () =>
          _safeBoundary(hasPendingLocalCommand: true),
      'computer-use approval is pending': () =>
          _safeBoundary(hasPendingComputerUseAction: true),
      'browser action approval is pending': () =>
          _safeBoundary(hasPendingBrowserAction: true),
      'file operation approval is pending': () =>
          _safeBoundary(hasPendingFileOperation: true),
      'BLE connection approval is pending': () =>
          _safeBoundary(hasPendingBleConnect: true),
      'serial port approval is pending': () =>
          _safeBoundary(hasPendingSerialOpen: true),
      'participant tool approval is pending': () =>
          _safeBoundary(hasPendingParticipantToolApproval: true),
      'assistant question is pending': () =>
          _safeBoundary(hasPendingAskUserQuestion: true),
      'workflow decision is pending': () =>
          _safeBoundary(hasPendingWorkflowDecision: true),
      'participant turn is active': () =>
          _safeBoundary(hasParticipantTurnRuntime: true),
      'chat state has an error': () => _safeBoundary(hasError: true),
    };

    for (final entry in cases.entries) {
      final decision = policy.decide(_input(safeBoundary: entry.value()));
      expect(decision.kind, GoalAutoContinueDecisionKind.skip);
      expect(decision.reason, entry.key);
    }
  });

  test('skips questions and turns with no incomplete evidence', () {
    expect(
      policy.decide(_input(finalAnswerEndsWithQuestion: true)).reason,
      'final answer asks a question',
    );
    expect(
      policy
          .decide(_input(evidence: const ToolResultCompletionEvidence()))
          .reason,
      'no incomplete evidence',
    );
  });

  test('continues from unverified file changes', () {
    final decision = policy.decide(
      _input(
        evidence: const ToolResultCompletionEvidence(
          unverifiedChangePaths: ['bin/todo_cli.dart'],
        ),
      ),
    );

    expect(decision.kind, GoalAutoContinueDecisionKind.continueTurn);
    expect(decision.reason, 'incomplete evidence remains');
  });

  test('continues after mutation without execution verification', () {
    final decision = policy.decide(
      _input(
        evidence: const ToolResultCompletionEvidence(
          mutatedWithoutExecutionVerification: true,
          unverifiedChangePaths: ['bin/todo_cli.dart'],
        ),
      ),
    );

    expect(decision.kind, GoalAutoContinueDecisionKind.continueTurn);
    expect(decision.reason, contains('validate file changes'));
  });

  test('blocks when the dedicated validation continuation is ignored', () {
    final decision = policy.decide(
      _input(
        evidence: const ToolResultCompletionEvidence(
          mutatedWithoutExecutionVerification: true,
          unverifiedChangePaths: ['bin/todo_cli.dart'],
        ),
        consecutiveValidationMisses: 1,
      ),
    );

    expect(decision.kind, GoalAutoContinueDecisionKind.stopAndBlock);
    expect(decision.reason, 'validation continuation was ignored');
  });

  test('retries one claimed validation action that was not executed', () {
    final decision = policy.decide(
      _input(
        evidence: const ToolResultCompletionEvidence(
          mutatedWithoutExecutionVerification: true,
          hasUnexecutedActionClaim: true,
        ),
        consecutiveValidationMisses: 1,
      ),
    );

    expect(decision.kind, GoalAutoContinueDecisionKind.continueTurn);
    expect(decision.reason, 'retry the unexecuted validation action');
  });

  test('validates one repair made after failed execution verification', () {
    final decision = policy.decide(
      _input(
        evidence: const ToolResultCompletionEvidence(
          hasExecutionVerification: true,
          mutatedWithoutExecutionVerification: true,
          unresolvedErrorCount: 1,
        ),
        consecutiveValidationMisses: 1,
      ),
    );

    expect(decision.kind, GoalAutoContinueDecisionKind.continueTurn);
    expect(
      decision.reason,
      'validate the repair made after failed verification',
    );
  });

  test('blocks a repeated post-verification repair without validation', () {
    final decision = policy.decide(
      _input(
        evidence: const ToolResultCompletionEvidence(
          hasExecutionVerification: true,
          mutatedWithoutExecutionVerification: true,
          unresolvedErrorCount: 1,
        ),
        consecutiveValidationMisses: 2,
        failedVerificationObserved: true,
      ),
    );

    expect(decision.kind, GoalAutoContinueDecisionKind.stopAndBlock);
    expect(decision.reason, 'post-verification repair was not revalidated');
    expect(decision.blockedReason, contains('not verified again'));
  });

  test('blocks after the unexecuted validation action retry is ignored', () {
    final decision = policy.decide(
      _input(
        evidence: const ToolResultCompletionEvidence(
          mutatedWithoutExecutionVerification: true,
          hasUnexecutedActionClaim: true,
        ),
        consecutiveValidationMisses: 2,
      ),
    );

    expect(decision.kind, GoalAutoContinueDecisionKind.stopAndBlock);
    expect(decision.reason, 'validation continuation was ignored');
  });

  test('prioritizes an unexecuted verifier over diagnostic stalling', () {
    final decision = policy.decide(
      _input(
        evidence: const ToolResultCompletionEvidence(
          boundedToolLoopExhausted: true,
          unexecutedToolNames: ['local_execute_command'],
          unresolvedErrorCount: 3,
        ),
        noProgressStreak: 2,
      ),
    );

    expect(decision.kind, GoalAutoContinueDecisionKind.continueTurn);
    expect(decision.reason, 'execute the pending verification call');
  });

  test('bounds repeated unexecuted verifier continuations', () {
    final decision = policy.decide(
      _input(
        evidence: const ToolResultCompletionEvidence(
          boundedToolLoopExhausted: true,
          unexecutedToolNames: ['local_execute_command'],
          unresolvedErrorCount: 3,
        ),
        consecutiveValidationMisses: 1,
      ),
    );

    expect(decision.kind, GoalAutoContinueDecisionKind.stopAndBlock);
    expect(decision.reason, 'validation continuation was ignored');
  });

  test('validation continuation still respects budgets and safety vetos', () {
    const evidence = ToolResultCompletionEvidence(
      mutatedWithoutExecutionVerification: true,
      unverifiedChangePaths: ['bin/todo_cli.dart'],
    );

    expect(
      policy
          .decide(
            _input(
              evidence: evidence,
              consecutiveAutoContinuations: 3,
              noProgressStreak: 2,
            ),
          )
          .kind,
      GoalAutoContinueDecisionKind.continueTurn,
    );
    expect(
      policy
          .decide(_input(goal: _goal(turnsUsed: 10), evidence: evidence))
          .stopCause,
      GoalAutoContinueStopCause.turnBudget,
    );
    expect(
      policy
          .decide(
            _input(
              safeBoundary: _safeBoundary(hasPendingLocalCommand: true),
              evidence: evidence,
            ),
          )
          .reason,
      'local command approval is pending',
    );
    expect(
      policy
          .decide(_input(evidence: evidence, finalAnswerEndsWithQuestion: true))
          .reason,
      'final answer asks a question',
    );
  });

  test('does not block after progress followed by one diagnostic plateau', () {
    final evidence = _evidence(count: 2, paths: const ['bin/todo_cli.dart']);
    final decision = policy.decide(
      _input(
        evidence: evidence,
        consecutiveAutoContinuations: 2,
        noProgressStreak: 1,
      ),
    );

    expect(decision.kind, GoalAutoContinueDecisionKind.continueTurn);
  });

  test('continues a stable diagnostic plateau despite a final question', () {
    final decision = policy.decide(
      _input(
        evidence: _evidence(count: 1, paths: const ['bin/todo_cli.dart']),
        identicalDiagnosticSignatureStreak: 1,
        finalAnswerEndsWithQuestion: true,
      ),
    );

    expect(decision.kind, GoalAutoContinueDecisionKind.continueTurn);
  });

  test('prioritizes the first stable diagnostic repair over no-progress', () {
    final decision = policy.decide(
      _input(
        evidence: _evidence(count: 1, paths: const ['bin/todo_cli.dart']),
        noProgressStreak: 2,
        identicalDiagnosticSignatureStreak: 1,
      ),
    );

    expect(decision.kind, GoalAutoContinueDecisionKind.continueTurn);
  });

  test('blocks after two consecutive diagnostic no-progress comparisons', () {
    final evidence = _evidence(count: 2, paths: const ['bin/todo_cli.dart']);
    final decision = policy.decide(
      _input(
        evidence: evidence,
        consecutiveAutoContinuations: 3,
        noProgressStreak: 2,
      ),
    );

    expect(decision.kind, GoalAutoContinueDecisionKind.stopAndBlock);
    expect(decision.blockedReason, contains('no diagnostic progress'));
  });

  test('blocks when diagnostic repair continuation budget is exhausted', () {
    final decision = policy.decide(
      _input(
        evidence: _evidence(count: 1, paths: const ['bin/todo_cli.dart']),
        consecutiveAutoContinuations: 2,
        diagnosticRepairContinuations: kGoalAutoContinueDiagnosticRepairBudget,
        noProgressStreak: 0,
      ),
    );

    expect(decision.kind, GoalAutoContinueDecisionKind.stopAndBlock);
    expect(decision.reason, contains('repair continuation budget'));
    expect(decision.blockedReason, contains('2 continued repair turns'));
  });

  test('grants one repair extension when diagnostics improve', () {
    final decision = policy.decide(
      _input(
        evidence: _evidence(count: 1, paths: const ['bin/todo_cli.dart']),
        diagnosticRepairContinuations: kGoalAutoContinueDiagnosticRepairBudget,
        diagnosticEvidenceImproved: true,
      ),
    );

    expect(decision.kind, GoalAutoContinueDecisionKind.continueTurn);
    expect(decision.usesDiagnosticRepairExtension, isTrue);
    expect(decision.reason, contains('one repair extension'));
  });

  test('does not grant a second improving repair extension', () {
    final decision = policy.decide(
      _input(
        evidence: _evidence(count: 1, paths: const ['bin/todo_cli.dart']),
        diagnosticRepairContinuations: kGoalAutoContinueDiagnosticRepairBudget,
        diagnosticRepairExtensionUsed: true,
        diagnosticEvidenceImproved: true,
      ),
    );

    expect(decision.kind, GoalAutoContinueDecisionKind.stopAndBlock);
    expect(decision.reason, contains('repair continuation budget'));
  });

  test('grants one extension when a post-repair verifier advances', () {
    final decision = policy.decide(
      _input(
        evidence: _evidence(count: 2, paths: const ['bin/todo_cli.dart']),
        diagnosticRepairContinuations: kGoalAutoContinueDiagnosticRepairBudget,
        noProgressStreak: 2,
        postRepairVerifierAdvanced: true,
      ),
    );

    expect(decision.kind, GoalAutoContinueDecisionKind.continueTurn);
    expect(decision.usesDiagnosticRepairExtension, isTrue);
    expect(decision.reason, contains('post-repair verifier advanced'));
  });

  test('does not grant a second post-repair verifier extension', () {
    final decision = policy.decide(
      _input(
        evidence: _evidence(count: 2, paths: const ['bin/todo_cli.dart']),
        diagnosticRepairContinuations: kGoalAutoContinueDiagnosticRepairBudget,
        diagnosticRepairExtensionUsed: true,
        noProgressStreak: 2,
        postRepairVerifierAdvanced: true,
      ),
    );

    expect(decision.kind, GoalAutoContinueDecisionKind.stopAndBlock);
    expect(decision.reason, contains('repair continuation budget'));
  });

  test('retries one repair contract that made no mutation', () {
    final decision = policy.decide(
      _input(
        evidence: const ToolResultCompletionEvidence(
          boundedToolLoopExhausted: true,
          unexecutedToolNames: ['local_execute_command'],
          unresolvedErrorCount: 1,
          unresolvedErrorPaths: ['bin/todo_cli.dart'],
          diagnosticSignature: 'stable-diagnostic',
        ),
        diagnosticRepairContinuations: kGoalAutoContinueDiagnosticRepairBudget,
        noProgressStreak: 2,
        identicalDiagnosticSignatureStreak: 2,
        repairContractProducedNoMutation: true,
      ),
    );

    expect(decision.kind, GoalAutoContinueDecisionKind.continueTurn);
    expect(decision.usesRepairNoMutationRetry, isTrue);
    expect(decision.reason, contains('one retry granted'));
  });

  test('blocks when a repair contract makes no mutation twice', () {
    final decision = policy.decide(
      _input(
        evidence: _evidence(count: 1, paths: const ['bin/todo_cli.dart']),
        diagnosticRepairContinuations: kGoalAutoContinueDiagnosticRepairBudget,
        noProgressStreak: 3,
        identicalDiagnosticSignatureStreak: 3,
        repairContractProducedNoMutation: true,
        repairNoMutationRetryUsed: true,
      ),
    );

    expect(decision.kind, GoalAutoContinueDecisionKind.stopAndBlock);
    expect(decision.reason, contains('no mutation twice'));
    expect(decision.blockedReason, contains('without a file mutation'));
  });

  test('allows the last diagnostic repair continuation in the budget', () {
    final decision = policy.decide(
      _input(
        evidence: _evidence(count: 1, paths: const ['bin/todo_cli.dart']),
        consecutiveAutoContinuations: 1,
        diagnosticRepairContinuations:
            kGoalAutoContinueDiagnosticRepairBudget - 1,
        noProgressStreak: 0,
      ),
    );

    expect(decision.kind, GoalAutoContinueDecisionKind.continueTurn);
  });

  test('skips but does not block when unverified-only evidence stalls', () {
    final decision = policy.decide(
      _input(
        evidence: const ToolResultCompletionEvidence(
          unverifiedChangePaths: ['README.md'],
        ),
        consecutiveAutoContinuations: 3,
        noProgressStreak: 2,
      ),
    );

    expect(decision.kind, GoalAutoContinueDecisionKind.skip);
    expect(decision.reason, 'no measurable progress');
    expect(decision.stopCause, GoalAutoContinueStopCause.noProgress);
  });

  test('skips but does not block when exhaustion-only evidence stalls', () {
    final evidence = const ToolResultCompletionEvidence(
      boundedToolLoopExhausted: true,
      unexecutedToolNames: ['read_file'],
    );
    final decision = policy.decide(
      _input(
        evidence: evidence,
        consecutiveAutoContinuations: 3,
        noProgressStreak: 2,
      ),
    );

    expect(decision.kind, GoalAutoContinueDecisionKind.skip);
    expect(decision.reason, 'no measurable progress');
    expect(decision.stopCause, GoalAutoContinueStopCause.noProgress);
  });

  test('treats diagnostic regression as no progress', () {
    final progress = _evidence(
      count: 3,
      paths: const ['bin/todo_cli.dart'],
    ).compareProgress(_evidence(count: 2, paths: const ['bin/todo_cli.dart']));

    expect(progress, GoalEvidenceProgress.noProgress);
  });

  test('continues when diagnostics improve', () {
    final decision = policy.decide(
      _input(
        evidence: _evidence(count: 1, paths: const ['bin/todo_cli.dart']),
        consecutiveAutoContinuations: 2,
        noProgressStreak: 0,
      ),
    );

    expect(decision.kind, GoalAutoContinueDecisionKind.continueTurn);
  });

  test('skips when edit and read-only evidence alternate without progress', () {
    const editEvidence = ToolResultCompletionEvidence(
      unverifiedChangePaths: ['README.md'],
    );
    const readEvidence = ToolResultCompletionEvidence(
      boundedToolLoopExhausted: true,
      unexecutedToolNames: ['read_file'],
    );
    var streak = 0;
    streak = _nextStreak(streak, readEvidence, editEvidence);
    streak = _nextStreak(streak, editEvidence, readEvidence);

    final decision = policy.decide(
      _input(
        evidence: editEvidence,
        consecutiveAutoContinuations: 3,
        noProgressStreak: streak,
      ),
    );

    expect(streak, 2);
    expect(decision.kind, GoalAutoContinueDecisionKind.skip);
    expect(decision.stopCause, GoalAutoContinueStopCause.noProgress);
  });

  test('resets no-progress streak when unverified edits move files', () {
    const firstEdit = ToolResultCompletionEvidence(
      unverifiedChangePaths: ['README.md'],
    );
    const secondEdit = ToolResultCompletionEvidence(
      unverifiedChangePaths: ['docs/README.md'],
    );
    final streak = _nextStreak(1, secondEdit, firstEdit);

    final decision = policy.decide(
      _input(
        evidence: secondEdit,
        consecutiveAutoContinuations: 2,
        noProgressStreak: streak,
      ),
    );

    expect(streak, 0);
    expect(decision.kind, GoalAutoContinueDecisionKind.continueTurn);
  });
}

GoalAutoContinuePolicyInput _input({
  ConversationGoal? goal,
  GoalAutoContinueSafeBoundary? safeBoundary,
  ToolResultCompletionEvidence? evidence,
  int consecutiveAutoContinuations = 0,
  int diagnosticRepairContinuations = 0,
  bool diagnosticRepairExtensionUsed = false,
  bool diagnosticEvidenceImproved = false,
  bool postRepairVerifierAdvanced = false,
  bool repairContractProducedNoMutation = false,
  bool repairNoMutationRetryUsed = false,
  int consecutiveValidationMisses = 0,
  bool failedVerificationObserved = false,
  int noProgressStreak = 0,
  int identicalDiagnosticSignatureStreak = 0,
  bool finalAnswerEndsWithQuestion = false,
}) {
  return GoalAutoContinuePolicyInput(
    goal: goal ?? _goal(),
    safeBoundary: safeBoundary ?? _safeBoundary(),
    evidence: evidence ?? _evidence(),
    consecutiveAutoContinuations: consecutiveAutoContinuations,
    diagnosticRepairContinuations: diagnosticRepairContinuations,
    diagnosticRepairExtensionUsed: diagnosticRepairExtensionUsed,
    diagnosticEvidenceImproved: diagnosticEvidenceImproved,
    postRepairVerifierAdvanced: postRepairVerifierAdvanced,
    repairContractProducedNoMutation: repairContractProducedNoMutation,
    repairNoMutationRetryUsed: repairNoMutationRetryUsed,
    consecutiveValidationMisses: consecutiveValidationMisses,
    failedVerificationObserved: failedVerificationObserved,
    noProgressStreak: noProgressStreak,
    identicalDiagnosticSignatureStreak: identicalDiagnosticSignatureStreak,
    finalAnswerEndsWithQuestion: finalAnswerEndsWithQuestion,
  );
}

ConversationGoal _goal({
  bool autoContinue = true,
  ConversationGoalStatus status = ConversationGoalStatus.active,
  int tokenBudget = 0,
  int tokenUsage = 0,
  int turnBudget = 0,
  int turnsUsed = 1,
}) {
  return ConversationGoal(
    id: 'goal-1',
    objective: 'Fix analyzer errors',
    enabled: true,
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

int _nextStreak(
  int currentStreak,
  ToolResultCompletionEvidence current,
  ToolResultCompletionEvidence previous,
) {
  return current.compareProgress(previous) == GoalEvidenceProgress.improved
      ? 0
      : currentStreak + 1;
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

ToolResultCompletionEvidence _evidence({
  int count = 2,
  List<String> paths = const ['bin/todo_cli.dart'],
}) {
  return ToolResultCompletionEvidence(
    unresolvedErrorCount: count,
    unresolvedErrorPaths: paths,
  );
}
