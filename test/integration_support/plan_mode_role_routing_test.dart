import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/test_support/plan_mode_scenario_config.dart';
import '../../integration_test/test_support/plan_mode_scenario_spec.dart';

PlanModeScenarioTestConfig _config({
  String? planningBaseUrl,
  String? planningModel,
  String? planningApiKey,
}) {
  return PlanModeScenarioTestConfig(
    deviceName: 'macos',
    mode: PlanModeScenarioExecutionMode.live,
    suiteName: 'suite',
    reportPrefix: 'report',
    reportRootPath: '/tmp/report',
    scenarios: const <PlanModeScenarioSpec>[],
    failOnWarnings: true,
    requestedScenarioNames: const <String>[],
    requestedTags: const <String>[],
    baseUrl: 'http://192.168.100.241:8080/v1',
    apiKey: 'local-key',
    model: 'qwen3.6-27b-vision',
    planningBaseUrl: planningBaseUrl,
    planningApiKey: planningApiKey,
    planningModel: planningModel,
  );
}

AppSettings _baseSettings(PlanModeScenarioTestConfig config) {
  return AppSettings.defaults().copyWith(
    baseUrl: config.baseUrl!,
    apiKey: config.apiKey!,
    model: config.model!,
  );
}

void main() {
  test('the baseline arm registers no planning role', () {
    final config = _config();
    final settings = applyPlanModeRoleRouting(_baseSettings(config), config);

    expect(config.routesPlanningRole, isFalse);
    expect(settings.planningModel, isEmpty);
    expect(settings.planningEndpointId, isEmpty);
    expect(
      settings.effectivePlanningModel,
      'qwen3.6-27b-vision',
      reason: 'the primary model drafts the plan it will execute',
    );
  });

  test('the planner arm keeps the planning endpoint pointed at its own host', () {
    final config = _config(
      planningBaseUrl: 'https://api.x.ai/v1',
      planningApiKey: 'planner-key',
      planningModel: 'grok-4.5',
    );
    // Normalization runs on every load, so the assertion has to survive it:
    // with only the planner registered it would adopt the planner as the active
    // endpoint and overwrite its base URL with the local one, silently running
    // the whole A/B on the local model.
    final settings = applyPlanModeRoleRouting(
      _baseSettings(config),
      config,
    ).withNormalizedLlmEndpoints();

    final planner = settings.llmEndpoints.firstWhere(
      (endpoint) => endpoint.id == planModeCanaryPlannerEndpointId,
    );
    expect(planner.normalizedBaseUrl, 'https://api.x.ai/v1');
    expect(planner.normalizedModel, 'grok-4.5');
    expect(planner.apiKey, 'planner-key');

    expect(settings.activeLlmEndpointId, planModeCanaryPrimaryEndpointId);
    expect(settings.baseUrl, 'http://192.168.100.241:8080/v1');
    expect(
      settings.model,
      'qwen3.6-27b-vision',
      reason: 'execution must stay on the primary model',
    );
    expect(settings.planningEndpointId, planModeCanaryPlannerEndpointId);
    expect(settings.effectivePlanningModel, 'grok-4.5');
  });

  test('a planning host without a model is not a planner arm', () {
    final config = _config(planningBaseUrl: 'https://api.x.ai/v1');
    final settings = applyPlanModeRoleRouting(_baseSettings(config), config);

    expect(config.routesPlanningRole, isFalse);
    expect(settings.planningEndpointId, isEmpty);
  });
}
