import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';

import '../../integration_test/test_support/plan_mode_scenario_spec.dart';
import '../../integration_test/test_support/plan_mode_tool_loop_convergence.dart';

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
    expect(scenario.tags, contains('convergence'));
    expect(scenario.tags, isNot(contains('smoke')));
    expect(scenario.savedWorkflowExpectation, isNotNull);
    expect(scenario.savedWorkflowExpectation!.minTaskCount, 1);
    expect(
      scenario.savedWorkflowExpectation!.firstTaskTargetFilesContain,
      contains('README.md'),
    );
    expect(
      scenario.logExpectations.map((item) => item.pattern),
      contains(planModeSavedValidationSuccessPattern),
    );
  });

  test('PM10 live scenario classes stay explicit', () {
    final scenarios = buildLivePlanModeScenarios();
    final smokeScenarios = scenarios
        .where((item) => item.tags.contains('smoke'))
        .map((item) => item.name)
        .toSet();
    final canaryScenarios = scenarios
        .where((item) => item.tags.contains('canary'))
        .map((item) => item.name)
        .toSet();

    expect(smokeScenarios, {
      'live_host_health_scaffold',
      'live_cli_entrypoint_decision',
      'live_clarify_recovery',
    });
    expect(canaryScenarios, contains('live_readme_first_canary'));
    expect(canaryScenarios, contains('live_exact_preservation_readme'));
    expect(smokeScenarios, isNot(contains('live_readme_first_canary')));
    expect(smokeScenarios, isNot(contains('live_exact_preservation_readme')));
    expect(smokeScenarios, isNot(contains('live_ping_cli_completion')));
  });

  test('live host health smoke stops after the first harness task', () {
    final scenario = buildLivePlanModeScenarios().firstWhere(
      (item) => item.name == 'live_host_health_scaffold',
    );

    expect(scenario.harnessTaskExecutionLimit, 1);
    expect(
      scenario.artifactExpectationMode,
      PlanModeArtifactExpectationMode.anyRequired,
    );
    expect(
      scenario.savedWorkflowExpectation!.firstTaskTargetFilesContain,
      isEmpty,
    );
    expect(
      scenario.savedWorkflowExpectation!.targetFilesContain,
      contains('requirements.txt'),
    );
    expect(
      scenario.savedWorkflowExpectation!.targetFilesContain,
      contains('README.md'),
    );
  });

  test('live smoke decision scenarios keep explicit execution limits', () {
    final scenarios = buildLivePlanModeScenarios();
    final decisionScenario = scenarios.firstWhere(
      (item) => item.name == 'live_cli_entrypoint_decision',
    );
    final clarifyScenario = scenarios.firstWhere(
      (item) => item.name == 'live_clarify_recovery',
    );

    expect(decisionScenario.harnessTaskExecutionLimit, 2);
    expect(clarifyScenario.harnessTaskExecutionLimit, 1);
  });

  test('PM10 canary candidates keep promotion evidence explicit', () {
    final scenarios = buildLivePlanModeScenarios();
    final readmeCanary = scenarios.firstWhere(
      (item) => item.name == 'live_readme_first_canary',
    );
    final exactPreservationCanary = scenarios.firstWhere(
      (item) => item.name == 'live_exact_preservation_readme',
    );
    final pingCanary = scenarios.firstWhere(
      (item) => item.name == 'live_ping_cli_completion',
    );

    expect(
      readmeCanary.resolvedArtifactExpectations.map((item) => item.path),
      contains('README.md'),
    );
    expect(
      readmeCanary.resolvedArtifactExpectations
          .singleWhere((item) => item.path == 'README.md')
          .contains,
      contains('CANARY_CONTENT_FIT: README_ONLY'),
    );
    expect(
      readmeCanary.userPrompt,
      contains('CANARY_CONTENT_FIT: README_ONLY'),
    );
    expect(readmeCanary.savedWorkflowExpectation, isNotNull);
    expect(
      readmeCanary.savedWorkflowExpectation!.firstTaskTargetFilesContain,
      contains('README.md'),
    );
    expect(readmeCanary.allowedWarningPatterns, isNotEmpty);
    expect(
      readmeCanary.logExpectations.map((item) => item.pattern),
      contains(planModeSavedValidationSuccessPattern),
    );

    const exactValue =
        'EXACT_PRESERVATION_VALUE: https://example.test/downloads/build_2026-06-10.tar.zst?sha=abc123_def | ZX-900_α | 2026-06-12 | ¥3,980 | 12 GiB';
    expect(exactPreservationCanary.tags, contains('exact_preservation'));
    expect(exactPreservationCanary.tags, isNot(contains('smoke')));
    expect(exactPreservationCanary.harnessTaskExecutionLimit, 1);
    expect(exactPreservationCanary.userPrompt, contains(exactValue));
    expect(
      exactPreservationCanary.resolvedArtifactExpectations
          .singleWhere((item) => item.path == 'README.md')
          .contains,
      contains(exactValue),
    );
    expect(
      exactPreservationCanary
          .savedWorkflowExpectation!
          .firstTaskTargetFilesContain,
      contains('README.md'),
    );
    expect(
      exactPreservationCanary.savedWorkflowExpectation!.textContains,
      contains(exactValue),
    );

    expect(pingCanary.waitForExecutionCompletion, isTrue);
    expect(
      pingCanary.resolvedArtifactExpectations
          .where((item) => item.shouldExist)
          .map((item) => item.path),
      contains('ping_cli.py'),
    );
    expect(
      pingCanary.resolvedArtifactExpectations
          .where((item) => !item.shouldExist)
          .map((item) => item.path),
      allOf(contains('README.md'), contains('requirements.txt')),
    );
    expect(pingCanary.savedWorkflowExpectation, isNotNull);
    expect(
      pingCanary.savedWorkflowExpectation!.firstTaskTargetFilesContain,
      contains('ping_cli.py'),
    );
  });

  test('PM5 live ping canary requires the explicit completion artifact', () {
    final scenario = buildLivePlanModeScenarios().firstWhere(
      (item) => item.name == 'live_ping_cli_completion',
    );

    expect(scenario.userPrompt, contains('root-level ping_cli.py'));
    expect(scenario.userPrompt, contains('exactly one implementation task'));
    expect(scenario.userPrompt, contains('Do not create README.md'));
    expect(
      scenario.resolvedArtifactExpectations
          .where((item) => item.shouldExist)
          .map((item) => item.path),
      contains('ping_cli.py'),
    );
    expect(
      scenario.resolvedArtifactExpectations
          .where((item) => !item.shouldExist)
          .map((item) => item.path),
      allOf(contains('README.md'), contains('requirements.txt')),
    );
    expect(scenario.savedWorkflowExpectation, isNotNull);
    expect(scenario.savedWorkflowExpectation!.minTaskCount, 1);
    expect(
      scenario.savedWorkflowExpectation!.firstTaskTargetFilesContain,
      contains('ping_cli.py'),
    );
  });

  test('production-path TODO canary keeps the exact runtime contract', () {
    final scenario = buildLivePlanModeScenarios().firstWhere(
      (item) => item.name == 'live_todo_app_plan_completion',
    );

    expect(
      scenario.userPrompt,
      'todo_app.md \u3092\u53C2\u8003\u306B\u3057\u3066MVP\u3092\u5B9F\u88C5\u3002'
      '\u8A00\u8A9E\u306Fdart\u3068\u3059\u308B\u3002',
    );
    expect(scenario.languageCode, 'ja');
    expect(scenario.temperature, 0.2);
    expect(scenario.maxTokens, 8192);
    expect(scenario.waitForExecutionCompletion, isTrue);
    expect(scenario.executionStallTimeout, const Duration(seconds: 150));
    expect(scenario.postValidator, isNotNull);
    expect(scenario.seedFiles, hasLength(1));
    expect(scenario.seedFiles.single.destinationPath, 'todo_app.md');
    expect(scenario.seedFiles.single.immutable, isTrue);
    expect(
      scenario.taskDriftExcludedPaths,
      containsAll(<String>[
        '.todo.json',
        '.todo_app.json',
        '.todos.json',
        'tasks.json',
        'todo.json',
        'todo_app.json',
        'todo_state.json',
        'todos.json',
      ]),
    );
    expect(
      scenario.logExpectations
          .singleWhere(
            (item) =>
                item.pattern == planModeSavedValidationConvergenceGuardPattern,
          )
          .maxCount,
      0,
    );
    expect(
      scenario.logExpectations
          .singleWhere(
            (item) => item.pattern == 'unexecuted_command_action_notice',
          )
          .maxCount,
      0,
    );
  });

  test('PM5 clarify recovery live scenario requires a planning decision', () {
    final scenario = buildLivePlanModeScenarios().firstWhere(
      (item) => item.name == 'live_clarify_recovery',
    );

    expect(scenario.decisionSelections.single.optionLabel, 'JSON Report');
    expect(
      scenario.uiExpectations.where(
        (expectation) => expectation.phase == PlanModeUiPhase.decision,
      ),
      isNotEmpty,
    );
  });

  test('counts saved validation convergence guard activations', () {
    final report = buildPlanModeToolLoopConvergenceReport(const <String>[
      '[Tool] Sending in tool-aware mode (MCP)',
      planModeSavedValidationSuccessPattern,
      planModeSavedValidationConvergenceGuardPattern,
      '[Tool] Ignoring unrelated duplicate write',
      planModeSavedValidationSuccessPattern,
      planModeSavedValidationConvergenceGuardPattern,
    ]);

    expect(report, containsPair('detected', true));
    expect(report, containsPair('status', 'guarded'));
    expect(report, containsPair('successfulValidations', 2));
    expect(report, containsPair('guardActivations', 2));
    expect(report, containsPair('naturalStops', 0));
  });

  test('classifies saved validation natural stops', () {
    final report = buildPlanModeToolLoopConvergenceReport(const <String>[
      '[Tool] Sending in tool-aware mode (MCP)',
      planModeSavedValidationSuccessPattern,
      '[LLM] finishReason: FinishReason.stop',
    ]);

    expect(report, containsPair('detected', false));
    expect(report, containsPair('status', 'natural_stop'));
    expect(report, containsPair('successfulValidations', 1));
    expect(report, containsPair('guardActivations', 0));
    expect(report, containsPair('naturalStops', 1));
  });

  test('fake scenarios keep final assertions artifact and log focused', () {
    final finalResultExpectations = buildPlanModeScenarios().expand(
      (scenario) => scenario.uiExpectations.where(
        (expectation) => expectation.phase == PlanModeUiPhase.finalResult,
      ),
    );

    expect(finalResultExpectations, isEmpty);
  });

  test('batched_tool_calls includes an empty-workspace follow-up task', () {
    final scenario = buildPlanModeScenarios().firstWhere(
      (item) => item.name == 'batched_tool_calls',
    );

    expect(scenario.taskProposal, hasLength(2));
    expect(
      scenario.taskProposal.first.title,
      'Write the initial scaffold files',
    );
    expect(scenario.taskProposal.last.targetFiles, contains('main.py'));
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

  test(
    'fake scenario datasource accepts current approved task prompts',
    () async {
      final scenario = buildPlanModeScenarios().firstWhere(
        (item) => item.name == 'host_health_scaffold',
      );
      final dataSource = FakePlanModeChatDataSource(scenario);

      final streamResult = dataSource.streamChatCompletionWithTools(
        messages: [
          Message(
            id: 'prompt',
            content:
                'Use the approved saved task now: ${scenario.initialTaskTitle}\n'
                'Saved task ID: task-1',
            role: MessageRole.user,
            timestamp: DateTime(2026),
          ),
        ],
        tools: const <Map<String, dynamic>>[],
      );

      final completion = await streamResult.completion;

      expect(completion.toolCalls, isNotNull);
      expect(completion.toolCalls, hasLength(1));
      expect(completion.toolCalls!.single.name, 'write_file');
      expect(
        completion.toolCalls!.single.arguments['path'],
        'requirements.txt',
      );
    },
  );

  test(
    'fake scenario datasource accepts quality fallback task prompts',
    () async {
      final scenario = buildPlanModeScenarios().firstWhere(
        (item) => item.name == 'batched_tool_calls',
      );
      final dataSource = FakePlanModeChatDataSource(scenario);

      final streamResult = dataSource.streamChatCompletionWithTools(
        messages: [
          Message(
            id: 'prompt',
            content:
                'Use the approved saved task now: Create scaffold files\n'
                'Saved task ID: task-1\n'
                'Implement this task now. Use available tools and report completion evidence.',
            role: MessageRole.user,
            timestamp: DateTime(2026),
          ),
        ],
        tools: const <Map<String, dynamic>>[],
      );

      final completion = await streamResult.completion;

      expect(completion.toolCalls, isNotNull);
      expect(completion.toolCalls, hasLength(2));
      expect(
        completion.toolCalls!.map((toolCall) => toolCall.arguments['path']),
        ['requirements.txt', 'README.md'],
      );
    },
  );

  test(
    'fake scenario datasource accepts approved plan execution prompts',
    () async {
      final scenario = buildPlanModeScenarios().firstWhere(
        (item) => item.name == 'batched_tool_calls',
      );
      final dataSource = FakePlanModeChatDataSource(scenario);

      final streamResult = dataSource.streamChatCompletionWithTools(
        messages: [
          Message(
            id: 'prompt',
            content:
                'Use the approved plan for this coding thread. Start with the highest-value task.',
            role: MessageRole.user,
            timestamp: DateTime(2026),
          ),
        ],
        tools: const <Map<String, dynamic>>[],
      );

      final completion = await streamResult.completion;

      expect(completion.toolCalls, isNotNull);
      expect(completion.toolCalls, hasLength(2));
      expect(
        completion.toolCalls!.map((toolCall) => toolCall.arguments['path']),
        ['requirements.txt', 'README.md'],
      );
    },
  );
}
