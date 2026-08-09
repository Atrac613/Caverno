import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/services/conversation_goal_auto_continue_policy.dart';
import 'package:caverno/features/chat/domain/services/execution_snapshot_projector.dart';
import 'package:caverno/features/chat/domain/services/goal_auto_continue_prompt_builder.dart';
import 'package:caverno/features/chat/domain/services/tool_result_prompt_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
