import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/test_support/plan_mode_scenario_config.dart';
import '../../integration_test/test_support/plan_mode_scenario_spec.dart';
import '../../integration_test/test_support/plan_mode_tool_loop_convergence.dart';

void main() {
  group('plan mode scenario config', () {
    test('filters deterministic scenarios by all requested tags', () {
      final config = resolvePlanModeScenarioTestConfig(
        environment: const {
          'CAVERNO_PLAN_MODE_DEVICE': ' MacOS ',
          'CAVERNO_PLAN_MODE_TAGS': 'smoke, recovery',
          'CAVERNO_PLAN_MODE_TAG_MATCH': 'all',
          'CAVERNO_PLAN_MODE_FAIL_ON_WARNINGS': 'YES',
        },
        defaultDeviceName: 'linux',
        deterministicScenarios: <PlanModeScenarioSpec>[
          _scenario('smoke_only', tags: const <String>['smoke']),
          _scenario(
            'recovery_smoke',
            tags: const <String>['recovery', 'smoke'],
          ),
        ],
        liveScenarios: <PlanModeScenarioSpec>[_scenario('live')],
      );

      expect(config.mode, PlanModeScenarioExecutionMode.fake);
      expect(config.deviceName, 'macos');
      expect(config.suiteName, 'plan_mode_scenarios_macos');
      expect(config.reportPrefix, 'plan_mode_suite_macos');
      expect(
        config.reportRootPath,
        '${Directory.current.path}/build/integration_test_reports',
      );
      expect(config.failOnWarnings, isTrue);
      expect(config.requestedTags, const <String>['smoke', 'recovery']);
      expect(config.scenarios.map((scenario) => scenario.name), const <String>[
        'recovery_smoke',
      ]);
    });

    test('resolves live scenario credentials and name filters', () {
      final config = resolvePlanModeScenarioTestConfig(
        environment: const {
          'CAVERNO_PLAN_MODE_LIVE_LLM': 'true',
          'CAVERNO_PLAN_MODE_SCENARIOS': 'live_two',
          'CAVERNO_LLM_BASE_URL': 'http://localhost:1234/v1',
          'CAVERNO_LLM_API_KEY': 'test-key',
          'CAVERNO_LLM_MODEL': 'test-model',
        },
        defaultDeviceName: 'macos',
        deterministicScenarios: <PlanModeScenarioSpec>[_scenario('fake')],
        liveScenarios: <PlanModeScenarioSpec>[
          _scenario('live_one'),
          _scenario('live_two'),
        ],
      );

      expect(config.mode, PlanModeScenarioExecutionMode.live);
      expect(config.usesLiveLlm, isTrue);
      expect(config.suiteName, 'plan_mode_live_scenarios_macos');
      expect(config.reportPrefix, 'plan_mode_live_suite_macos');
      expect(
        config.reportRootPath,
        '${Directory.current.path}/build/integration_test_reports',
      );
      expect(config.baseUrl, 'http://localhost:1234/v1');
      expect(config.apiKey, 'test-key');
      expect(config.model, 'test-model');
      expect(config.requestedScenarioNames, const <String>['live_two']);
      expect(config.scenarios.single.name, 'live_two');
    });

    test('requires live credentials when live mode is enabled', () {
      expect(
        () => resolvePlanModeScenarioTestConfig(
          environment: const {'CAVERNO_PLAN_MODE_LIVE_LLM': '1'},
          defaultDeviceName: 'macos',
          deterministicScenarios: <PlanModeScenarioSpec>[_scenario('fake')],
          liveScenarios: <PlanModeScenarioSpec>[_scenario('live')],
        ),
        throwsStateError,
      );
    });

    test('resolves report root override', () {
      final config = resolvePlanModeScenarioTestConfig(
        environment: const {
          'CAVERNO_PLAN_MODE_REPORT_ROOT': ' /tmp/caverno-qwen-gate ',
        },
        defaultDeviceName: 'macos',
        deterministicScenarios: <PlanModeScenarioSpec>[_scenario('fake')],
        liveScenarios: <PlanModeScenarioSpec>[_scenario('live')],
      );

      expect(config.reportRootPath, '/tmp/caverno-qwen-gate');
    });

    test('resolves timeout overrides from seconds', () {
      final scenario = _scenario(
        'timeouts',
        planningProposalTimeout: const Duration(seconds: 5),
        executionCompletionTimeout: const Duration(seconds: 20),
        executionStallTimeout: const Duration(seconds: 45),
      );

      expect(
        resolvePlanModePlanningProposalTimeout(
          scenario,
          environment: const {
            'CAVERNO_PLAN_MODE_PLANNING_TIMEOUT_SECONDS': '7',
          },
        ),
        const Duration(seconds: 7),
      );
      expect(
        resolvePlanModeExecutionCompletionTimeout(
          scenario,
          environment: const {
            'CAVERNO_PLAN_MODE_EXECUTION_TIMEOUT_SECONDS': '8',
          },
        ),
        const Duration(seconds: 8),
      );
      expect(
        resolvePlanModeExecutionStallTimeout(
          scenario,
          environment: const {
            'CAVERNO_PLAN_MODE_EXECUTION_STALL_TIMEOUT_SECONDS': '9',
          },
        ),
        const Duration(seconds: 9),
      );
      expect(
        resolvePlanModeOverallRunTimeout(
          scenario,
          environment: const {'CAVERNO_PLAN_MODE_RUN_TIMEOUT_SECONDS': '10'},
        ),
        const Duration(seconds: 10),
      );
      expect(
        resolvePlanModePlanningProposalTimeout(
          scenario,
          environment: const {
            'CAVERNO_PLAN_MODE_PLANNING_TIMEOUT_SECONDS': '-1',
          },
        ),
        scenario.planningProposalTimeout,
      );
    });

    test('live smoke scenarios wait for harness task completion logs', () {
      final scenarios = {
        for (final scenario in buildLivePlanModeScenarios())
          scenario.name: scenario,
      };

      expect(
        _minLogCount(
          scenarios['live_host_health_scaffold']!,
          planModeSavedValidationSuccessPattern,
        ),
        1,
      );
      expect(
        _minLogCount(
          scenarios['live_cli_entrypoint_decision']!,
          planModeSavedValidationSuccessPattern,
        ),
        2,
      );
      expect(
        _minLogCount(
          scenarios['live_clarify_recovery']!,
          planModeSavedValidationSuccessPattern,
        ),
        1,
      );
      expect(
        _hasLogPattern(
          scenarios['live_cli_entrypoint_decision']!,
          '[Workflow] Harness stopped after reaching task execution limit: 2',
        ),
        isTrue,
      );
    });
  });
}

int? _minLogCount(PlanModeScenarioSpec scenario, String pattern) {
  for (final expectation in scenario.logExpectations) {
    if (expectation.pattern == pattern) {
      return expectation.minCount;
    }
  }
  return null;
}

bool _hasLogPattern(PlanModeScenarioSpec scenario, String pattern) {
  return scenario.logExpectations.any(
    (expectation) => expectation.pattern == pattern,
  );
}

PlanModeScenarioSpec _scenario(
  String name, {
  List<String> tags = const <String>[],
  Duration planningProposalTimeout = const Duration(seconds: 5),
  Duration executionCompletionTimeout = const Duration(seconds: 20),
  Duration executionStallTimeout = const Duration(seconds: 45),
}) {
  return PlanModeScenarioSpec(
    name: name,
    userPrompt: 'Create a test artifact.',
    projectName: 'plan-mode-config-test',
    workflowResponses: const <PlanModeWorkflowResponseSpec>[],
    taskProposal: const <PlanModeScenarioTaskSpec>[
      PlanModeScenarioTaskSpec(
        title: 'Create test artifact',
        targetFiles: <String>['README.md'],
        validationCommand: 'test -f README.md',
        notes: 'Keep the fixture minimal.',
      ),
    ],
    toolWrites: const <PlanModeScenarioToolWriteSpec>[],
    continuationStreams: const <String>[],
    tags: tags,
    planningProposalTimeout: planningProposalTimeout,
    executionCompletionTimeout: executionCompletionTimeout,
    executionStallTimeout: executionStallTimeout,
  );
}
