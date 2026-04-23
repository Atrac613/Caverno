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

  test('retries approval when the button is still visible and no progress started', () {
    final conversation = buildConversation();

    expect(
      shouldRetryPlanApprovalTap(
        conversation: conversation,
        isLoading: false,
        approvalVisible: true,
      ),
      isTrue,
    );
  });

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

  test('recovers approval from the execution document when projected tasks are empty', () {
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
  });

  test('ignores phantom decision confirmations without pending decision state', () {
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
}
