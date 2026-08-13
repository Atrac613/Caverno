import '../../../../core/types/assistant_mode.dart';
import '../../../settings/domain/entities/app_settings.dart';
import '../../../settings/domain/services/llm_request_temperature_policy.dart';
import '../../../settings/domain/services/mesh_endpoint_router.dart';
import '../../../settings/domain/services/primary_model_preparation_service.dart';
import '../../../settings/presentation/providers/local_model_lifecycle_provider.dart';
import '../../data/datasources/chat_datasource.dart';
import '../../data/datasources/llm_session_log_store.dart';
import '../../data/datasources/primary_route_chat_datasource.dart';
import '../../domain/services/primary_model_router.dart';

typedef AssignedPrimaryDataSourceBuilder =
    ChatDataSource Function(ResolvedEndpoint endpoint);
typedef PrimaryRouteRecorder =
    Future<void> Function(PrimaryRouteResolution resolution);

final class PrimaryTurnRouteRuntime {
  final Map<int, (PrimaryRouteResolution, ChatDataSource)> _routes = {};

  Future<void> capture({
    required int generation,
    required AppSettings settings,
    required AssistantMode assistantMode,
    required ChatDataSource primaryDataSource,
    required EndpointHealthTracker health,
    required AssignedPrimaryDataSourceBuilder buildAssignedDataSource,
    required PrimaryRouteModelPreparer preparer,
    required PrimaryRouteRecorder record,
  }) async {
    final resolution = const PrimaryModelRouter().resolve(
      PrimaryRouteContext(
        settings: settings,
        assistantMode: assistantMode,
        unhealthyEndpointIds: health.unhealthyEndpointIds,
      ),
    );
    final assigned = resolution.endpoint.isPrimary
        ? primaryDataSource
        : buildAssignedDataSource(resolution.endpoint);
    final dataSource = resolution.endpoint.isPrimary
        ? assigned
        : PrimaryRouteChatDataSource(
            assigned: assigned,
            primary: primaryDataSource,
            assignedEndpointId: resolution.endpoint.endpointId,
            assignedModel: resolution.endpoint.model,
            primaryModel: resolution.fallbackModel,
            health: health,
          );
    _routes[generation] = (resolution, dataSource);
    await preparer.prepare(settings: settings, resolution: resolution);
    await record(resolution);
  }

  ChatDataSource dataSource(int generation, ChatDataSource fallback) =>
      _routes[generation]?.$2 ?? fallback;

  String model(int generation, AppSettings settings) =>
      _routes[generation]?.$1.endpoint.model ?? settings.effectiveModel;

  String baseUrl(int generation, AppSettings settings) =>
      _routes[generation]?.$1.endpoint.baseUrl ?? settings.baseUrl;

  ModelCapabilityProfile? capabilityProfile(
    int? generation,
    AppSettings settings,
  ) => generation == null
      ? settings.effectiveModelCapabilityProfile
      : settings.modelCapabilityProfileFor(
          provider: settings.llmProvider,
          baseUrl: baseUrl(generation, settings),
          model: model(generation, settings),
        );

  ModelHarnessConfig? harnessConfig(int? generation, AppSettings settings) =>
      generation == null
      ? settings.effectiveModelHarnessConfig
      : settings.modelHarnessConfigFor(
          provider: settings.llmProvider,
          baseUrl: baseUrl(generation, settings),
          model: model(generation, settings),
        );

  LlmRequestTemperaturePolicy temperaturePolicy(
    int generation,
    AppSettings settings,
  ) {
    final resolution = _routes[generation]?.$1;
    if (resolution == null) {
      return LlmRequestTemperaturePolicy.forSettings(settings);
    }
    return LlmRequestTemperaturePolicy.forSettings(
      settings.copyWith(
        baseUrl: resolution.endpoint.baseUrl,
        model: resolution.endpoint.model,
      ),
    );
  }

  AssistantMode assistantMode(int generation, AppSettings settings) =>
      _routes[generation]?.$1.context.assistantMode ?? settings.assistantMode;

  void release(int generation) => _routes.remove(generation);
  int get count => _routes.length;
}

final class PrimaryRouteModelPreparer {
  PrimaryRouteModelPreparer({
    required PrimaryModelPreparationServiceFactory serviceFactory,
    required void Function(PrimaryModelPreparationOutcome outcome) logOutcome,
    required void Function(Object error, StackTrace stackTrace) logError,
  }) : _serviceFactory = serviceFactory,
       _logOutcome = logOutcome,
       _logError = logError;

  final PrimaryModelPreparationServiceFactory _serviceFactory;
  final void Function(PrimaryModelPreparationOutcome outcome) _logOutcome;
  final void Function(Object error, StackTrace stackTrace) _logError;
  final Map<String, String> _preparedModels = {};

  void notePrimaryRouteChange({
    required AppSettings settings,
    required String? previousModelId,
  }) {
    final previous = previousModelId?.trim() ?? '';
    if (previous.isEmpty) return;
    _preparedModels[LlmEndpoint.normalizeBaseUrl(settings.baseUrl)] = previous;
  }

  Future<void> prepare({
    required AppSettings settings,
    required PrimaryRouteResolution resolution,
  }) async {
    if (settings.demoMode ||
        settings.llmProvider != LlmProvider.openAiCompatible) {
      return;
    }
    final endpoint = resolution.endpoint;
    final model = endpoint.model.trim();
    if (model.isEmpty) return;
    final key = endpoint.isPrimary
        ? LlmEndpoint.normalizeBaseUrl(settings.baseUrl)
        : endpoint.endpointId;
    final previous = _preparedModels[key];
    if (resolution.reason == PrimaryRouteReason.primaryDefault &&
        previous == null) {
      return;
    }
    if (previous == model) return;
    final config = endpoint.isPrimary
        ? LocalModelLifecycleEndpointConfig.primary(
            baseUrl: endpoint.baseUrl,
            apiKey: endpoint.apiKey,
          )
        : LocalModelLifecycleEndpointConfig(
            id: endpoint.endpointId,
            baseUrl: endpoint.baseUrl,
            apiKey: endpoint.apiKey,
            label: endpoint.endpointId,
            isPrimary: false,
          );
    final service = _serviceFactory(config);
    try {
      final outcome = await service
          .preparePrimaryModel(
            settings: settings.copyWith(
              baseUrl: endpoint.baseUrl,
              apiKey: endpoint.apiKey,
              model: model,
            ),
            previousPrimaryModelId: previous,
            refreshCatalog: true,
          )
          .timeout(const Duration(seconds: 60));
      _logOutcome(outcome);
      if (_retainsPreparedModel(outcome.status)) _preparedModels[key] = model;
    } on Object catch (error, stackTrace) {
      _logError(error, stackTrace);
    }
  }

  bool _retainsPreparedModel(PrimaryModelPreparationStatus status) =>
      switch (status) {
        PrimaryModelPreparationStatus.ready ||
        PrimaryModelPreparationStatus.inProgress ||
        PrimaryModelPreparationStatus.loadStarted ||
        PrimaryModelPreparationStatus.unsupported => true,
        _ => false,
      };
}

Future<void> recordPrimaryTurnRoute({
  required LlmSessionLogStore store,
  required LlmSessionLogContext? context,
  required int generation,
  required PrimaryRouteResolution resolution,
  required bool enabled,
}) async {
  if (!LlmSessionLogStore.isEnabled(settingsEnabled: enabled)) return;
  await store.recordPrimaryModelRoute(
    context: context,
    turnId: 'gen-$generation',
    assistantMode: resolution.context.assistantMode.name,
    endpointId: resolution.endpoint.endpointId,
    model: resolution.endpoint.model,
    reason: resolution.reason.name,
    demotedToPrimary: resolution.endpoint.demotedToPrimary,
    at: DateTime.now(),
  );
}
