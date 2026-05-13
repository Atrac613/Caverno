import 'dart:io';

import 'plan_mode_scenario_spec.dart';

enum PlanModeScenarioExecutionMode { fake, live }

class PlanModeScenarioTestConfig {
  const PlanModeScenarioTestConfig({
    required this.deviceName,
    required this.mode,
    required this.suiteName,
    required this.reportPrefix,
    required this.scenarios,
    required this.failOnWarnings,
    required this.requestedScenarioNames,
    required this.requestedTags,
    this.baseUrl,
    this.apiKey,
    this.model,
  });

  final String deviceName;
  final PlanModeScenarioExecutionMode mode;
  final String suiteName;
  final String reportPrefix;
  final List<PlanModeScenarioSpec> scenarios;
  final bool failOnWarnings;
  final List<String> requestedScenarioNames;
  final List<String> requestedTags;
  final String? baseUrl;
  final String? apiKey;
  final String? model;

  bool get usesLiveLlm => mode == PlanModeScenarioExecutionMode.live;
}

bool planModeEnvFlagEnabled(Map<String, String> environment, String name) {
  final rawValue = environment[name]?.trim().toLowerCase();
  return rawValue == '1' ||
      rawValue == 'true' ||
      rawValue == 'yes' ||
      rawValue == 'on';
}

String planModeEnvValueOrDefault(
  Map<String, String> environment,
  String name,
  String fallback,
) {
  final rawValue = environment[name]?.trim().toLowerCase();
  if (rawValue == null || rawValue.isEmpty) {
    return fallback;
  }
  return rawValue;
}

String requireNonEmptyPlanModeEnv(
  Map<String, String> environment,
  String name,
) {
  final value = environment[name]?.trim();
  if (value == null || value.isEmpty) {
    throw StateError('Set $name before running live Plan mode scenarios.');
  }
  return value;
}

Duration? planModeEnvDurationFromSeconds(
  Map<String, String> environment,
  String name,
) {
  final rawValue = environment[name]?.trim();
  if (rawValue == null || rawValue.isEmpty) {
    return null;
  }
  final seconds = int.tryParse(rawValue);
  if (seconds == null || seconds <= 0) {
    return null;
  }
  return Duration(seconds: seconds);
}

Duration resolvePlanModePlanningProposalTimeout(
  PlanModeScenarioSpec scenario, {
  Map<String, String>? environment,
}) {
  return planModeEnvDurationFromSeconds(
        environment ?? Platform.environment,
        'CAVERNO_PLAN_MODE_PLANNING_TIMEOUT_SECONDS',
      ) ??
      scenario.planningProposalTimeout;
}

Duration resolvePlanModeExecutionCompletionTimeout(
  PlanModeScenarioSpec scenario, {
  Map<String, String>? environment,
}) {
  return planModeEnvDurationFromSeconds(
        environment ?? Platform.environment,
        'CAVERNO_PLAN_MODE_EXECUTION_TIMEOUT_SECONDS',
      ) ??
      scenario.executionCompletionTimeout;
}

Duration resolvePlanModeExecutionStallTimeout(
  PlanModeScenarioSpec scenario, {
  Map<String, String>? environment,
}) {
  return planModeEnvDurationFromSeconds(
        environment ?? Platform.environment,
        'CAVERNO_PLAN_MODE_EXECUTION_STALL_TIMEOUT_SECONDS',
      ) ??
      scenario.executionStallTimeout;
}

Duration resolvePlanModeOverallRunTimeout(
  PlanModeScenarioSpec scenario, {
  Map<String, String>? environment,
}) {
  return planModeEnvDurationFromSeconds(
        environment ?? Platform.environment,
        'CAVERNO_PLAN_MODE_RUN_TIMEOUT_SECONDS',
      ) ??
      scenario.planningProposalTimeout +
          scenario.executionCompletionTimeout +
          const Duration(minutes: 5);
}

String defaultPlanModeDeviceName() {
  if (Platform.isLinux) {
    return 'linux';
  }
  if (Platform.isMacOS) {
    return 'macos';
  }
  if (Platform.isWindows) {
    return 'windows';
  }
  return Platform.operatingSystem.toLowerCase();
}

PlanModeScenarioTestConfig resolvePlanModeScenarioTestConfig({
  Map<String, String>? environment,
  String? defaultDeviceName,
  List<PlanModeScenarioSpec>? deterministicScenarios,
  List<PlanModeScenarioSpec>? liveScenarios,
}) {
  final resolvedEnvironment = environment ?? Platform.environment;
  final usesLiveLlm = planModeEnvFlagEnabled(
    resolvedEnvironment,
    'CAVERNO_PLAN_MODE_LIVE_LLM',
  );
  final failOnWarnings = planModeEnvFlagEnabled(
    resolvedEnvironment,
    'CAVERNO_PLAN_MODE_FAIL_ON_WARNINGS',
  );
  final tagMatchMode = planModeEnvValueOrDefault(
    resolvedEnvironment,
    'CAVERNO_PLAN_MODE_TAG_MATCH',
    'any',
  );
  final deviceName = resolvedEnvironment['CAVERNO_PLAN_MODE_DEVICE']
      ?.trim()
      .toLowerCase();
  final resolvedDeviceName = deviceName == null || deviceName.isEmpty
      ? defaultDeviceName ?? defaultPlanModeDeviceName()
      : deviceName;
  final requestedScenarioNames = _splitCsv(
    resolvedEnvironment['CAVERNO_PLAN_MODE_SCENARIOS'],
  );
  final requestedScenarioNameSet = requestedScenarioNames.toSet();
  final requestedTags = _splitCsv(
    resolvedEnvironment['CAVERNO_PLAN_MODE_TAGS'],
  ).map((value) => value.toLowerCase()).toList(growable: false);
  final requestedTagSet = requestedTags.toSet();

  final scenarios = usesLiveLlm
      ? liveScenarios ?? buildLivePlanModeScenarios()
      : deterministicScenarios ?? buildPlanModeScenarios();
  final filteredScenarios = scenarios
      .where((scenario) {
        final matchesName =
            requestedScenarioNameSet.isEmpty ||
            requestedScenarioNameSet.contains(scenario.name);
        final matchesTag =
            requestedTagSet.isEmpty ||
            (tagMatchMode == 'all'
                ? requestedTagSet.every(
                    (tag) => scenario.tags.any(
                      (candidate) => candidate.trim().toLowerCase() == tag,
                    ),
                  )
                : scenario.tags.any(
                    (tag) => requestedTagSet.contains(tag.trim().toLowerCase()),
                  ));
        return matchesName && matchesTag;
      })
      .toList(growable: false);

  if (filteredScenarios.isEmpty) {
    throw StateError(
      'No plan mode scenarios matched '
      'names="${resolvedEnvironment['CAVERNO_PLAN_MODE_SCENARIOS'] ?? ''}" '
      'tags="${resolvedEnvironment['CAVERNO_PLAN_MODE_TAGS'] ?? ''}".',
    );
  }

  if (!usesLiveLlm) {
    return PlanModeScenarioTestConfig(
      deviceName: resolvedDeviceName,
      mode: PlanModeScenarioExecutionMode.fake,
      suiteName: 'plan_mode_scenarios_$resolvedDeviceName',
      reportPrefix: 'plan_mode_suite_$resolvedDeviceName',
      scenarios: filteredScenarios,
      failOnWarnings: failOnWarnings,
      requestedScenarioNames: requestedScenarioNames,
      requestedTags: requestedTags,
    );
  }

  return PlanModeScenarioTestConfig(
    deviceName: resolvedDeviceName,
    mode: PlanModeScenarioExecutionMode.live,
    suiteName: 'plan_mode_live_scenarios_$resolvedDeviceName',
    reportPrefix: 'plan_mode_live_suite_$resolvedDeviceName',
    scenarios: filteredScenarios,
    failOnWarnings: failOnWarnings,
    requestedScenarioNames: requestedScenarioNames,
    requestedTags: requestedTags,
    baseUrl: requireNonEmptyPlanModeEnv(
      resolvedEnvironment,
      'CAVERNO_LLM_BASE_URL',
    ),
    apiKey: requireNonEmptyPlanModeEnv(
      resolvedEnvironment,
      'CAVERNO_LLM_API_KEY',
    ),
    model: requireNonEmptyPlanModeEnv(resolvedEnvironment, 'CAVERNO_LLM_MODEL'),
  );
}

List<String> _splitCsv(String? rawValue) {
  return (rawValue
              ?.split(',')
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty) ??
          const Iterable<String>.empty())
      .toList(growable: false);
}
