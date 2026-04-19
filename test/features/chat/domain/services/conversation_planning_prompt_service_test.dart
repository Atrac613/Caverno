import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/services/conversation_planning_prompt_service.dart';

void main() {
  test('workflow proposal prompt includes execution and open question state', () {
    final conversation = Conversation(
      id: 'conversation-1',
      title: 'Plan thread',
      messages: const [],
      createdAt: DateTime(2026, 4, 18, 10),
      updatedAt: DateTime(2026, 4, 18, 10, 5),
      workflowStage: ConversationWorkflowStage.implement,
      workflowSpec: const ConversationWorkflowSpec(
        goal: 'Ship the markdown-first task runner',
        openQuestions: ['Should blocked tasks force a replan immediately?'],
        tasks: [
          ConversationWorkflowTask(
            id: 'task-1',
            title: 'Refresh the approved projection',
            status: ConversationWorkflowTaskStatus.blocked,
            validationCommand: 'flutter test',
          ),
        ],
      ),
      executionProgress: [
        ConversationExecutionTaskProgress(
          taskId: 'task-1',
          status: ConversationWorkflowTaskStatus.blocked,
          summary: 'Waiting on a failing smoke test',
          blockedReason: 'The smoke suite is still red',
          events: [
            ConversationExecutionTaskEvent(
              type: ConversationExecutionTaskEventType.blocked,
              createdAt: DateTime(2026, 4, 18, 10, 4),
              blockedReason: 'The smoke suite is still red',
            ),
          ],
        ),
      ],
      openQuestionProgress: [
        ConversationOpenQuestionProgress(
          questionId: Conversation.openQuestionIdFor(
            'Should blocked tasks force a replan immediately?',
          ),
          question: 'Should blocked tasks force a replan immediately?',
          status: ConversationOpenQuestionStatus.needsUserInput,
          note:
              'Yes. Trigger a narrow replan when the validation path stays red.',
        ),
      ],
    );

    final prompt =
        ConversationPlanningPromptService.buildWorkflowProposalRequest(
          currentConversation: conversation,
          messages: [
            Message(
              id: 'message-1',
              role: MessageRole.user,
              content: 'Please replan the blocked task.',
              timestamp: DateTime(2026, 4, 18, 10, 6),
            ),
          ],
          languageCode: 'en',
          additionalPlanningContext: 'Focus on the current blocker first.',
        );

    expect(prompt, contains('Execution progress:'));
    expect(prompt, contains('Waiting on a failing smoke test'));
    expect(prompt, contains('Open question progress:'));
    expect(
      prompt,
      contains(
        '[needsUserInput] Should blocked tasks force a replan immediately?',
      ),
    );
    expect(
      prompt,
      contains(
        'note: Yes. Trigger a narrow replan when the validation path stays red.',
      ),
    );
    expect(prompt, contains('Requested replan focus:'));
  });

  test('proposal transcript keeps only visible plain text content', () {
    final transcript =
        ConversationPlanningPromptService.buildProposalTranscript([
          Message(
            id: 'message-1',
            role: MessageRole.user,
            content: 'User request',
            timestamp: DateTime(2026, 4, 18, 11),
          ),
          Message(
            id: 'message-2',
            role: MessageRole.assistant,
            content: '<think>hidden</think>Visible answer',
            timestamp: DateTime(2026, 4, 18, 11, 1),
          ),
        ]);

    expect(transcript, contains('- user: User request'));
    expect(transcript, contains('- assistant: Visible answer'));
    expect(transcript, isNot(contains('hidden')));
  });

  test('task proposal prompt forbids research notes as task titles', () {
    final prompt = ConversationPlanningPromptService.buildTaskProposalRequest(
      currentConversation: Conversation(
        id: 'conversation-2',
        title: 'Plan thread',
        messages: const [],
        createdAt: DateTime(2026, 4, 19, 10),
        updatedAt: DateTime(2026, 4, 19, 10, 5),
        workflowStage: ConversationWorkflowStage.tasks,
        workflowSpec: const ConversationWorkflowSpec(
          goal: 'Build a ping CLI',
          constraints: ['Keep dependencies minimal'],
          acceptanceCriteria: ['The CLI can ping one or more hosts'],
        ),
      ),
      messages: [
        Message(
          id: 'message-3',
          role: MessageRole.user,
          content: 'Create a Python CLI that pings specific hosts.',
          timestamp: DateTime(2026, 4, 19, 10, 6),
        ),
      ],
      languageCode: 'en',
    );

    expect(
      prompt,
      contains(
        'Every task title must describe an action the agent can perform immediately.',
      ),
    );
    expect(
      prompt,
      contains(
        'Do not turn research notes, current-state observations, or repo summaries into task titles.',
      ),
    );
    expect(
      prompt,
      contains(
        'Order tasks by dependency so the first task can start immediately.',
      ),
    );
    expect(
      prompt,
      contains(
        'If the workspace is empty or nearly empty, put scaffolding or initial file creation before feature tasks.',
      ),
    );
  });
}
