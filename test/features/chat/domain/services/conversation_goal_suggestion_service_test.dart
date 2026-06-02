import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/services/conversation_goal_suggestion_service.dart';

const _japaneseMarkdownWeatherRequest =
    '\u6771\u4eac\u306e\u660e\u65e5\u306e\u5929\u6c17\u3092\u8abf\u3079\u3066\u30de\u30fc\u30af\u30c0\u30a6\u30f3\u5f62\u5f0f\u3067\u4fdd\u5b58\u3092';
const _japaneseMarkdownWeatherGoal =
    '\u6771\u4eac\u306e\u660e\u65e5\u306e\u5929\u6c17\u3092\u8abf\u3079\u3066\u30de\u30fc\u30af\u30c0\u30a6\u30f3\u5f62\u5f0f\u3067\u4fdd\u5b58\u3059\u308b';
const _japaneseScriptClarification =
    '\u5929\u6c17\u60c5\u5831\u3092\u53d6\u5f97\u3057\u3066Markdown\u30d5\u30a1\u30a4\u30eb\u306b\u4fdd\u5b58\u3059\u308b\u30b9\u30af\u30ea\u30d7\u30c8\u3092\u4f5c\u6210\u3059\u308b\u306e\u3067\u3057\u3087\u3046\u304b\uff1f';

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

  test('preserves saved Markdown report requests in the suggestion prompt', () {
    final now = DateTime(2026, 6, 1);
    final conversation = Conversation(
      id: 'thread-1',
      title: 'New coding thread',
      messages: const [],
      createdAt: now,
      updatedAt: now,
    );

    final messages = ConversationGoalSuggestionService.buildMessages(
      conversation: conversation,
      languageCode: 'ja',
      pendingUserMessage:
          'Check tomorrow weather in Tokyo and save it as Markdown.',
      now: now,
    );

    expect(
      ConversationGoalSuggestionService.systemPrompt,
      contains('Preserve the requested outcome and artifact type'),
    );
    expect(
      ConversationGoalSuggestionService.systemPrompt,
      contains('For a saved Markdown report request'),
    );
    expect(
      ConversationGoalSuggestionService.systemPrompt,
      contains('not to create a script that generates it'),
    );
    expect(
      ConversationGoalSuggestionService.systemPrompt,
      contains('artifact types'),
    );
    expect(
      ConversationGoalSuggestionService.systemPrompt,
      contains(_japaneseMarkdownWeatherRequest),
    );
    expect(
      messages.last.content,
      contains('Check tomorrow weather in Tokyo and save it as Markdown.'),
    );
  });

  test(
    'validates Japanese Markdown save requests against script clarification',
    () {
      final now = DateTime(2026, 6, 1);
      final conversation = Conversation(
        id: 'thread-1',
        title: 'New coding thread',
        messages: const [],
        createdAt: now,
        updatedAt: now,
      );

      final validated = ConversationGoalSuggestionService.validateSuggestion(
        suggestion: const ConversationGoalSuggestion.needsClarification(
          _japaneseScriptClarification,
        ),
        conversation: conversation,
        pendingUserMessage: _japaneseMarkdownWeatherRequest,
      );

      expect(validated.kind, ConversationGoalSuggestionKind.suggested);
      expect(validated.objective, _japaneseMarkdownWeatherGoal);
      expect(
        validated.objective,
        isNot(contains('\u30b9\u30af\u30ea\u30d7\u30c8')),
      );
    },
  );

  test('validates clear save requests against API detail clarification', () {
    final now = DateTime(2026, 6, 1);
    final conversation = Conversation(
      id: 'thread-1',
      title: 'New coding thread',
      messages: const [],
      createdAt: now,
      updatedAt: now,
    );

    final validated = ConversationGoalSuggestionService.validateSuggestion(
      suggestion: const ConversationGoalSuggestion.needsClarification(
        'Which weather API should be used?',
      ),
      conversation: conversation,
      pendingUserMessage:
          'Check tomorrow weather in Tokyo and save it as a Markdown report.',
    );

    expect(validated.kind, ConversationGoalSuggestionKind.suggested);
    expect(
      validated.objective,
      'Check tomorrow weather in Tokyo and save it as a Markdown report',
    );
  });

  test(
    'validates clear work-product requests against implementation drift',
    () {
      final now = DateTime(2026, 6, 1);
      final conversation = Conversation(
        id: 'thread-1',
        title: 'New coding thread',
        messages: const [],
        createdAt: now,
        updatedAt: now,
      );
      const cases = [
        (
          request: 'Save the query results as a CSV file.',
          question: 'Which script should generate the CSV file?',
          objective: 'Save the query results as a CSV file',
          forbiddenTerm: 'script',
        ),
        (
          request: 'Output the diagnostic summary as JSON.',
          question: 'Which package should serialize the JSON output?',
          objective: 'Output the diagnostic summary as JSON',
          forbiddenTerm: 'package',
        ),
        (
          request: 'Create a release report.',
          question: 'Should I build a helper app for the report?',
          objective: 'Create a release report',
          forbiddenTerm: 'helper app',
        ),
        (
          request: 'Update README.md with the new setup steps.',
          question: 'Which file path should I update?',
          objective: 'Update README.md with the new setup steps',
          forbiddenTerm: 'path',
        ),
      ];

      for (final testCase in cases) {
        final validated = ConversationGoalSuggestionService.validateSuggestion(
          suggestion: ConversationGoalSuggestion.needsClarification(
            testCase.question,
          ),
          conversation: conversation,
          pendingUserMessage: testCase.request,
        );

        expect(
          validated.kind,
          ConversationGoalSuggestionKind.suggested,
          reason: testCase.request,
        );
        expect(
          validated.objective,
          testCase.objective,
          reason: testCase.request,
        );
        expect(
          validated.objective!.toLowerCase(),
          isNot(contains(testCase.forbiddenTerm)),
          reason: testCase.request,
        );
      }
    },
  );

  test('keeps explicit implementation artifacts in work-product requests', () {
    final now = DateTime(2026, 6, 1);
    final conversation = Conversation(
      id: 'thread-1',
      title: 'New coding thread',
      messages: const [],
      createdAt: now,
      updatedAt: now,
    );

    final validated = ConversationGoalSuggestionService.validateSuggestion(
      suggestion: const ConversationGoalSuggestion.suggested(
        'Create a Python script that exports query results as CSV',
      ),
      conversation: conversation,
      pendingUserMessage:
          'Create a Python script that exports query results as CSV.',
    );

    expect(validated.kind, ConversationGoalSuggestionKind.suggested);
    expect(validated.objective!.toLowerCase(), contains('script'));
  });

  test(
    'validates suggested objectives that invent implementation artifacts',
    () {
      final now = DateTime(2026, 6, 1);
      final conversation = Conversation(
        id: 'thread-1',
        title: 'New coding thread',
        messages: const [],
        createdAt: now,
        updatedAt: now,
      );

      final validated = ConversationGoalSuggestionService.validateSuggestion(
        suggestion: const ConversationGoalSuggestion.suggested(
          'Create a Python script that saves Tokyo weather as Markdown',
        ),
        conversation: conversation,
        pendingUserMessage:
            'Check tomorrow weather in Tokyo and save it as a Markdown report.',
      );

      expect(validated.kind, ConversationGoalSuggestionKind.suggested);
      expect(
        validated.objective,
        'Check tomorrow weather in Tokyo and save it as a Markdown report',
      );
      expect(validated.objective!.toLowerCase(), isNot(contains('script')));
    },
  );

  test('ignores implementation artifact terms inside word fragments', () {
    final now = DateTime(2026, 6, 1);
    final conversation = Conversation(
      id: 'thread-1',
      title: 'New coding thread',
      messages: const [],
      createdAt: now,
      updatedAt: now,
    );

    final validated = ConversationGoalSuggestionService.validateSuggestion(
      suggestion: const ConversationGoalSuggestion.suggested(
        'Check tomorrow weather in Tokyo and save it as an appropriate Markdown report',
      ),
      conversation: conversation,
      pendingUserMessage:
          'Check tomorrow weather in Tokyo and save it as a Markdown report.',
    );

    expect(validated.kind, ConversationGoalSuggestionKind.suggested);
    expect(
      validated.objective,
      'Check tomorrow weather in Tokyo and save it as an appropriate Markdown report',
    );
  });

  test(
    'keeps clarification when the request does not imply a clear outcome',
    () {
      final now = DateTime(2026, 6, 1);
      final conversation = Conversation(
        id: 'thread-1',
        title: 'New coding thread',
        messages: const [],
        createdAt: now,
        updatedAt: now,
      );

      final validated = ConversationGoalSuggestionService.validateSuggestion(
        suggestion: const ConversationGoalSuggestion.needsClarification(
          'Which coding outcome should stay in focus?',
        ),
        conversation: conversation,
        pendingUserMessage: 'Please help with this.',
      );

      expect(validated.kind, ConversationGoalSuggestionKind.needsClarification);
    },
  );

  test('keeps explicitly requested script objectives', () {
    final now = DateTime(2026, 6, 1);
    final conversation = Conversation(
      id: 'thread-1',
      title: 'New coding thread',
      messages: const [],
      createdAt: now,
      updatedAt: now,
    );

    final validated = ConversationGoalSuggestionService.validateSuggestion(
      suggestion: const ConversationGoalSuggestion.suggested(
        'Create a Python script that saves Tokyo weather as Markdown',
      ),
      conversation: conversation,
      pendingUserMessage:
          'Create a Python script that checks Tokyo weather and saves Markdown.',
    );

    expect(validated.kind, ConversationGoalSuggestionKind.suggested);
    expect(validated.objective!.toLowerCase(), contains('script'));
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
