import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/features/chat/domain/services/primary_model_router.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/domain/services/mesh_endpoint_router.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const router = PrimaryModelRouter();

  AppSettings settings({
    String generalModel = '',
    String codingModel = '',
    String planModel = '',
    String generalEndpoint = '',
    String codingEndpoint = '',
    String planEndpoint = '',
    List<LlmEndpoint> endpoints = const <LlmEndpoint>[],
    LlmProvider provider = LlmProvider.openAiCompatible,
  }) => AppSettings.defaults().copyWith(
    llmProvider: provider,
    baseUrl: 'http://primary.example/v1',
    model: 'primary-model',
    apiKey: 'primary-key',
    generalPrimaryModel: generalModel,
    codingPrimaryModel: codingModel,
    planPrimaryModel: planModel,
    generalPrimaryEndpointId: generalEndpoint,
    codingPrimaryEndpointId: codingEndpoint,
    planPrimaryEndpointId: planEndpoint,
    llmEndpoints: endpoints,
  );

  const qualityEndpoint = LlmEndpoint(
    id: 'quality-host',
    baseUrl: 'http://quality.example/v1',
    apiKey: 'quality-key',
    model: 'quality-model',
  );

  test('empty assignment preserves the primary route', () {
    final result = router.resolve(
      PrimaryRouteContext(
        settings: settings(),
        assistantMode: AssistantMode.general,
      ),
    );

    expect(result.endpoint.isPrimary, isTrue);
    expect(result.endpoint.model, 'primary-model');
    expect(result.reason, PrimaryRouteReason.primaryDefault);
    expect(result.escalationRequested, isFalse);
  });

  test('model-only assignment stays on the primary endpoint', () {
    final result = router.resolve(
      PrimaryRouteContext(
        settings: settings(codingModel: 'coding-model'),
        assistantMode: AssistantMode.coding,
      ),
    );

    expect(result.endpoint.isPrimary, isTrue);
    expect(result.endpoint.model, 'coding-model');
    expect(result.fallbackModel, 'primary-model');
    expect(result.reason, PrimaryRouteReason.explicitModeModel);
  });

  test('endpoint-only assignment uses the endpoint catalog model', () {
    final result = router.resolve(
      PrimaryRouteContext(
        settings: settings(
          planEndpoint: qualityEndpoint.id,
          endpoints: const [qualityEndpoint],
        ),
        assistantMode: AssistantMode.plan,
      ),
    );

    expect(result.endpoint.isPrimary, isFalse);
    expect(result.endpoint.endpointId, qualityEndpoint.id);
    expect(result.endpoint.model, 'quality-model');
    expect(result.reason, PrimaryRouteReason.endpointDefaultModel);
  });

  test('explicit endpoint model overrides the endpoint catalog model', () {
    final result = router.resolve(
      PrimaryRouteContext(
        settings: settings(
          codingModel: 'coding-model',
          codingEndpoint: qualityEndpoint.id,
          endpoints: const [qualityEndpoint],
        ),
        assistantMode: AssistantMode.coding,
      ),
    );

    expect(result.endpoint.endpointId, qualityEndpoint.id);
    expect(result.endpoint.model, 'coding-model');
    expect(result.reason, PrimaryRouteReason.explicitEndpointModel);
  });

  test('unhealthy endpoint demotes to the primary model', () {
    final result = router.resolve(
      PrimaryRouteContext(
        settings: settings(
          codingModel: 'mesh-only-model',
          codingEndpoint: qualityEndpoint.id,
          endpoints: const [qualityEndpoint],
        ),
        assistantMode: AssistantMode.coding,
        unhealthyEndpointIds: const {'quality-host'},
      ),
    );

    expect(result.endpoint.isPrimary, isTrue);
    expect(result.endpoint.model, 'primary-model');
    expect(result.endpoint.demotedToPrimary, isTrue);
    expect(result.requestedModel, 'mesh-only-model');
    expect(result.reason, PrimaryRouteReason.endpointUnavailable);
  });

  test('endpoint without a model demotes instead of guessing', () {
    const emptyModelEndpoint = LlmEndpoint(
      id: 'empty-host',
      baseUrl: 'http://empty.example/v1',
    );
    final result = router.resolve(
      PrimaryRouteContext(
        settings: settings(
          generalEndpoint: emptyModelEndpoint.id,
          endpoints: const [emptyModelEndpoint],
        ),
        assistantMode: AssistantMode.general,
      ),
    );

    expect(result.endpoint.isPrimary, isTrue);
    expect(result.endpoint.model, 'primary-model');
    expect(result.reason, PrimaryRouteReason.endpointModelMissing);
  });

  test('Apple Foundation Models ignores mode assignments', () {
    final result = router.resolve(
      PrimaryRouteContext(
        settings: settings(
          provider: LlmProvider.appleFoundationModels,
          codingModel: 'ignored-model',
          codingEndpoint: qualityEndpoint.id,
          endpoints: const [qualityEndpoint],
        ),
        assistantMode: AssistantMode.coding,
      ),
    );

    expect(result.endpoint.isPrimary, isTrue);
    expect(result.endpoint.model, AppSettings.appleFoundationModelsModelId);
    expect(result.reason, PrimaryRouteReason.appleFoundationModels);
  });

  test('LL25 checkpoint is evaluated without changing the LL24 route', () {
    const checkpoint = _AlwaysEscalateCheckpoint();
    const routed = PrimaryModelRouter(escalationCheckpoint: checkpoint);
    final result = routed.resolve(
      PrimaryRouteContext(
        settings: settings(),
        assistantMode: AssistantMode.general,
      ),
    );

    expect(result.endpoint.model, 'primary-model');
    expect(result.escalationRequested, isTrue);
  });
}

final class _AlwaysEscalateCheckpoint
    implements PrimaryRouteEscalationCheckpoint {
  const _AlwaysEscalateCheckpoint();

  @override
  bool shouldEscalate({
    required PrimaryRouteContext context,
    required ResolvedEndpoint resolvedEndpoint,
  }) => true;
}
