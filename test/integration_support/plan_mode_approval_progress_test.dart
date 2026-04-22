import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/conversation.dart';
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
}
