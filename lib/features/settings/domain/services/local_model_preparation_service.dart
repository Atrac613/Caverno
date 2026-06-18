import '../entities/app_settings.dart';
import '../entities/local_model_lifecycle.dart';

class LocalModelPreparationPlan {
  const LocalModelPreparationPlan({
    required this.targetModelIds,
    required this.loadableModelIds,
    required this.readyModelIds,
    required this.inProgressModelIds,
    required this.missingModelIds,
  });

  final List<String> targetModelIds;
  final List<String> loadableModelIds;
  final List<String> readyModelIds;
  final List<String> inProgressModelIds;
  final List<String> missingModelIds;

  bool get hasTargets => targetModelIds.isNotEmpty;

  bool get hasLoadableModels => loadableModelIds.isNotEmpty;
}

/// LL9 one-tap role-model preparation for a selected llama.cpp router endpoint.
class LocalModelPreparationService {
  const LocalModelPreparationService();

  LocalModelPreparationPlan buildPrimaryRoleModelPlan({
    required AppSettings settings,
    required LocalModelLifecycleCatalog catalog,
  }) => buildRoleModelPlanForEndpoint(
    settings: settings,
    catalog: catalog,
    endpointId: '',
  );

  LocalModelPreparationPlan buildRoleModelPlanForEndpoint({
    required AppSettings settings,
    required LocalModelLifecycleCatalog catalog,
    required String endpointId,
  }) {
    final targetModelIds = _roleModelIdsForEndpoint(settings, endpointId);
    if (!catalog.supported || targetModelIds.isEmpty) {
      return LocalModelPreparationPlan(
        targetModelIds: targetModelIds,
        loadableModelIds: const [],
        readyModelIds: const [],
        inProgressModelIds: const [],
        missingModelIds: catalog.supported ? const [] : targetModelIds,
      );
    }

    final modelsById = <String, LocalManagedModel>{
      for (final model in catalog.models) model.id: model,
    };
    final loadable = <String>[];
    final ready = <String>[];
    final inProgress = <String>[];
    final missing = <String>[];

    for (final modelId in targetModelIds) {
      final model = modelsById[modelId];
      if (model == null) {
        missing.add(modelId);
        continue;
      }
      switch (model.state) {
        case LocalModelLifecycleState.loaded:
        case LocalModelLifecycleState.sleeping:
          ready.add(modelId);
        case LocalModelLifecycleState.loading:
        case LocalModelLifecycleState.downloading:
          inProgress.add(modelId);
        case LocalModelLifecycleState.unloaded:
        case LocalModelLifecycleState.unknown:
          loadable.add(modelId);
      }
    }

    return LocalModelPreparationPlan(
      targetModelIds: targetModelIds,
      loadableModelIds: loadable,
      readyModelIds: ready,
      inProgressModelIds: inProgress,
      missingModelIds: missing,
    );
  }

  List<String> _roleModelIdsForEndpoint(
    AppSettings settings,
    String endpointId,
  ) {
    if (settings.llmProvider != LlmProvider.openAiCompatible) {
      return const [];
    }

    final selectedEndpointId = endpointId.trim();
    final ordered = <String>[
      if (settings.memoryExtractionEndpointId.trim() == selectedEndpointId)
        settings.memoryExtractionModel.trim(),
      if (settings.subagentEndpointId.trim() == selectedEndpointId)
        settings.subagentModel.trim(),
      if (settings.goalSuggestionEndpointId.trim() == selectedEndpointId)
        settings.goalSuggestionModel.trim(),
      if (settings.approvalAutoReviewEndpointId.trim() == selectedEndpointId)
        settings.approvalAutoReviewModel.trim(),
    ];
    final seen = <String>{};
    final result = <String>[];
    for (final modelId in ordered) {
      if (modelId.isEmpty || !seen.add(modelId)) {
        continue;
      }
      result.add(modelId);
    }
    return result;
  }
}
