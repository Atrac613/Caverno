import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/services/model_switch_handoff_brief_service.dart';

void main() {
  test('returns null when there is no continuity context', () {
    final brief = ModelSwitchHandoffBriefService.build(
      conversation: null,
      messages: const [],
      previousModel: 'old-model',
      nextModel: 'new-model',
    );

    expect(brief, isNull);
  });

  test('builds a model-agnostic brief with workflow target files', () {
    final brief = ModelSwitchHandoffBriefService.build(
      conversation: _conversation(
        workflowSpec: const ConversationWorkflowSpec(
          goal: 'Finish LL14 model handoff',
          tasks: [
            ConversationWorkflowTask(
              id: 'task-1',
              title: 'Add model switch handoff',
              status: ConversationWorkflowTaskStatus.inProgress,
              targetFiles: [
                'lib/features/chat/domain/services/model_switch_handoff_brief_service.dart',
              ],
              validationCommand:
                  'fvm flutter test test/features/chat/domain/services/model_switch_handoff_brief_service_test.dart',
            ),
          ],
        ),
      ),
      messages: [
        _message(
          role: MessageRole.user,
          content: 'Please continue LL14 after changing models.',
        ),
      ],
      previousModel: 'qwen-old',
      nextModel: 'glm-new',
    );

    expect(brief, isNotNull);
    expect(brief, contains('MODEL SWITCH HANDOFF BRIEF'));
    expect(brief, contains('Previous model: qwen-old'));
    expect(brief, contains('Next model: glm-new'));
    expect(
      brief,
      contains('Focus task: [inProgress] Add model switch handoff'),
    );
    expect(
      brief,
      contains(
        'lib/features/chat/domain/services/model_switch_handoff_brief_service.dart',
      ),
    );
    expect(brief, contains('Validation command: fvm flutter test'));
    expect(brief, contains('Please continue LL14 after changing models.'));
  });

  test('marks assistant claims as unverified side-effect context', () {
    final brief = ModelSwitchHandoffBriefService.build(
      conversation: _conversation(),
      messages: [
        _message(role: MessageRole.user, content: 'Create the file.'),
        _message(
          role: MessageRole.assistant,
          content:
              '<tool_call>{"name":"write_file"}</tool_call>\nI saved /tmp/report.md and ran validation.',
        ),
      ],
      previousModel: 'model-a',
      nextModel: 'model-b',
    );

    expect(brief, isNotNull);
    expect(
      brief,
      contains(
        'Do not treat this brief as proof that file writes, command runs',
      ),
    );
    expect(
      brief,
      contains(
        'Assistant (claims are unverified unless supported by retained tool results)',
      ),
    );
    expect(brief, isNot(contains('<tool_call>')));
    expect(brief, contains('I saved /tmp/report.md and ran validation.'));
  });
}

Conversation _conversation({ConversationWorkflowSpec? workflowSpec}) {
  final now = DateTime(2026, 6, 14);
  return Conversation(
    id: 'conversation-1',
    title: 'LL14 context surgery',
    messages: const [],
    createdAt: now,
    updatedAt: now,
    workflowStage: workflowSpec == null
        ? ConversationWorkflowStage.idle
        : ConversationWorkflowStage.implement,
    workflowSpec: workflowSpec,
    goal: ConversationGoal(
      id: 'goal-1',
      objective: 'Complete LL14 safely',
      createdAt: now,
      updatedAt: now,
    ),
  );
}

Message _message({required MessageRole role, required String content}) {
  return Message(
    id: '${role.name}-${content.hashCode}',
    content: content,
    role: role,
    timestamp: DateTime(2026, 6, 14),
  );
}
