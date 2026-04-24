import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';

import '../../integration_test/test_support/plan_mode_scenario_spec.dart';

void main() {
  test('log expectation lower bounds require min and exact counts', () {
    const expectations = <PlanModeLogExpectation>[
      PlanModeLogExpectation(pattern: 'alpha', minCount: 2),
      PlanModeLogExpectation(pattern: 'beta', exactCount: 1),
      PlanModeLogExpectation(pattern: 'gamma', maxCount: 0),
    ];

    expect(
      planModeLogLowerBoundsSatisfied(const <String>[
        'alpha event',
        'beta event',
      ], expectations),
      isFalse,
    );
    expect(
      planModeLogLowerBoundsSatisfied(const <String>[
        'alpha event',
        'alpha again',
        'beta event',
      ], expectations),
      isTrue,
    );
  });

  test('normalizes live decision option labels', () {
    expect(
      normalizePlanModeDecisionOptionLabel('"CLI entry point"'),
      'cli entry point',
    );
    expect(
      normalizePlanModeDecisionOptionLabel('CLI Entry Point'),
      'cli entry point',
    );
  });

  test('keeps README live canary out of smoke tags', () {
    final scenario = buildLivePlanModeScenarios().firstWhere(
      (item) => item.name == 'live_readme_first_canary',
    );

    expect(scenario.tags, contains('canary'));
    expect(scenario.tags, isNot(contains('smoke')));
    expect(scenario.savedWorkflowExpectation, isNotNull);
    expect(scenario.savedWorkflowExpectation!.minTaskCount, 1);
    expect(
      scenario.savedWorkflowExpectation!.firstTaskTargetFilesContain,
      contains('README.md'),
    );
  });

  test(
    'batched_tool_calls emits both file writes in one tool-call turn',
    () async {
      final scenario = buildPlanModeScenarios().firstWhere(
        (item) => item.name == 'batched_tool_calls',
      );
      final dataSource = FakePlanModeChatDataSource(scenario);

      final streamResult = dataSource.streamChatCompletionWithTools(
        messages: [
          Message(
            id: 'prompt',
            content: 'Use the saved task "${scenario.initialTaskTitle}" now.',
            role: MessageRole.user,
            timestamp: DateTime(2026),
          ),
        ],
        tools: const <Map<String, dynamic>>[],
      );

      final completion = await streamResult.completion;

      expect(scenario.resolvedToolCallBatchSizes, const <int>[2]);
      expect(completion.toolCalls, isNotNull);
      expect(completion.toolCalls, hasLength(2));
      expect(
        completion.toolCalls!
            .map((toolCall) => toolCall.arguments['path'])
            .toList(),
        ['requirements.txt', 'README.md'],
      );

      final followUp = await dataSource.createChatCompletionWithToolResults(
        messages: const <Message>[],
        toolResults: completion.toolCalls!
            .map(
              (toolCall) => ToolResultInfo(
                id: toolCall.id,
                name: toolCall.name,
                arguments: toolCall.arguments,
                result: 'ok',
              ),
            )
            .toList(growable: false),
        assistantContent: '',
        tools: const <Map<String, dynamic>>[],
      );

      expect(followUp.finishReason, 'stop');
      expect(followUp.toolCalls, isNull);
    },
  );
}
