import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/domain/entities/local_model_lifecycle.dart';
import 'package:caverno/features/settings/domain/services/primary_model_preparation_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PrimaryModelPreparationService', () {
    test('loads an unloaded OpenAI-compatible primary model', () async {
      final loadedModelIds = <String>[];
      final service = PrimaryModelPreparationService(
        listManagedModels: ({bool refresh = false}) async {
          expect(refresh, isTrue);
          return const LocalModelLifecycleCatalog.supported(
            models: [
              LocalManagedModel(
                id: 'qwen3.6-35b-a3b-vision',
                state: LocalModelLifecycleState.unloaded,
                statusValue: 'unloaded',
              ),
            ],
          );
        },
        loadManagedModel: (modelId) async {
          loadedModelIds.add(modelId);
          return LocalModelLifecycleActionResult.success(
            message: 'Requested load for "$modelId".',
          );
        },
      );

      final outcome = await service.preparePrimaryModel(
        settings: AppSettings.defaults().copyWith(
          model: 'qwen3.6-35b-a3b-vision',
        ),
        refreshCatalog: true,
      );

      expect(outcome.status, PrimaryModelPreparationStatus.loadStarted);
      expect(outcome.attemptedLoad, isTrue);
      expect(loadedModelIds, ['qwen3.6-35b-a3b-vision']);
    });

    test('does not load ready or in-progress models', () async {
      final service = PrimaryModelPreparationService(
        listManagedModels: ({bool refresh = false}) async {
          return const LocalModelLifecycleCatalog.supported(
            models: [
              LocalManagedModel(
                id: 'ready-model',
                state: LocalModelLifecycleState.sleeping,
                statusValue: 'sleeping',
              ),
              LocalManagedModel(
                id: 'loading-model',
                state: LocalModelLifecycleState.loading,
                statusValue: 'loading',
              ),
            ],
          );
        },
        loadManagedModel: (modelId) async {
          fail('Expected no load request for $modelId.');
        },
      );

      final readyOutcome = await service.preparePrimaryModel(
        settings: AppSettings.defaults().copyWith(model: 'ready-model'),
      );
      final loadingOutcome = await service.preparePrimaryModel(
        settings: AppSettings.defaults().copyWith(model: 'loading-model'),
      );

      expect(readyOutcome.status, PrimaryModelPreparationStatus.ready);
      expect(loadingOutcome.status, PrimaryModelPreparationStatus.inProgress);
    });

    test('skips unsupported providers before catalog inspection', () async {
      var catalogInspected = false;
      final service = PrimaryModelPreparationService(
        listManagedModels: ({bool refresh = false}) async {
          catalogInspected = true;
          return const LocalModelLifecycleCatalog.supported(models: []);
        },
        loadManagedModel: (modelId) async {
          fail('Expected no load request for $modelId.');
        },
      );

      final outcome = await service.preparePrimaryModel(
        settings: AppSettings.defaults().copyWith(
          llmProvider: LlmProvider.appleFoundationModels,
        ),
      );

      expect(outcome.status, PrimaryModelPreparationStatus.skipped);
      expect(catalogInspected, isFalse);
    });

    test('treats missing and unsupported lifecycle data as no-op', () {
      final service = PrimaryModelPreparationService(
        listManagedModels: ({bool refresh = false}) async {
          return const LocalModelLifecycleCatalog.supported(models: []);
        },
        loadManagedModel: (modelId) async {
          fail('Expected no load request for $modelId.');
        },
      );

      final missingPlan = service.buildPlan(
        modelId: 'missing-model',
        catalog: const LocalModelLifecycleCatalog.supported(models: []),
      );
      final unsupportedPlan = service.buildPlan(
        modelId: 'qwen3.6-27b-mtp-vision',
        catalog: const LocalModelLifecycleCatalog.unsupported(
          message: 'Lifecycle unsupported.',
        ),
      );

      expect(missingPlan.status, PrimaryModelPreparationStatus.missing);
      expect(unsupportedPlan.status, PrimaryModelPreparationStatus.unsupported);
      expect(missingPlan.shouldLoad, isFalse);
      expect(unsupportedPlan.shouldLoad, isFalse);
    });
  });
}
