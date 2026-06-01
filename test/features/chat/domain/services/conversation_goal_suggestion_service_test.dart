import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/services/conversation_goal_suggestion_service.dart';

void main() {
  test('parses a suggested objective from fenced JSON', () {
    final suggestion = ConversationGoalSuggestionService.parse('''
```json
{"status":"suggested","objective":"Move coding goal controls into the composer","question":""}
```
''');

    expect(suggestion, isNotNull);
    expect(suggestion!.kind, ConversationGoalSuggestionKind.suggested);
    expect(suggestion.objective, 'Move coding goal controls into the composer');
  });

  test('parses a clarification question when the goal is ambiguous', () {
    final suggestion = ConversationGoalSuggestionService.parse(
      '{"status":"needs_clarification","objective":"","question":"Which coding outcome should stay in focus?"}',
    );

    expect(suggestion, isNotNull);
    expect(suggestion!.kind, ConversationGoalSuggestionKind.needsClarification);
    expect(suggestion.question, 'Which coding outcome should stay in focus?');
  });

  test('detects useful context from user messages or saved workflow goals', () {
    final now = DateTime(2026);
    final empty = Conversation(
      id: 'empty',
      title: 'New Conversation',
      messages: const [],
      createdAt: now,
      updatedAt: now,
    );
    final withUserMessage = empty.copyWith(
      messages: [
        Message(
          id: 'message-1',
          role: MessageRole.user,
          content: 'Move the goal UI into the composer.',
          timestamp: now,
        ),
      ],
    );
    final withWorkflowGoal = empty.copyWith(
      workflowSpec: const ConversationWorkflowSpec(
        goal: 'Ship an inline coding goal composer flow',
      ),
    );

    expect(ConversationGoalSuggestionService.hasUsefulContext(empty), isFalse);
    expect(
      ConversationGoalSuggestionService.hasUsefulContext(withUserMessage),
      isTrue,
    );
    expect(
      ConversationGoalSuggestionService.hasUsefulContext(withWorkflowGoal),
      isTrue,
    );
    expect(
      ConversationGoalSuggestionService.hasUsefulContext(
        empty,
        pendingUserMessage: 'Set up the composer goal flow.',
      ),
      isTrue,
    );
    expect(
      ConversationGoalSuggestionService.hasUsefulContext(
        empty,
        clarificationAnswer: 'Keep the weather report task in focus.',
      ),
      isTrue,
    );
    expect(
      ConversationGoalSuggestionService.hasUsefulContext(
        empty,
        clarificationQuestion: 'Which coding outcome should stay in focus?',
      ),
      isTrue,
    );
  });

  test('builds a compact prompt from recent thread context', () {
    final now = DateTime(2026);
    final conversation = Conversation(
      id: 'thread-1',
      title: 'Composer goal flow',
      messages: [
        Message(
          id: 'message-1',
          role: MessageRole.user,
          content: 'I want the goal toggle in the composer.',
          timestamp: now,
        ),
        Message(
          id: 'message-2',
          role: MessageRole.assistant,
          content: 'I moved the visible controls into MessageInput.',
          timestamp: now,
        ),
      ],
      createdAt: now,
      updatedAt: now,
      workflowSpec: const ConversationWorkflowSpec(
        goal: 'Refine coding goal setup',
        acceptanceCriteria: ['Switch-on can prefill an editable goal'],
      ),
    );

    final messages = ConversationGoalSuggestionService.buildMessages(
      conversation: conversation,
      languageCode: 'en',
      now: now,
    );

    expect(messages, hasLength(2));
    expect(messages.first.role, MessageRole.system);
    expect(messages.last.content, contains('Preferred response language code'));
    expect(messages.last.content, contains('Refine coding goal setup'));
    expect(messages.last.content, contains('I want the goal toggle'));
  });

  test('includes pending user message in the suggestion prompt', () {
    final now = DateTime(2026);
    final conversation = Conversation(
      id: 'thread-1',
      title: 'New coding thread',
      messages: const [],
      createdAt: now,
      updatedAt: now,
    );

    final messages = ConversationGoalSuggestionService.buildMessages(
      conversation: conversation,
      languageCode: 'en',
      pendingUserMessage: 'Move goal setup forward after send.',
      now: now,
    );

    expect(messages.last.content, contains('user (pending send)'));
    expect(
      messages.last.content,
      contains('Move goal setup forward after send.'),
    );
  });

  test('includes user clarification in the suggestion prompt', () {
    final now = DateTime(2026);
    final conversation = Conversation(
      id: 'thread-1',
      title: 'New coding thread',
      messages: const [],
      createdAt: now,
      updatedAt: now,
    );

    final messages = ConversationGoalSuggestionService.buildMessages(
      conversation: conversation,
      languageCode: 'en',
      pendingUserMessage: 'Check Tokyo weather and save Markdown.',
      clarificationQuestion: 'Should this create a Markdown report file?',
      clarificationAnswer: 'Create a Markdown weather report file.',
      now: now,
    );

    expect(
      messages.last.content,
      contains('Goal clarification question asked'),
    );
    expect(
      messages.last.content,
      contains('Should this create a Markdown report file?'),
    );
    expect(
      messages.last.content,
      contains('User clarification answer for the goal'),
    );
    expect(
      messages.last.content,
      contains('Create a Markdown weather report file.'),
    );
  });

  test('keeps clarification questions focused on the goal', () {
    expect(
      ConversationGoalSuggestionService.systemPrompt,
      contains('Clarification questions must stay at goal level'),
    );
    expect(
      ConversationGoalSuggestionService.systemPrompt,
      contains('not which API, file name, storage path'),
    );
    expect(
      ConversationGoalSuggestionService.systemPrompt,
      contains('leave implementation choices for execution'),
    );
    expect(
      ConversationGoalSuggestionService.systemPrompt,
      contains('do not ask whether the user wants code or a script'),
    );
  });
}
