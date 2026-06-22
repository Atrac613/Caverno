import '../entities/app_settings.dart';
import '../entities/local_model_lifecycle.dart';

typedef ManagedModelCatalogLoader =
    Future<LocalModelLifecycleCatalog> Function({bool refresh});
typedef ManagedModelLoader =
    Future<LocalModelLifecycleActionResult> Function(String modelId);
typedef ManagedModelUnloader =
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
    this.previousModelId,
    this.unloadActionResult,
    this.actionResult,
  });

  final String modelId;
  final PrimaryModelPreparationStatus status;
  final String message;
  final String? previousModelId;
  final LocalModelLifecycleActionResult? unloadActionResult;
  final LocalModelLifecycleActionResult? actionResult;

  bool get attemptedLoad => actionResult != null;

  bool get attemptedUnload => unloadActionResult != null;
}

class PrimaryModelPreparationService {
  const PrimaryModelPreparationService({
    required this.listManagedModels,
    required this.unloadManagedModel,
    required this.loadManagedModel,
  });

  final ManagedModelCatalogLoader listManagedModels;
  final ManagedModelUnloader unloadManagedModel;
  final ManagedModelLoader loadManagedModel;

  Future<PrimaryModelPreparationOutcome> preparePrimaryModel({
    required AppSettings settings,
    String? previousPrimaryModelId,
    bool refreshCatalog = false,
  }) async {
    final skipPlan = buildSettingsOnlyPlan(settings);
    if (skipPlan != null) {
      return _outcomeFromPlan(skipPlan);
    }
    final targetModelId = settings.model.trim();
    var previousModelId = _normalizedPreviousModelId(
      previousPrimaryModelId,
      targetModelId,
    );

    LocalModelLifecycleCatalog? catalog;
    LocalModelLifecycleActionResult? unloadResult;
    PrimaryModelPreparationPlan? plan;
    if (previousModelId == null) {
      try {
        catalog = await listManagedModels(refresh: refreshCatalog);
      } on Object catch (error) {
        return PrimaryModelPreparationOutcome(
          modelId: targetModelId,
          status: PrimaryModelPreparationStatus.failed,
          message:
              'Failed to inspect the managed model catalog: '
              '${error.runtimeType}: $error',
        );
      }

      plan = buildPlan(modelId: targetModelId, catalog: catalog);
      if (plan.shouldLoad) {
        previousModelId = _readyDifferentModelId(catalog, targetModelId);
      }
    }

    if (previousModelId != null) {
      try {
        unloadResult = await unloadManagedModel(previousModelId);
      } on Object catch (error) {
        return PrimaryModelPreparationOutcome(
          modelId: targetModelId,
          previousModelId: previousModelId,
          status: PrimaryModelPreparationStatus.failed,
          message:
              'Failed to request managed model unload: '
              '${error.runtimeType}: $error',
        );
      }

      if (!unloadResult.succeeded) {
        return PrimaryModelPreparationOutcome(
          modelId: targetModelId,
          previousModelId: previousModelId,
          status: unloadResult.supported
              ? PrimaryModelPreparationStatus.failed
              : PrimaryModelPreparationStatus.unsupported,
          message: unloadResult.message,
          unloadActionResult: unloadResult,
        );
      }

      try {
        catalog = await listManagedModels(refresh: true);
      } on Object catch (error) {
        return PrimaryModelPreparationOutcome(
          modelId: targetModelId,
          previousModelId: previousModelId,
          status: PrimaryModelPreparationStatus.failed,
          message:
              'Failed to confirm managed model unload: '
              '${error.runtimeType}: $error',
          unloadActionResult: unloadResult,
        );
      }

      if (!catalog.supported) {
        return PrimaryModelPreparationOutcome(
          modelId: targetModelId,
          previousModelId: previousModelId,
          status: PrimaryModelPreparationStatus.unsupported,
          message:
              catalog.message ??
              'Managed model lifecycle is not supported by this endpoint.',
          unloadActionResult: unloadResult,
        );
      }

      if (!_isConfirmedUnloaded(catalog, previousModelId)) {
        return PrimaryModelPreparationOutcome(
          modelId: targetModelId,
          previousModelId: previousModelId,
          status: PrimaryModelPreparationStatus.failed,
          message:
              'Managed model catalog did not confirm "$previousModelId" '
              'is unloaded.',
          unloadActionResult: unloadResult,
        );
      }
      plan = null;
    }

    try {
      catalog ??= await listManagedModels(refresh: refreshCatalog);
    } on Object catch (error) {
      return PrimaryModelPreparationOutcome(
        modelId: targetModelId,
        previousModelId: previousModelId,
        status: PrimaryModelPreparationStatus.failed,
        message:
            'Failed to inspect the managed model catalog: '
            '${error.runtimeType}: $error',
        unloadActionResult: unloadResult,
      );
    }

    plan ??= buildPlan(modelId: targetModelId, catalog: catalog);
    if (!plan.shouldLoad) {
      return _outcomeFromPlan(
        plan,
        previousModelId: previousModelId,
        unloadActionResult: unloadResult,
      );
    }

    try {
      final result = await loadManagedModel(plan.modelId);
      if (result.succeeded) {
        return PrimaryModelPreparationOutcome(
          modelId: plan.modelId,
          previousModelId: previousModelId,
          status: PrimaryModelPreparationStatus.loadStarted,
          message: result.message,
          unloadActionResult: unloadResult,
          actionResult: result,
        );
      }
      return PrimaryModelPreparationOutcome(
        modelId: plan.modelId,
        previousModelId: previousModelId,
        status: result.supported
            ? PrimaryModelPreparationStatus.failed
            : PrimaryModelPreparationStatus.unsupported,
        message: result.message,
        unloadActionResult: unloadResult,
        actionResult: result,
      );
    } on Object catch (error) {
      return PrimaryModelPreparationOutcome(
        modelId: plan.modelId,
        previousModelId: previousModelId,
        status: PrimaryModelPreparationStatus.failed,
        message:
            'Failed to request managed model load: '
            '${error.runtimeType}: $error',
        unloadActionResult: unloadResult,
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

  String? _normalizedPreviousModelId(String? previousModelId, String targetId) {
    final normalized = previousModelId?.trim();
    if (normalized == null || normalized.isEmpty || normalized == targetId) {
      return null;
    }
    return normalized;
  }

  bool _isConfirmedUnloaded(
    LocalModelLifecycleCatalog catalog,
    String modelId,
  ) {
    final model = _findModel(catalog.models, modelId);
    return model?.state == LocalModelLifecycleState.unloaded;
  }

  String? _readyDifferentModelId(
    LocalModelLifecycleCatalog catalog,
    String targetModelId,
  ) {
    for (final model in catalog.models) {
      if (model.id == targetModelId) {
        continue;
      }
      if (model.state == LocalModelLifecycleState.loaded ||
          model.state == LocalModelLifecycleState.sleeping) {
        return model.id;
      }
    }
    return null;
  }

  PrimaryModelPreparationOutcome _outcomeFromPlan(
    PrimaryModelPreparationPlan plan, {
    String? previousModelId,
    LocalModelLifecycleActionResult? unloadActionResult,
  }) {
    return PrimaryModelPreparationOutcome(
      modelId: plan.modelId,
      previousModelId: previousModelId,
      status: plan.status,
      message: plan.message,
      unloadActionResult: unloadActionResult,
    );
  }
}
