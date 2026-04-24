import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_plan_artifact.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';

import '../../integration_test/test_support/plan_mode_approval_progress.dart';

void main() {
  Conversation buildConversation({
    ConversationWorkflowStage workflowStage = ConversationWorkflowStage.tasks,
    List<ConversationWorkflowTask> tasks = const [],
  }) {
    return Conversation(
      id: 'conversation-1',
      title: 'Approval progress',
      messages: const [],
      createdAt: DateTime(2026, 4, 22, 21),
      updatedAt: DateTime(2026, 4, 22, 21),
      workflowStage: workflowStage,
      workflowSpec: ConversationWorkflowSpec(tasks: tasks),
    );
  }

  test('observes approval transition when execution starts loading', () {
    expect(
      planApprovalTransitionObserved(conversation: null, isLoading: true),
      isTrue,
    );
  });

  test('observes approval transition when projected tasks exist', () {
    final conversation = buildConversation(
      tasks: const [
        ConversationWorkflowTask(
          id: 'task-1',
          title: 'Initialize project files',
          status: ConversationWorkflowTaskStatus.inProgress,
        ),
      ],
    );

    expect(
      planApprovalTransitionObserved(
        conversation: conversation,
        isLoading: false,
      ),
      isTrue,
    );
  });

  test(
    'retries approval when the button is still visible and no progress started',
    () {
      final conversation = buildConversation();

      expect(
        shouldRetryPlanApprovalTap(
          conversation: conversation,
          isLoading: false,
          approvalVisible: true,
        ),
        isTrue,
      );
    },
  );

  test('does not retry approval after transition is already observed', () {
    final conversation = buildConversation(
      workflowStage: ConversationWorkflowStage.review,
    );

    expect(
      shouldRetryPlanApprovalTap(
        conversation: conversation,
        isLoading: false,
        approvalVisible: true,
      ),
      isFalse,
    );
  });

  test(
    'recovers approval from the execution document when projected tasks are empty',
    () {
      final conversation = buildConversation().copyWith(
        planArtifact: const ConversationPlanArtifact(
          approvedMarkdown:
              '# Plan\n'
              '\n'
              '## Stage\n'
              'implement\n'
              '\n'
              '## Goal\n'
              'Recover execution after approval\n'
              '\n'
              '## Tasks\n'
              '\n'
              '1. Implement ping_cli.py\n'
              '   - Status: inProgress\n',
        ),
      );

      expect(
        shouldRecoverPlanApprovalFromExecutionDocument(
          conversation: conversation,
          isLoading: false,
        ),
        isTrue,
      );
    },
  );

  test(
    'ignores phantom decision confirmations without pending decision state',
    () {
      expect(
        shouldHandlePlanningDecision(
          hasPendingDecision: false,
          confirmVisible: true,
        ),
        isFalse,
      );
      expect(
        shouldHandlePlanningDecision(
          hasPendingDecision: true,
          confirmVisible: true,
        ),
        isTrue,
      );
    },
  );

  test('waits for a pending decision sheet before handling it', () {
    expect(
      shouldWaitForPlanningDecisionSheet(
        hasPendingDecision: true,
        confirmVisible: false,
      ),
      isTrue,
    );
    expect(
      shouldWaitForPlanningDecisionSheet(
        hasPendingDecision: false,
        confirmVisible: false,
      ),
      isFalse,
    );
    expect(
      shouldWaitForPlanningDecisionSheet(
        hasPendingDecision: true,
        confirmVisible: true,
      ),
      isFalse,
    );
  });

  test('waits briefly before retrying a fresh approval tap', () {
    expect(
      shouldWaitForPlanApprovalToSettle(
        approvalTappedAt: DateTime(2026, 4, 23, 12, 0, 0),
        now: DateTime(2026, 4, 23, 12, 0, 1),
      ),
      isTrue,
    );
    expect(
      shouldWaitForPlanApprovalToSettle(
        approvalTappedAt: DateTime(2026, 4, 23, 12, 0, 0),
        now: DateTime(2026, 4, 23, 12, 0, 3),
      ),
      isFalse,
    );
  });

  test('detects whether a review artifact has preview tasks', () {
    final workflowOnly = buildConversation().copyWith(
      planArtifact: const ConversationPlanArtifact(
        draftMarkdown:
            '# Plan\n'
            '\n'
            '## Stage\n'
            'plan\n'
            '\n'
            '## Goal\n'
            'Create the project plan\n',
      ),
    );
    final withTasks = buildConversation().copyWith(
      planArtifact: const ConversationPlanArtifact(
        draftMarkdown:
            '# Plan\n'
            '\n'
            '## Stage\n'
            'plan\n'
            '\n'
            '## Goal\n'
            'Create the project plan\n'
            '\n'
            '## Tasks\n'
            '\n'
            '1. Create README.md\n'
            '   - Status: pending\n',
      ),
    );

    expect(
      planReviewArtifactHasPreviewTasks(conversation: workflowOnly),
      isFalse,
    );
    expect(planReviewArtifactHasPreviewTasks(conversation: withTasks), isTrue);
  });

  test(
    'treats execution as settled only after loading and approvals clear',
    () {
      expect(
        planModeExecutionIsSettled(
          isLoading: false,
          hasPendingApprovals: false,
        ),
        isTrue,
      );
      expect(
        planModeExecutionIsSettled(isLoading: true, hasPendingApprovals: false),
        isFalse,
      );
      expect(
        planModeExecutionIsSettled(isLoading: false, hasPendingApprovals: true),
        isFalse,
      );
    },
  );

  test('cancels leftover execution only for partial smoke scenarios', () {
    expect(
      shouldCancelBackgroundExecutionAfterSettleTimeout(
        waitForExecutionCompletion: false,
        settled: false,
      ),
      isTrue,
    );
    expect(
      shouldCancelBackgroundExecutionAfterSettleTimeout(
        waitForExecutionCompletion: true,
        settled: false,
      ),
      isFalse,
    );
    expect(
      shouldCancelBackgroundExecutionAfterSettleTimeout(
        waitForExecutionCompletion: false,
        settled: true,
      ),
      isFalse,
    );
  });

  test('uses a short post-scenario settle timeout for partial smoke', () {
    expect(
      resolvePostScenarioSettleTimeout(
        usesLiveLlm: true,
        waitForExecutionCompletion: false,
      ),
      const Duration(seconds: 5),
    );
    expect(
      resolvePostScenarioSettleTimeout(
        usesLiveLlm: false,
        waitForExecutionCompletion: false,
      ),
      const Duration(seconds: 5),
    );
    expect(
      resolvePostScenarioSettleTimeout(
        usesLiveLlm: true,
        waitForExecutionCompletion: true,
      ),
      const Duration(seconds: 60),
    );
  });
}
