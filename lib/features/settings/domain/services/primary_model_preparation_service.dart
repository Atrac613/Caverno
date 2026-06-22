import '../entities/app_settings.dart';
import '../entities/local_model_lifecycle.dart';

typedef ManagedModelCatalogLoader =
    Future<LocalModelLifecycleCatalog> Function({bool refresh});
typedef ManagedModelLoader =
    Future<LocalModelLifecycleActionResult> Function(String modelId);

enum PrimaryModelPreparationStatus {
  skipped,
  unsupported,
  ready,
  inProgress,
  missing,
  loadRequired,
  loadStarted,
  failed,
}

class PrimaryModelPreparationPlan {
  const PrimaryModelPreparationPlan({
    required this.modelId,
    required this.status,
    required this.message,
  });

  final String modelId;
  final PrimaryModelPreparationStatus status;
  final String message;

  bool get shouldLoad => status == PrimaryModelPreparationStatus.loadRequired;
}

class PrimaryModelPreparationOutcome {
  const PrimaryModelPreparationOutcome({
    required this.modelId,
    required this.status,
    required this.message,
    this.actionResult,
  });

  final String modelId;
  final PrimaryModelPreparationStatus status;
  final String message;
  final LocalModelLifecycleActionResult? actionResult;

  bool get attemptedLoad => actionResult != null;
}

class PrimaryModelPreparationService {
  const PrimaryModelPreparationService({
    required this.listManagedModels,
    required this.loadManagedModel,
  });

  final ManagedModelCatalogLoader listManagedModels;
  final ManagedModelLoader loadManagedModel;

  Future<PrimaryModelPreparationOutcome> preparePrimaryModel({
    required AppSettings settings,
    bool refreshCatalog = false,
  }) async {
    final skipPlan = buildSettingsOnlyPlan(settings);
    if (skipPlan != null) {
      return _outcomeFromPlan(skipPlan);
    }

    final LocalModelLifecycleCatalog catalog;
    try {
      catalog = await listManagedModels(refresh: refreshCatalog);
    } on Object catch (error) {
      return PrimaryModelPreparationOutcome(
        modelId: settings.model.trim(),
        status: PrimaryModelPreparationStatus.failed,
        message:
            'Failed to inspect the managed model catalog: '
            '${error.runtimeType}: $error',
      );
    }

    final plan = buildPlan(modelId: settings.model, catalog: catalog);
    if (!plan.shouldLoad) {
      return _outcomeFromPlan(plan);
    }

    try {
      final result = await loadManagedModel(plan.modelId);
      if (result.succeeded) {
        return PrimaryModelPreparationOutcome(
          modelId: plan.modelId,
          status: PrimaryModelPreparationStatus.loadStarted,
          message: result.message,
          actionResult: result,
        );
      }
      return PrimaryModelPreparationOutcome(
        modelId: plan.modelId,
        status: result.supported
            ? PrimaryModelPreparationStatus.failed
            : PrimaryModelPreparationStatus.unsupported,
        message: result.message,
        actionResult: result,
      );
    } on Object catch (error) {
      return PrimaryModelPreparationOutcome(
        modelId: plan.modelId,
        status: PrimaryModelPreparationStatus.failed,
        message:
            'Failed to request managed model load: '
            '${error.runtimeType}: $error',
      );
    }
  }

  PrimaryModelPreparationPlan? buildSettingsOnlyPlan(AppSettings settings) {
    if (settings.llmProvider != LlmProvider.openAiCompatible) {
      return const PrimaryModelPreparationPlan(
        modelId: '',
        status: PrimaryModelPreparationStatus.skipped,
        message:
            'Primary model preparation is only available for '
            'OpenAI-compatible endpoints.',
      );
    }

    final modelId = settings.model.trim();
    if (modelId.isEmpty) {
      return const PrimaryModelPreparationPlan(
        modelId: '',
        status: PrimaryModelPreparationStatus.skipped,
        message: 'Primary model preparation skipped because no model is set.',
      );
    }

    return null;
  }

  PrimaryModelPreparationPlan buildPlan({
    required String modelId,
    required LocalModelLifecycleCatalog catalog,
  }) {
    final normalizedModelId = modelId.trim();
    if (normalizedModelId.isEmpty) {
      return const PrimaryModelPreparationPlan(
        modelId: '',
        status: PrimaryModelPreparationStatus.skipped,
        message: 'Primary model preparation skipped because no model is set.',
      );
    }
    if (!catalog.supported) {
      return PrimaryModelPreparationPlan(
        modelId: normalizedModelId,
        status: PrimaryModelPreparationStatus.unsupported,
        message:
            catalog.message ??
            'Managed model lifecycle is not supported by this endpoint.',
      );
    }

    final model = _findModel(catalog.models, normalizedModelId);
    if (model == null) {
      return PrimaryModelPreparationPlan(
        modelId: normalizedModelId,
        status: PrimaryModelPreparationStatus.missing,
        message: 'Managed model catalog does not include "$normalizedModelId".',
      );
    }

    return switch (model.state) {
      LocalModelLifecycleState.loaded ||
      LocalModelLifecycleState.sleeping => PrimaryModelPreparationPlan(
        modelId: normalizedModelId,
        status: PrimaryModelPreparationStatus.ready,
        message: 'Primary model "$normalizedModelId" is already ready.',
      ),
      LocalModelLifecycleState.loading ||
      LocalModelLifecycleState.downloading => PrimaryModelPreparationPlan(
        modelId: normalizedModelId,
        status: PrimaryModelPreparationStatus.inProgress,
        message: 'Primary model "$normalizedModelId" is already loading.',
      ),
      LocalModelLifecycleState.unloaded ||
      LocalModelLifecycleState.unknown => PrimaryModelPreparationPlan(
        modelId: normalizedModelId,
        status: PrimaryModelPreparationStatus.loadRequired,
        message: 'Primary model "$normalizedModelId" should be loaded.',
      ),
    };
  }

  LocalManagedModel? _findModel(
    List<LocalManagedModel> models,
    String modelId,
  ) {
    for (final model in models) {
      if (model.id == modelId) {
        return model;
      }
    }
    return null;
  }

  PrimaryModelPreparationOutcome _outcomeFromPlan(
    PrimaryModelPreparationPlan plan,
  ) {
    return PrimaryModelPreparationOutcome(
      modelId: plan.modelId,
      status: plan.status,
      message: plan.message,
    );
  }
}
