part of 'chat_domain_services_test.dart';

void _runGoalAutoContinuePromptBuilder() {
  test('quotes the selected plan step in the continuation nudge', () {
    final prompt = GoalAutoContinuePromptBuilder.build(
      goal: _goal(),
      evidence: const ToolResultCompletionEvidence(unresolvedErrorCount: 1),
      executionSnapshot: _snapshot(),
      repairContract: null,
      repairNoMutationRetry: false,
      capabilityProfile: GoalAutoContinueCapabilityProfile.unrestricted,
      nextTurnNumber: 2,
      effectiveTurnBudget: 5,
      languageCode: 'en',
      planMarkdown: '## Task checklist\n- [ ] Implement the parser',
    );

    expect(prompt, contains('Immediate next step from the plan:'));
    expect(prompt, contains('Implement the parser'));
  });

  test('preserves the generic continuation fallback without a plan step', () {
    final prompt = GoalAutoContinuePromptBuilder.build(
      goal: _goal(),
      evidence: const ToolResultCompletionEvidence(unresolvedErrorCount: 1),
      executionSnapshot: _snapshot(),
      repairContract: null,
      repairNoMutationRetry: false,
      capabilityProfile: GoalAutoContinueCapabilityProfile.unrestricted,
      nextTurnNumber: 2,
      effectiveTurnBudget: 5,
      languageCode: 'en',
    );

    expect(prompt, isNot(contains('Immediate next step from the plan:')));
    expect(prompt, contains('Continue the work now.'));
  });
}

ConversationGoal _goal() => ConversationGoal(
  id: 'goal-1',
  objective: 'Implement the feature',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

ExecutionSnapshot _snapshot() => const ExecutionSnapshot(
  contractHash: '',
  workflowStage: ConversationWorkflowStage.implement,
  action: ExecutionSnapshotAction.execute,
  activeTaskId: null,
  activeTaskStatus: null,
  validationStatus: ConversationExecutionValidationStatus.unknown,
  completedTaskCount: 0,
  remainingTaskCount: 0,
  unresolvedQuestionCount: 0,
  requiresValidation: false,
  latestDiagnostic: null,
);
